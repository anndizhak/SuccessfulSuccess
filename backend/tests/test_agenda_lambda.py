"""Tests for the parser's Lambda handler: auth, limits, errors, the log line.

Tokens are signed with a test RSA key, so the signature, expiry, issuer and
client checks run for real; only the JWKS download and the model are faked.
"""

import json
import time
from datetime import date

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.ai import agenda_lambda, cognito
from app.ai.agenda import AgendaParseError, ParsedAgenda
from app.config import settings

POOL = "us-east-1_TESTPOOL"
CLIENT = "testclient123"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
AGENDA = ParsedAgenda.model_validate(
    {"title": "Sync", "items": [{"topic": "Pricing", "owner": "Олена"}], "language": "uk"}
)
BODY = {"text": "Пн 10:00, синк по прайсингу", "today": "2026-10-21", "tz": "Europe/Kyiv"}


class _FakeJwks:
    def get_signing_key_from_jwt(self, token):
        class _Key:
            key = KEY.public_key()

        return _Key()


@pytest.fixture(autouse=True)
def configured(monkeypatch):
    monkeypatch.setattr(settings, "cognito_user_pool_id", POOL)
    monkeypatch.setattr(settings, "cognito_client_id", CLIENT)
    monkeypatch.setattr(settings, "parser_model", "anthropic.claude-opus-5-5")
    monkeypatch.setattr(cognito, "_jwks", lambda: _FakeJwks())


def token(signing_key=KEY, **claims) -> str:
    now = int(time.time())
    body = {
        "sub": "user-123",
        "username": "google_1234",
        "iss": f"https://cognito-idp.us-east-1.amazonaws.com/{POOL}",
        "token_use": "access",
        "client_id": CLIENT,
        "iat": now,
        "exp": now + 3600,
    } | claims
    return jwt.encode(body, signing_key, algorithm="RS256")


def call(body=BODY, authorization=None) -> tuple[int, dict]:
    headers = {"Authorization": authorization if authorization is not None else f"Bearer {token()}"}
    result = agenda_lambda.handler({"headers": headers, "body": json.dumps(body)}, None)
    return result["statusCode"], json.loads(result["body"])


@pytest.fixture
def parsed(monkeypatch):
    calls = []

    def fake_parse(text, today, tz):
        calls.append((text, today, tz))
        return AGENDA, {"input_tokens": 1500, "output_tokens": 300, "attempts": 1}

    monkeypatch.setattr(agenda_lambda, "parse_agenda", fake_parse)
    return calls


def test_a_signed_in_user_gets_the_agenda_and_one_log_line(parsed, caplog):
    status, body = call()

    assert status == 200
    assert body["agenda"]["items"][0]["owner"] == "Олена"
    assert body["model"] == "anthropic.claude-opus-5-5"
    assert body["prompt_version"] == "agenda-v1"
    assert parsed == [("Пн 10:00, синк по прайсингу", date(2026, 10, 21), "Europe/Kyiv")]

    [record] = [r for r in caplog.records if r.getMessage() == "agenda_parsed"]
    assert record.user == "user-123"
    assert record.model == "anthropic.claude-opus-5-5"
    assert record.prompt_version == "agenda-v1"
    assert (record.input_tokens, record.output_tokens) == (1500, 300)
    assert record.cost_usd == 0.012  # 1,500 × $4/M + 300 × $20/M
    assert isinstance(record.latency_ms, int)
    assert "синк" not in caplog.text  # the pasted text is never logged


@pytest.mark.parametrize(
    "authorization",
    [
        "",
        "Basic dXNlcjpwYXNz",
        f"Bearer {token(exp=int(time.time()) - 10)}",  # expired
        f"Bearer {token(client_id='someone-else')}",  # another app client
        f"Bearer {token(token_use='id')}",  # an ID token, not an access token
        f"Bearer {token(iss='https://evil.example.com')}",
        f"Bearer {token(signing_key=OTHER_KEY)}",  # not signed by the pool
    ],
)
def test_anything_but_a_valid_access_token_is_401(parsed, authorization):
    status, body = call(authorization=authorization)

    assert status == 401
    assert body["error"]["code"] == "unauthorized"
    assert parsed == []  # no model call, no cost


def test_text_over_10000_characters_is_413_before_the_model(parsed):
    status, body = call(BODY | {"text": "x" * 10_001})

    assert status == 413
    assert body["error"]["code"] == "text_too_long"
    assert parsed == []


@pytest.mark.parametrize(
    "body",
    [
        {"text": "x", "today": "Monday", "tz": "Europe/Kyiv"},
        {"text": "x", "today": "2026-10-21", "tz": "Mars/Olympus"},
        {"text": "", "today": "2026-10-21", "tz": "Europe/Kyiv"},
        {"today": "2026-10-21", "tz": "Europe/Kyiv"},
    ],
)
def test_a_malformed_request_is_400(parsed, body):
    status, response = call(body)

    assert status == 400
    assert parsed == []


def test_no_agenda_in_the_text_is_422(monkeypatch):
    def no_agenda(text, today, tz):
        raise AgendaParseError("no agenda returned (stop_reason=end_turn)")

    monkeypatch.setattr(agenda_lambda, "parse_agenda", no_agenda)

    status, body = call()

    assert status == 422
    assert body["error"]["code"] == "no_agenda"


class _AnthropicRateLimit(Exception):
    status_code = 429


class _BotoThrottling(Exception):
    response = {"Error": {"Code": "ThrottlingException"}}


@pytest.mark.parametrize("error", [_AnthropicRateLimit(), _BotoThrottling()])
def test_throttling_from_either_api_is_429(monkeypatch, error):
    def throttled(text, today, tz):
        raise error

    monkeypatch.setattr(agenda_lambda, "parse_agenda", throttled)

    status, body = call()

    assert status == 429
    assert body["error"]["code"] == "busy"


def test_any_other_model_failure_is_502(monkeypatch):
    def broken(text, today, tz):
        raise RuntimeError("AccessDeniedException: model not available")

    monkeypatch.setattr(agenda_lambda, "parse_agenda", broken)

    status, body = call()

    assert status == 502
    assert body["error"]["code"] == "model_error"
