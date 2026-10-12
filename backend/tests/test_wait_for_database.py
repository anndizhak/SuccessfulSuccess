"""Tests for wait_for_database: retry while unreachable, never on real errors."""

import time

import pytest
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError

from app.config import settings
from app.db import wait_for_database


async def test_returns_at_once_when_the_database_is_up():
    assert await wait_for_database() == 1


async def test_retries_an_unreachable_database_until_the_deadline():
    # Nothing listens on port 1: every attempt is refused, a transient error.
    unreachable = "postgresql+asyncpg://app:app@127.0.0.1:1/meetings"
    started = time.monotonic()

    with pytest.raises(OSError):
        await wait_for_database(unreachable, total=1.0, attempt_timeout=1.0, pause=0.2)

    assert 0.9 <= time.monotonic() - started < 5


async def test_does_not_retry_a_wrong_password():
    wrong = make_url(settings.database_url).set(password="not-the-password")
    started = time.monotonic()

    with pytest.raises(DBAPIError):
        await wait_for_database(wrong.render_as_string(hide_password=False), total=30.0)

    assert time.monotonic() - started < 5
