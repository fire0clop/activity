"""Вход через Apple: проверка identity token замокана, тестируем логику эндпоинта."""

import pytest

from app.services import apple_auth


@pytest.fixture
def fake_apple(monkeypatch):
    """Подменяет проверку Apple-токена: identity_token -> (apple_user_id, email)."""
    mapping = {"tok-a": ("apple-aaa", "a@example.com")}

    def fake_verify(token: str):
        if token not in mapping:
            from app.core.exceptions import AppError
            raise AppError("apple_auth_failed", "Не удалось проверить вход через Apple", 401)
        return mapping[token]

    monkeypatch.setattr(apple_auth, "verify_identity_token", fake_verify)
    return mapping


@pytest.mark.asyncio
async def test_apple_creates_then_logs_in(client, fake_apple) -> None:
    # Первый вход — создаётся пользователь, профиль ещё не заполнен.
    first = await client.post("/auth/apple", json={"identity_token": "tok-a", "full_name": "Иван"})
    assert first.status_code == 200
    data = first.json()
    assert data["is_new_user"] is True and data["access_token"]

    me = await client.get("/users/me", headers={"Authorization": f"Bearer {data['access_token']}"})
    body = me.json()
    assert body["name"] == "Иван"          # имя из Apple предзаполнено
    assert body["phone"] is None           # у Apple-пользователя телефона нет
    assert body["profile_completed"] is False

    # Повторный вход тем же Apple ID — это логин, не новый пользователь.
    second = await client.post("/auth/apple", json={"identity_token": "tok-a"})
    assert second.status_code == 200
    assert second.json()["is_new_user"] is False


@pytest.mark.asyncio
async def test_apple_invalid_token_rejected(client, fake_apple) -> None:
    resp = await client.post("/auth/apple", json={"identity_token": "bogus"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "apple_auth_failed"
