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


async def _register(client, phone: str, password: str = "secret123"):
    """Двухшаговая регистрация: подтверждаем код → тикет, затем тикет + пароль → аккаунт."""
    code = await _get_code(client, phone)
    vt = (await client.post("/auth/verify-code", json={"phone": phone, "code": code})).json()
    return await client.post(
        "/auth/register", json={"verification_token": vt["verification_token"], "password": password})


@pytest.mark.asyncio
async def test_request_code_cooldown(client) -> None:
    phone = "+79990001100"
    r1 = await client.post("/auth/request-code", json={"phone": phone})
    assert r1.status_code == 200
    r2 = await client.post("/auth/request-code", json={"phone": phone})
    assert r2.status_code == 429
    assert r2.json()["error"]["code"] == "rate_limited"


@pytest.mark.asyncio
async def test_verify_code_bad_and_expired(client) -> None:
    phone = "+79990001101"
    await client.post("/auth/request-code", json={"phone": phone})
    bad = await client.post("/auth/verify-code", json={"phone": phone, "code": "000000"})
    assert bad.status_code == 400
    assert bad.json()["error"]["code"] == "invalid_code"

    no_code = await client.post("/auth/verify-code", json={"phone": "+79990009999", "code": "123456"})
    assert no_code.status_code == 410
    assert no_code.json()["error"]["code"] == "code_expired"


@pytest.mark.asyncio
async def test_register_then_login_with_password(client) -> None:
    phone = "+79990001102"
    reg = await _register(client, phone)
    assert reg.status_code == 200
    assert reg.json()["is_new_user"] is True

    # повторная регистрация того же номера — нельзя
    dup = await _register(client, phone)
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
    await _register(client, phone, "oldpass1")
    # смена пароля: подтверждаем номер → тикет → новый пароль
    code = await _get_code(client, phone)
    vt = (await client.post("/auth/verify-code", json={"phone": phone, "code": code})).json()["verification_token"]
    reset = await client.post("/auth/reset-password",
                              json={"verification_token": vt, "new_password": "newpass2"})
    assert reset.status_code == 200
    # старый пароль больше не работает, новый — да
    assert (await client.post("/auth/login", json={"phone": phone, "password": "oldpass1"})).status_code == 401
    assert (await client.post("/auth/login", json={"phone": phone, "password": "newpass2"})).status_code == 200


@pytest.mark.asyncio
async def test_refresh_rotation(client) -> None:
    phone = "+79990001104"
    reg = (await _register(client, phone)).json()
    refreshed = await client.post("/auth/refresh", json={"refresh_token": reg["refresh_token"]})
    assert refreshed.status_code == 200
    # старый refresh после ротации отозван
    again = await client.post("/auth/refresh", json={"refresh_token": reg["refresh_token"]})
    assert again.status_code == 401


@pytest.mark.asyncio
async def test_login_bruteforce_throttled(client) -> None:
    from app.api.v1.auth import LOGIN_MAX_FAILS

    phone = "+79990001105"
    await _register(client, phone)

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
