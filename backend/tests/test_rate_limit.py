"""Per-user rate-limit: авторизованный пользователь не может спамить действиями."""

from datetime import UTC, datetime, timedelta

import pytest

from app.core.config import settings


def _event_body(**over):
    base = {
        "title": "Событие",
        "description": "тест",
        "category": "walk",
        "starts_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "address": "Парк",
        "min_participants": 2,
        "max_participants": 4,
        "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.fixture
def _tight_limits():
    """Временно ужимает лимиты, чтобы упереться в них парой запросов."""
    saved = (settings.user_rl_events_per_hour, settings.user_rl_reports_per_hour)
    settings.user_rl_events_per_hour = 2
    settings.user_rl_reports_per_hour = 2
    yield
    settings.user_rl_events_per_hour, settings.user_rl_reports_per_hour = saved


@pytest.mark.asyncio
async def test_event_creation_rate_limited(client, user_factory, _tight_limits) -> None:
    u = await user_factory("Спамер")
    for i in range(2):
        resp = await client.post("/events", headers=u["headers"], json=_event_body(title=f"e{i}"))
        assert resp.status_code == 201
    third = await client.post("/events", headers=u["headers"], json=_event_body(title="e3"))
    assert third.status_code == 429
    assert third.json()["error"]["code"] == "rate_limited"
    assert third.headers.get("Retry-After") is not None


@pytest.mark.asyncio
async def test_reports_rate_limited(client, user_factory, _tight_limits) -> None:
    reporter = await user_factory("Жалобщик")
    target = await user_factory("Цель")
    for _ in range(2):
        resp = await client.post(
            "/reports", headers=reporter["headers"],
            json={"target_user_id": target["id"], "reason": "spam"},
        )
        assert resp.status_code == 201
    third = await client.post(
        "/reports", headers=reporter["headers"],
        json={"target_user_id": target["id"], "reason": "spam"},
    )
    assert third.status_code == 429
    assert third.json()["error"]["code"] == "rate_limited"


@pytest.mark.asyncio
async def test_limit_is_per_user_not_global(client, user_factory, _tight_limits) -> None:
    u1 = await user_factory("Первый")
    u2 = await user_factory("Второй")
    for i in range(2):
        assert (
            await client.post("/events", headers=u1["headers"], json=_event_body(title=f"a{i}"))
        ).status_code == 201
    # у другого пользователя свой счётчик
    assert (
        await client.post("/events", headers=u2["headers"], json=_event_body(title="b0"))
    ).status_code == 201
