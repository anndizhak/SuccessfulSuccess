"""The weekly meetings report: one ISO week in, one CSV file out.

No AWS in here. The caller decides which week to build; nothing in this module
means "last week". The same week always maps to the same S3 key and the same
bytes, so building a report twice overwrites one file with an identical one,
which is what makes at-least-once delivery harmless.

Run it locally against the compose database:

    docker compose exec backend python -m app.reports.weekly 2026-W40
"""

import asyncio
import csv
import io
import re
import sys
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import settings
from app.models import Meeting

WEEK_PATTERN = re.compile(r"^(\d{4})-W(\d{2})$")
LONGEST_COUNT = 5


class InvalidWeekError(ValueError):
    """Raised for anything that is not an existing ISO week such as "2026-W40"."""


def week_monday(week: str) -> date:
    """The Monday of an ISO week given as "YYYY-Www"."""
    match = WEEK_PATTERN.match(week) if isinstance(week, str) else None
    if match is None:
        raise InvalidWeekError(f"Not an ISO week like 2026-W40: {week!r}")
    year, number = int(match.group(1)), int(match.group(2))
    try:
        return date.fromisocalendar(year, number, 1)
    except ValueError as error:  # e.g. week 53 of a year that has 52
        raise InvalidWeekError(f"{week} does not exist: {error}") from error


def iso_week(day: date) -> str:
    year, number, _ = day.isocalendar()
    return f"{year}-W{number:02d}"


def previous_week(week: str) -> str:
    return iso_week(week_monday(week) - timedelta(days=7))


def week_window(week: str) -> tuple[datetime, datetime]:
    """[Monday 00:00, next Monday 00:00) of the week, in the application timezone."""
    monday = week_monday(week)
    start = datetime.combine(monday, time.min, tzinfo=settings.tz)
    end = datetime.combine(monday + timedelta(days=7), time.min, tzinfo=settings.tz)
    return start, end


def report_key(week: str) -> str:
    """Where a week's report lives. One week, one key: rebuilding overwrites it."""
    week_monday(week)  # validate before it becomes part of an S3 key
    return f"reports/{week}.csv"


async def meetings_starting_in(session: AsyncSession, week: str) -> list[Meeting]:
    """Meetings that start in the week. A meeting belongs to the week it starts
    in, so one that runs past Sunday midnight is counted once, not twice."""
    start, end = week_window(week)
    result = await session.scalars(
        select(Meeting)
        .where(Meeting.starts_at >= start, Meeting.starts_at < end)
        .order_by(Meeting.starts_at, Meeting.name, Meeting.id)
    )
    return list(result)


def _hours(meeting: Meeting) -> Decimal:
    seconds = (meeting.ends_at - meeting.starts_at).total_seconds()
    return Decimal(str(seconds)) / Decimal(3600)


def _round(value: Decimal) -> Decimal:
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _signed(value: Decimal | int) -> str:
    if isinstance(value, Decimal):
        value = _round(value)
    return f"+{value}" if value > 0 else str(value)


def _local(moment: datetime) -> str:
    return moment.astimezone(settings.tz).strftime("%Y-%m-%d %H:%M")


async def render_weekly_report(session: AsyncSession, week: str) -> bytes:
    """Build the CSV for one ISO week from an open session."""
    before = previous_week(week)
    this_week = await meetings_starting_in(session, week)
    last_week = await meetings_starting_in(session, before)

    hours_now = sum((_hours(m) for m in this_week), Decimal(0))
    hours_before = sum((_hours(m) for m in last_week), Decimal(0))
    start, end = week_window(week)

    out = io.StringIO()
    rows = csv.writer(out)

    rows.writerow(["Weekly meetings report", week])
    rows.writerow(
        [
            "Period",
            f"{start:%Y-%m-%d} to {(end - timedelta(days=1)):%Y-%m-%d}",
            settings.app_timezone,
        ]
    )
    rows.writerow([])

    rows.writerow(["Summary", f"This week ({week})", f"Previous week ({before})", "Change"])
    rows.writerow(
        ["Meetings", len(this_week), len(last_week), _signed(len(this_week) - len(last_week))]
    )
    rows.writerow(
        [
            "Hours",
            _round(hours_now),
            _round(hours_before),
            _signed(hours_now - hours_before),
        ]
    )
    rows.writerow([])

    longest = sorted(this_week, key=lambda m: (-_hours(m), m.starts_at, m.name, str(m.id)))
    rows.writerow([f"Longest meetings (top {LONGEST_COUNT})"])
    rows.writerow(["Title", "Start", "Duration (h)", "Participants"])
    for meeting in longest[:LONGEST_COUNT]:
        rows.writerow(
            [
                meeting.name,
                _local(meeting.starts_at),
                _round(_hours(meeting)),
                len(meeting.participants),
            ]
        )
    rows.writerow([])

    # Per person: the schema has no organisers, so participants are the people.
    # Someone with an email is one person across meetings; without one, the name is.
    people: dict[str, dict] = defaultdict(lambda: {"meetings": 0, "hours": Decimal(0)})
    for meeting in this_week:
        for participant in meeting.participants:
            key = (participant.email or participant.name).casefold()
            person = people[key]
            person.setdefault(
                "label",
                f"{participant.name} <{participant.email}>"
                if participant.email
                else participant.name,
            )
            person["meetings"] += 1
            person["hours"] += _hours(meeting)

    rows.writerow(["Per participant"])
    rows.writerow(["Participant", "Meetings", "Hours"])
    for person in sorted(
        people.values(), key=lambda p: (-p["hours"], -p["meetings"], p["label"].casefold())
    ):
        rows.writerow([person["label"], person["meetings"], _round(person["hours"])])

    # A BOM so that Excel opens the UTF-8 file with Cyrillic names intact.
    return out.getvalue().encode("utf-8-sig")


async def _build(week: str) -> bytes:
    # A short-lived engine of its own: the caller may be a Lambda handler or a
    # script with no event loop, and nothing should outlive one report.
    engine = create_async_engine(settings.database_url, poolclass=NullPool)
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            return await render_weekly_report(session, week)
    finally:
        await engine.dispose()


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    week_monday(week)  # fail fast, before opening a connection
    return asyncio.run(_build(week))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python -m app.reports.weekly 2026-W40")
    sys.stdout.buffer.write(build_weekly_report(sys.argv[1]))
