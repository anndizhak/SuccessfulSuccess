"""Database engine, session factory and the FastAPI session dependency."""

import asyncio
import logging
from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.config import settings

logger = logging.getLogger("meetings.db")

# asyncpg errors that mean "not reachable yet", not "something is wrong".
_TRANSIENT_ASYNCPG_ERRORS = {"CannotConnectNowError", "ConnectionDoesNotExistError"}


class Base(DeclarativeBase):
    """Declarative base for every ORM model."""


engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

SessionFactory = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """Yield a session and roll back if the request handler raises."""
    async with SessionFactory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


def _is_transient(error: BaseException) -> bool:
    cause = error.orig if isinstance(error, DBAPIError) else error
    return isinstance(cause, OSError) or type(cause).__name__ in _TRANSIENT_ASYNCPG_ERRORS


async def wait_for_database(
    url: str | None = None,
    *,
    total: float = 40.0,
    attempt_timeout: float = 10.0,
    pause: float = 2.0,
) -> int:
    """Return once the database accepts a connection; the number of attempts it took.

    A paused Aurora Serverless cluster takes ~15 s to resume, and connections
    made in that time time out. Code that runs without a user waiting (the
    migration step of a deploy, the weekly report) retries for up to `total`
    seconds instead of failing on the first attempt. Only connection problems
    are retried: a wrong password or a broken query still fails at once.
    """
    loop = asyncio.get_running_loop()
    deadline = loop.time() + total
    engine = create_async_engine(
        url or settings.database_url,
        poolclass=NullPool,
        connect_args={"timeout": attempt_timeout},
    )
    attempt = 0
    try:
        while True:
            attempt += 1
            try:
                async with engine.connect() as connection:
                    await connection.execute(text("SELECT 1"))
                return attempt
            except (OSError, DBAPIError) as error:
                remaining = deadline - loop.time()
                if not _is_transient(error) or remaining <= 0:
                    raise
                logger.warning(
                    "Database not reachable yet (attempt %d, %.0f s left): %r",
                    attempt,
                    remaining,
                    error,
                )
                await asyncio.sleep(min(pause, remaining))
    finally:
        await engine.dispose()
