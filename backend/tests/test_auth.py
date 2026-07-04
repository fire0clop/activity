import pytest
import redis.asyncio as aioredis

from app.core.config import settings


async def _get_code(client, phone: str) -> str:
    """Сбрасывает cooldown, запрашивает код и достаёт его из Redis (в обход SMS)."""
    redis = aioredis.from_url(settings.redis_url)
    await redis.delete(f"otp_cooldown:{phone}")
    await client.post("/auth/request-code", json={"phone": phone})
    code = (await redis.get(f"otp:{phone}")).decode()
    await redis.aclose()
    return code


@pytest.mark.asyncio
async def test_request_code_cooldown(client) -> None:
    phone = "+79990001100"
    r1 = await client.post("/auth/request-code", json={"phone": phone})
    assert r1.status_code == 200
    r2 = await client.post("/auth/request-code", json={"phone": phone})
    assert r2.status_code == 429
    assert r2.json()["error"]["code"] == "rate_limited"


@pytest.mark.asyncio
async def test_register_bad_and_expired_code(client) -> None:
    phone = "+79990001101"
    await client.post("/auth/request-code", json={"phone": phone})
    bad = await client.post("/auth/register",
                            json={"phone": phone, "code": "000000", "password": "secret123"})
    assert bad.status_code == 400
    assert bad.json()["error"]["code"] == "invalid_code"

    no_code = await client.post("/auth/register",
                                json={"phone": "+79990009999", "code": "123456", "password": "secret123"})
    assert no_code.status_code == 410
    assert no_code.json()["error"]["code"] == "code_expired"


@pytest.mark.asyncio
async def test_register_then_login_with_password(client) -> None:
    phone = "+79990001102"
    reg = await client.post("/auth/register",
                            json={"phone": phone, "code": await _get_code(client, phone), "password": "secret123"})
    assert reg.status_code == 200
    assert reg.json()["is_new_user"] is True

    # повторная регистрация того же номера — нельзя
    dup = await client.post("/auth/register",
                            json={"phone": phone, "code": await _get_code(client, phone), "password": "secret123"})
    assert dup.status_code == 409
    assert dup.json()["error"]["code"] == "already_registered"

    # вход по паролю без SMS
    ok = await client.post("/auth/login", json={"phone": phone, "password": "secret123"})
    assert ok.status_code == 200
    assert ok.json()["access_token"]

    # неверный пароль
    bad = await client.post("/auth/login", json={"phone": phone, "password": "wrong"})
    assert bad.status_code == 401
    assert bad.json()["error"]["code"] == "invalid_credentials"


@pytest.mark.asyncio
async def test_reset_password(client) -> None:
    phone = "+79990001103"
    await client.post("/auth/register",
                      json={"phone": phone, "code": await _get_code(client, phone), "password": "oldpass1"})
    # смена пароля по коду
    reset = await client.post("/auth/reset-password",
                              json={"phone": phone, "code": await _get_code(client, phone), "new_password": "newpass2"})
    assert reset.status_code == 200
    # старый пароль больше не работает, новый — да
    assert (await client.post("/auth/login", json={"phone": phone, "password": "oldpass1"})).status_code == 401
    assert (await client.post("/auth/login", json={"phone": phone, "password": "newpass2"})).status_code == 200


@pytest.mark.asyncio
async def test_refresh_rotation(client) -> None:
    phone = "+79990001104"
    reg = (await client.post("/auth/register",
                             json={"phone": phone, "code": await _get_code(client, phone), "password": "secret123"})).json()
    refreshed = await client.post("/auth/refresh", json={"refresh_token": reg["refresh_token"]})
    assert refreshed.status_code == 200
    # старый refresh после ротации отозван
    again = await client.post("/auth/refresh", json={"refresh_token": reg["refresh_token"]})
    assert again.status_code == 401


@pytest.mark.asyncio
async def test_login_bruteforce_throttled(client) -> None:
    from app.api.v1.auth import LOGIN_MAX_FAILS

    phone = "+79990001105"
    await client.post("/auth/register",
                      json={"phone": phone, "code": await _get_code(client, phone), "password": "secret123"})

    # Много неверных паролей подряд — счётчик доходит до лимита, затем 429.
    saw_rate_limited = False
    for _ in range(LOGIN_MAX_FAILS + 2):
        resp = await client.post("/auth/login", json={"phone": phone, "password": "wrong"})
        if resp.status_code == 429:
            saw_rate_limited = True
            assert resp.json()["error"]["code"] == "rate_limited"
            assert resp.headers.get("Retry-After")
            break
        assert resp.status_code == 401
    assert saw_rate_limited, "ожидался 429 после серии неудачных логинов"

    # Сброс счётчика вручную (как при успешном входе) → снова доступен 401, не 429.
    redis = aioredis.from_url(settings.redis_url)
    await redis.delete(f"login_fail:{phone}")
    await redis.aclose()
    ok = await client.post("/auth/login", json={"phone": phone, "password": "secret123"})
    assert ok.status_code == 200


@pytest.mark.asyncio
async def test_unauthorized(client) -> None:
    resp = await client.get("/users/me")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"
