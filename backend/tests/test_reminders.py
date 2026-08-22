"""Напоминания о событии: свипер шлёт пуш accepted-участникам один раз в окно."""

from datetime import UTC, datetime, timedelta

import pytest

from app.services import lifecycle, push_service


@pytest.fixture
def apns_recorder(monkeypatch):
    sent: list[dict] = []

    async def fake_send(token, title, body, data):
        sent.append({"token": token, "title": title, "body": body, "data": data})
        return True, False

    monkeypatch.setattr(push_service, "apns_enabled", lambda: True)
    monkeypatch.setattr(push_service, "_send_apns", fake_send)
    return sent


def _event_body(**over):
    base = {
        "title": "Встреча", "category": "walk",
        # старт через 90 минут — попадает в 2-часовое окно напоминаний
        "starts_at": (datetime.now(UTC) + timedelta(minutes=90)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 5, "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_reminder_sent_once_within_window(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/devices", headers=guest["headers"],
                      json={"token": "tok-guest", "platform": "ios"})
    eid = (await client.post("/events", headers=org["headers"], json=_event_body())).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])

    # Первый проход свипера — гость получает напоминание.
    await lifecycle._send_reminders_once()
    reminders = [p for p in apns_recorder
                 if p["token"] == "tok-guest" and p["title"] == "Напоминание о событии"]
    assert reminders and reminders[-1]["data"]["event_id"] == eid

    # Повторный проход — дубля нет (флаг окна уже выставлен).
    await lifecycle._send_reminders_once()
    again = [p for p in apns_recorder
             if p["token"] == "tok-guest" and p["title"] == "Напоминание о событии"]
    assert len(again) == len(reminders)


@pytest.mark.asyncio
async def test_no_reminder_for_distant_event(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/devices", headers=guest["headers"],
                      json={"token": "tok-guest", "platform": "ios"})
    # старт через 3 дня — вне обоих окон
    eid = (await client.post("/events", headers=org["headers"],
                             json=_event_body(starts_at=(datetime.now(UTC) + timedelta(days=3)).isoformat()))).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])

    await lifecycle._send_reminders_once()
    assert not [p for p in apns_recorder if p["title"] == "Напоминание о событии"]


@pytest.mark.asyncio
async def test_only_one_worker_runs_the_cycle(client) -> None:
    """Фоновый обход выполняет ровно один процесс.

    Gunicorn поднимает несколько воркеров, и каждый запускает свои фоновые задачи.
    Без замка напоминания уходили бы по числу воркеров, а повторяющееся событие
    клонировалось бы в стольких же экземплярах.
    """
    import redis.asyncio as aioredis

    from app.core.config import settings
    from app.services.lifecycle import _claim

    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    key = "test:lifecycle:claim"
    await redis.delete(key)
    try:
        # Четыре воркера одновременно пытаются взять цикл — проходит один.
        results = [await _claim(redis, key, 60) for _ in range(4)]
        assert results.count(True) == 1
        assert results.count(False) == 3
    finally:
        await redis.delete(key)
        await redis.aclose()


@pytest.mark.asyncio
async def test_claim_survives_dead_redis(client, monkeypatch) -> None:
    """Недоступный Redis не должен ронять приложение — цикл просто пропускается."""
    from app.services.lifecycle import _claim

    class DeadRedis:
        async def set(self, *a, **kw):
            raise ConnectionError("redis is down")

    assert await _claim(DeadRedis(), "test:dead", 60) is False
