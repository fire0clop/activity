import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

import redis.asyncio as aioredis
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

import app.models  # noqa: F401  (регистрирует таблицы в Base.metadata)
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.exceptions import register_exception_handlers
from app.core.logging import setup_logging
from app.core.middleware import (
    RateLimitMiddleware,
    RequestContextMiddleware,
    SecurityHeadersMiddleware,
)
from app.db.base import Base
from app.db.session import engine
from app.services.lifecycle import run_sweeper
from app.services.storage_service import S3Storage, get_storage
from app.ws.manager import manager

setup_logging()
logger = logging.getLogger("app")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.validate_for_prod()  # fail-fast на небезопасной прод-конфигурации

    app.state.redis = aioredis.from_url(settings.redis_url, decode_responses=False)
    await manager.start(app.state.redis)

    Path(settings.media_root).mkdir(parents=True, exist_ok=True)

    if settings.storage_backend == "s3":
        storage = get_storage()
        if isinstance(storage, S3Storage):
            await storage.ensure_bucket()

    async with engine.begin() as conn:
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
        if settings.auto_create_tables:
            await conn.run_sync(Base.metadata.create_all)

    sweeper = asyncio.create_task(run_sweeper())
    logger.info("startup complete (env=%s, storage=%s)", settings.app_env, settings.storage_backend)

    yield

    sweeper.cancel()
    await manager.stop()
    await app.state.redis.aclose()
    await engine.dispose()


app = FastAPI(title="Сходка API", version="1.0.0", lifespan=lifespan)

app.add_middleware(RateLimitMiddleware)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestContextMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

register_exception_handlers(app)

# Раздача медиа в dev (в проде/при S3 — Nginx или сам S3).
if settings.storage_backend == "local":
    Path(settings.media_root).mkdir(parents=True, exist_ok=True)
    app.mount("/media", StaticFiles(directory=settings.media_root), name="media")

app.include_router(api_router, prefix=settings.api_v1_prefix)


@app.get("/")
async def root() -> dict:
    return {"service": "skhodka-api", "docs": "/docs", "health": f"{settings.api_v1_prefix}/health"}
