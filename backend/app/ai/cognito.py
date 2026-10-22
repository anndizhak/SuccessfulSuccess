"""Verify a Cognito access token: the parser only answers signed-in users.

Every parse costs money, so an anonymous caller gets 401 before any model is
called. The token's signature is checked against the user pool's public keys
(JWKS, fetched over the internet, which is why the parser runs outside the VPC)
and cached; then its expiry, its issuer, that it is an access token, and that
it was issued to this app's client.
"""

from dataclasses import dataclass
from functools import lru_cache

import jwt

from app.config import settings


class Unauthorized(Exception):
    """No token, or one that this pool and client did not issue (→ 401)."""


@dataclass(frozen=True)
class User:
    sub: str
    username: str | None


def issuer() -> str:
    return f"https://cognito-idp.{settings.bedrock_region}.amazonaws.com/{settings.cognito_user_pool_id}"


@lru_cache(maxsize=1)
def _jwks() -> jwt.PyJWKClient:
    # One client per warm Lambda: it caches the keys, so they are fetched once,
    # not on every request.
    return jwt.PyJWKClient(f"{issuer()}/.well-known/jwks.json", cache_keys=True)


def verify_cognito_token(authorization: str) -> User:
    if not settings.cognito_user_pool_id or not settings.cognito_client_id:
        raise Unauthorized("sign-in is not configured")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise Unauthorized("missing bearer token")
    try:
        key = _jwks().get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            issuer=issuer(),
            options={"require": ["exp", "iss", "sub", "token_use"]},
        )
    except jwt.PyJWTError as error:
        raise Unauthorized(f"invalid token: {error}") from error
    # Cognito access tokens carry the app client in client_id (ID tokens carry
    # it in aud instead, and are not accepted here).
    if claims.get("token_use") != "access":
        raise Unauthorized("not an access token")
    if claims.get("client_id") != settings.cognito_client_id:
        raise Unauthorized("token was issued to another client")
    return User(sub=claims["sub"], username=claims.get("username"))
