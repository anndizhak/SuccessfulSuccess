"""Tests for the report builder's Lambda handler: triggers, weeks, event shapes."""

import json
from datetime import datetime

import pytest

from app.config import settings
from app.reports import lambda_handler as builder


@pytest.fixture
def stored(monkeypatch):
    """Run the handler without AWS or a database: record what would be stored."""
    uploads: list[tuple[str, str, bytes]] = []
    monkeypatch.setenv("REPORTS_BUCKET", "test-reports")
    monkeypatch.setattr(builder, "wait_for_database", _ready)
    monkeypatch.setattr(builder, "build_weekly_report", lambda week: f"csv {week}".encode())
    monkeypatch.setattr(builder, "_upload", lambda *args: uploads.append(args))
    return uploads


async def _ready() -> int:
    return 1


def _sqs(*bodies: dict) -> dict:
    return {
        "Records": [
            {"eventSource": "aws:sqs", "messageId": str(i), "body": json.dumps(body)}
            for i, body in enumerate(bodies)
        ]
    }


@pytest.mark.parametrize(
    ("event", "trigger"),
    [
        ({"source": "schedule"}, "schedule"),
        ({"source": "manual", "week": "2026-W40"}, "manual"),
        ({}, "manual"),
        (None, "manual"),
        (_sqs({"week": None, "source": "schedule"}), "sqs"),
        ({"Records": [{"eventSource": "aws:s3"}]}, "unknown"),
    ],
)
def test_detect_trigger(event, trigger):
    assert builder.detect_trigger(event) == trigger


def test_default_week_is_the_previous_iso_week_in_the_app_timezone():
    # Monday 5 October 2026, 07:00 in Kyiv: the report is for 28 Sep – 4 Oct.
    monday_morning = datetime(2026, 10, 5, 7, 0, tzinfo=settings.tz)
    assert builder.default_week(monday_morning) == "2026-W40"


def test_schedule_without_a_week_builds_last_week(stored, monkeypatch, caplog):
    monkeypatch.setattr(builder, "default_week", lambda: "2026-W40")

    result = builder.handler({"source": "schedule"}, None)

    assert result == {
        "trigger": "schedule",
        "reports": [{"week": "2026-W40", "key": "reports/2026-W40.csv", "bytes": 12}],
    }
    assert stored == [("test-reports", "reports/2026-W40.csv", b"csv 2026-W40")]
    assert "report-builder triggered trigger=schedule week=2026-W40" in caplog.text


def test_direct_invocation_with_a_week(stored):
    builder.handler({"source": "manual", "week": "2026-W39"}, None)

    assert [key for _, key, _ in stored] == ["reports/2026-W39.csv"]


def test_sqs_record_body_carries_the_week(stored, caplog):
    result = builder.handler(_sqs({"week": "2026-W38", "source": "make"}), None)

    assert result["trigger"] == "sqs"
    assert [key for _, key, _ in stored] == ["reports/2026-W38.csv"]
    assert "trigger=sqs week=2026-W38 source=make" in caplog.text


def test_an_invalid_week_raises_so_sqs_can_retry(stored):
    with pytest.raises(ValueError):
        builder.handler(_sqs({"week": "2026-W99"}), None)
    assert stored == []


def test_scheduled_sqs_message_without_a_week_builds_last_week(stored, monkeypatch, caplog):
    # What EventBridge Scheduler now puts on the queue every Monday.
    monkeypatch.setattr(builder, "default_week", lambda: "2026-W41")

    result = builder.handler(_sqs({"week": None, "source": "schedule"}), None)

    assert result["trigger"] == "sqs"
    assert [key for _, key, _ in stored] == ["reports/2026-W41.csv"]
    assert "trigger=sqs week=2026-W41 source=schedule" in caplog.text
