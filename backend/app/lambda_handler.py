"""AWS Lambda entry point: the FastAPI app through Mangum, plus a migrate action.

Function URL requests are served by the same app that runs locally. Invoked
directly with ``{"action": "migrate"}`` the function applies the Alembic
migrations (and the demo seed, when enabled) instead. Function URL events never
carry that key, so no web request can trigger it.
"""

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from alembic.config import Config
from mangum import Mangum
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from alembic import command
from app.config import settings
from app.main import app

logger = logging.getLogger("meetings.lambda")

BASE_DIR = Path(__file__).resolve().parent.parent

# Mangum would otherwise run the app's startup and shutdown around every
# invocation. The demo seed that startup does locally runs in migrate instead,
# once per deploy.
http_handler = Mangum(app, lifespan="off")


async def _seed() -> None:
    from app.seed import seed_if_empty

    # A throwaway engine: the app's pooled connections belong to the event loop
    # Mangum serves requests on, and this one closes when the seed is done.
    engine = create_async_engine(settings.database_url, poolclass=NullPool)
    try:
        await seed_if_empty(async_sessionmaker(engine, expire_on_commit=False))
    finally:
        await engine.dispose()


def _migrate() -> None:
    config = Config(str(BASE_DIR / "alembic.ini"))
    config.set_main_option("script_location", str(BASE_DIR / "alembic"))
    command.upgrade(config, "head")
    logger.info("Migrations applied.")
    if settings.seed_demo_data:
        asyncio.run(_seed())


def handler(event, context):
    if isinstance(event, dict) and event.get("action") == "migrate":
        # alembic/env.py calls asyncio.run(), which would close and unset the
        # main thread's event loop that Mangum reuses across invocations. A
        # worker thread keeps the two apart. Errors propagate, so the invoke
        # reports a FunctionError and `make aws-migrate` fails loudly.
        with ThreadPoolExecutor(max_workers=1) as pool:
            pool.submit(_migrate).result()
        return {"status": "migrated"}
    return http_handler(event, context)
