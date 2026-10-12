"""Tests for the weekly report: ISO weeks, week boundaries, contents, idempotency."""

import csv
import io
from datetime import datetime, timedelta

import pytest

from app.reports.weekly import (
    InvalidWeekError,
    previous_week,
    render_weekly_report,
    report_key,
    week_monday,
    week_window,
)

WEEK = "2026-W40"  # Monday 28 September to Sunday 4 October 2026


def _at(day_offset: float, hours: float = 0) -> datetime:
    start, _ = week_window(WEEK)
    return start + timedelta(days=day_offset, hours=hours)


async def _create(client, name, starts_at, minutes, participants=()):
    response = await client.post(
        "/api/v1/meetings",
        json={
            "name": name,
            "starts_at": starts_at.isoformat(),
            "ends_at": (starts_at + timedelta(minutes=minutes)).isoformat(),
            "participants": [dict(p) for p in participants],
        },
    )
    assert response.status_code == 201, response.text


def _sections(report: bytes) -> list[list[list[str]]]:
    """The CSV split into its blank-line-separated sections."""
    assert report.startswith(b"\xef\xbb\xbf"), "expected a UTF-8 BOM for Excel"
    sections: list[list[list[str]]] = [[]]
    for row in csv.reader(io.StringIO(report.decode("utf-8-sig"))):
        if row:
            sections[-1].append(row)
        else:
            sections.append([])
    return sections


@pytest.mark.parametrize(
    ("week", "previous"),
    [("2026-W40", "2026-W39"), ("2026-W01", "2025-W52"), ("2027-W01", "2026-W53")],
)
def test_previous_week_crosses_years(week, previous):
    assert previous_week(week) == previous


@pytest.mark.parametrize("week", ["2026-40", "2026-W4", "W40", "2025-W53", "", None])
def test_invalid_weeks_are_rejected(week):
    with pytest.raises(InvalidWeekError):
        week_monday(week)


def test_report_key_is_one_file_per_week():
    assert report_key(WEEK) == "reports/2026-W40.csv"
    with pytest.raises(InvalidWeekError):
        report_key("../../etc/passwd")


async def test_report_counts_this_and_previous_week(client, session):
    # This week: 1 h + 2.5 h + a meeting starting Sunday 23:30 that ends on Monday.
    await _create(client, "Planning", _at(0, 10), 60, [{"name": "Ostap"}])
    await _create(
        client,
        "Workshop",
        _at(2, 9),
        150,
        [{"name": "Iryna", "email": "iryna@example.com"}, {"name": "Ostap"}],
    )
    await _create(client, "Late call", _at(6, 23.5), 60)
    # Previous week: one 30-minute meeting. Next week: must not be counted.
    await _create(client, "Retro", _at(-3, 15), 30)
    await _create(client, "Next Monday", _at(7, 0), 45)

    summary, longest, people = _sections(await render_weekly_report(session, WEEK))[1:]

    assert summary == [
        ["Summary", "This week (2026-W40)", "Previous week (2026-W39)", "Change"],
        ["Meetings", "3", "1", "+2"],
        ["Hours", "4.50", "0.50", "+4.00"],
    ]
    assert longest[2:] == [
        ["Workshop", "2026-09-30 09:00", "2.50", "2"],
        ["Planning", "2026-09-28 10:00", "1.00", "1"],
        ["Late call", "2026-10-04 23:30", "1.00", "0"],
    ]
    assert people[2:] == [
        ["Ostap", "2", "3.50"],
        ["Iryna <iryna@example.com>", "1", "2.50"],
    ]


async def test_only_the_five_longest_meetings_are_listed(client, session):
    for minutes in (15, 30, 45, 60, 75, 90):
        await _create(client, f"{minutes} min", _at(1, 8), minutes)

    longest = _sections(await render_weekly_report(session, WEEK))[2]

    assert [row[0] for row in longest[2:]] == ["90 min", "75 min", "60 min", "45 min", "30 min"]


async def test_empty_week_and_drop_against_previous(client, session):
    await _create(client, "Retro", _at(-3, 15), 30)

    summary = _sections(await render_weekly_report(session, WEEK))[1]

    assert summary[1] == ["Meetings", "0", "1", "-1"]
    assert summary[2] == ["Hours", "0.00", "0.50", "-0.50"]


async def test_same_week_gives_identical_bytes(client, session):
    await _create(client, "Planning", _at(0, 10), 60, [{"name": "бабілка"}])

    first = await render_weekly_report(session, WEEK)
    second = await render_weekly_report(session, WEEK)

    assert first == second
    assert "бабілка".encode() in first
