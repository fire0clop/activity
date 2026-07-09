"""Фикстуры тестов. Требуют поднятые db(postgis)+redis (как в docker compose).

Запуск: docker compose exec api pytest -q
Каждый тест работает на чистой схеме (drop_all + create_all) для изоляции.
"""

import uuid
from collections.abc import AsyncGenerator

import httpx
import pytest_asyncio
from asgi_lifespan import LifespanManager
from sqlalchemy import text

import app.models  # noqa: F401
from app.db.base import Base
from app.db.session import engine
from app.main import app


@pytest_asyncio.fixture(scope="function", autouse=True)
async def _clean_state() -> AsyncGenerator[None, None]:
    import redis.asyncio as aioredis

    from app.core.config import settings

    async with engine.begin() as conn:
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
        # Добиваем чужие соединения к тестовой БД: утёкшая 'idle in transaction'
        # сессия из аварийно завершённого теста иначе вешает drop_all навсегда.
        await conn.execute(text(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
            "WHERE datname = current_database() AND pid <> pg_backend_pid()"
        ))
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    # Чистим Redis (OTP-кулдауны, rate-limit, presence), чтобы тесты не влияли друг на друга.
    redis = aioredis.from_url(settings.redis_url)
    await redis.flushdb()
    await redis.aclose()
    yield


@pytest_asyncio.fixture
async def client() -> AsyncGenerator[httpx.AsyncClient, None]:
    async with LifespanManager(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test/api/v1") as c:
            yield c


async def _login(client: httpx.AsyncClient, phone: str, password: str = "secret123") -> str:
    """Регистрация: код из Redis (в обход SMS) + пароль. Возвращает access-токен."""
    import redis.asyncio as aioredis

    from app.core.config import settings

    await client.post("/auth/request-code", json={"phone": phone})
    redis = aioredis.from_url(settings.redis_url)
    code = (await redis.get(f"otp:{phone}")).decode()
    await redis.aclose()
    # Шаг 2: подтверждаем код → тикет. Шаг 3: тикет + пароль → аккаунт.
    verify = await client.post("/auth/verify-code", json={"phone": phone, "code": code})
    token = verify.json()["verification_token"]
    resp = await client.post(
        "/auth/register", json={"verification_token": token, "password": password})
    return resp.json()["access_token"]


async def _complete_profile(client: httpx.AsyncClient, token: str, name: str) -> None:
    h = {"Authorization": f"Bearer {token}"}
    await client.patch("/users/me", headers=h, json={"name": name, "bio": "тест"})
    png = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06"
        b"\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05"
        b"\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    await client.post(
        "/users/me/avatar", headers=h, files={"file": ("a.png", png, "image/png")}
    )


@pytest_asyncio.fixture
async def user_factory(client: httpx.AsyncClient):
    async def make(name: str, complete: bool = True) -> dict:
        phone = "+7999" + f"{uuid.uuid4().int % 10_000_000:07d}"
        token = await _login(client, phone)
        if complete:
            await _complete_profile(client, token, name)
        me = (await client.get("/users/me", headers={"Authorization": f"Bearer {token}"})).json()
        return {"token": token, "headers": {"Authorization": f"Bearer {token}"}, "id": me["id"],
                "phone": phone, "name": name}

    return make
