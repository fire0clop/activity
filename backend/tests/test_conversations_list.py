"""Блок 5: список бесед строится батч-запросами (без N+1). Проверяем корректность
last_message / unread_count / members_count после рефакторинга."""

from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Кино", "description": "идём в кино", "category": "culture",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "ends_at": (datetime.now(UTC) + timedelta(days=1, hours=2)).isoformat(),
        "latitude": 55.75, "longitude": 37.62, "address": "Кинотеатр",
        "min_participants": 2, "max_participants": 4, "price": 0,
        "price_split": "free", "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_conversation_list_last_message_and_unread(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    ev = await client.post("/events", headers=org["headers"], json=_event_body())
    event_id = ev.json()["id"]
    # Автоприём гостя создаёт беседу события и системные сообщения (join + раскрытие времени).
    await client.post(f"/events/{event_id}/join", headers=guest["headers"])

    resp = await client.get("/conversations", headers=org["headers"])
    assert resp.status_code == 200
    items = resp.json()["items"]
    conv = next(c for c in items if c["event_id"] == event_id)

    # Беседа события: организатор + гость.
    assert conv["members_count"] == 2
    # Есть последнее сообщение (системное раскрытие времени) и оно непрочитано организатором.
    assert conv["last_message"] is not None
    assert conv["last_message"]["text"]
    assert conv["unread_count"] >= 1
