"""AWS Lambda entry point of the agenda parser, behind its function URL.

Same container image as the API, different handler (ImageConfig.Command in
infra/ai.yml). It runs outside the VPC: it needs Bedrock and Cognito's public
keys, never the database. It receives text and returns a suggested agenda; it
never writes anything. Saving goes through the main API, as before.

POST {"text": "...", "today": "2026-10-21", "tz": "Europe/Kyiv"}
with `Authorization: Bearer <Cognito access token>`.

  200 {"agenda": {...}, "model": ..., "prompt_version": ...}
  400 the body is not what is expected      401 not signed in
  413 text longer than 10,000 characters    422 no agenda in the text
  429 Bedrock is throttling: try again      502 the model call failed
"""

import base64
import json
import logging
import time
from datetime import date
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, Field, ValidationError, field_validator

from app.ai.agenda import (
    MAX_TEXT_CHARS,
    PROMPT_VERSION,
    AgendaParseError,
    TextTooLongError,
    parse_agenda,
)
from app.ai.cognito import Unauthorized, verify_cognito_token
from app.ai.pricing import cost_usd
from app.config import settings

log = logging.getLogger("meetings.ai")
log.setLevel(logging.INFO)


class ParseRequest(BaseModel):
    text: str = Field(min_length=1)
    today: date  # the user's today: their "Monday" is in their time zone
    tz: str

    @field_validator("tz")
    @classmethod
    def _known_zone(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise ValueError(f"unknown time zone: {value}") from error
        return value


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _error(status: int, code: str, message: str) -> dict:
    return _response(status, {"error": {"code": code, "message": message}})


def _is_throttling(error: Exception) -> bool:
    """Bedrock's "slow down", from either API: the user may simply retry."""
    if getattr(error, "status_code", None) == 429:  # anthropic.RateLimitError
        return True
    code = getattr(error, "response", {}).get("Error", {}).get("Code", "")  # botocore
    return code in ("ThrottlingException", "TooManyRequestsException", "ServiceQuotaExceeded")


def handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    try:
        user = verify_cognito_token(headers.get("authorization", ""))
    except Unauthorized as error:
        log.info("agenda_parse_rejected", extra={"event": "unauthorized", "reason": str(error)})
        return _error(401, "unauthorized", "Sign in to parse an agenda.")

    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return _error(400, "bad_request", "The body must be JSON.")
    # Before validating anything else: an oversized text costs nothing to reject.
    if isinstance(payload, dict) and len(str(payload.get("text") or "")) > MAX_TEXT_CHARS:
        return _error(
            413, "text_too_long", f"The text is longer than {MAX_TEXT_CHARS:,} characters."
        )
    try:
        request = ParseRequest.model_validate(payload)
    except ValidationError as error:
        first = error.errors()[0]
        field = ".".join(str(p) for p in first["loc"])
        return _error(400, "bad_request", f"{field}: {first['msg']}")

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(request.text, request.today, request.tz)
    except TextTooLongError as error:
        return _error(413, "text_too_long", str(error))
    except AgendaParseError as error:
        log.info(
            "agenda_parse_failed",
            extra={"event": "no_agenda", "user": user.sub, "reason": str(error)},
        )
        return _error(422, "no_agenda", "Could not find an agenda in this text.")
    except Exception as error:
        if _is_throttling(error):
            log.warning("agenda_parse_throttled", extra={"event": "throttled", "user": user.sub})
            return _error(429, "busy", "The AI service is busy. Try again in a moment.")
        log.exception("agenda_parse_error", extra={"event": "model_error", "user": user.sub})
        return _error(502, "model_error", "The AI service failed. Type the agenda by hand.")

    latency_ms = int((time.monotonic() - started) * 1000)
    # One line per parse: who, which model and prompt, what it took and cost.
    # Not the text itself: it is the user's data, and it can be personal.
    log.info(
        "agenda_parsed",
        extra={
            "event": "agenda_parsed",
            "user": user.sub,
            "model": settings.parser_model,
            "api": settings.parser_api,
            "prompt_version": PROMPT_VERSION,
            "input_tokens": usage["input_tokens"],
            "output_tokens": usage["output_tokens"],
            "attempts": usage["attempts"],
            "latency_ms": latency_ms,
            "cost_usd": cost_usd(settings.parser_model, usage),
            "text_chars": len(request.text),
            "items": len(agenda.items),
        },
    )
    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
        },
    )
