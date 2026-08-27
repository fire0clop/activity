"""Блок 4: «Мои события» (включая завершённые) и учёт посещений по факту завершения."""

from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Теннис", "description": "играем", "category": "sport",
        "starts_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
        "ends_at": (datetime.now(UTC) + timedelta(days=2, hours=1)).isoformat(),
        "latitude": 55.75, "longitude": 37.62, "address": "Корт",
        "min_participants": 2, "max_participants": 4, "price": 0,
        "price_split": "free", "auto_accept": True,
    }
    base.update(over)
    return base


async def _attended(client, headers) -> int:
    me = await client.get("/users/me", headers=headers)
    return me.json()["events_attended"]


@pytest.mark.asyncio
async def test_my_events_includes_organized_and_finished(client, user_factory) -> None:
    org = await user_factory("Орг")
    ev = await client.post("/events", headers=org["headers"], json=_event_body())
    event_id = ev.json()["id"]

    mine = await client.get("/events/mine", headers=org["headers"])
    assert mine.status_code == 200
    assert any(it["id"] == event_id for it in mine.json()["items"])

    # Завершаем — событие пропадает из общей ленты, но остаётся в «Моих событиях».
    await client.post(f"/events/{event_id}/finish", headers=org["headers"])
    feed = await client.get("/events", headers=org["headers"],
                            params={"lat": 55.75, "lng": 37.62, "radius_km": 50})
    assert all(it["id"] != event_id for it in feed.json()["items"])
    mine2 = await client.get("/events/mine", headers=org["headers"])
    assert any(it["id"] == event_id for it in mine2.json()["items"])


@pytest.mark.asyncio
async def test_my_events_includes_participated(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    ev = await client.post("/events", headers=org["headers"], json=_event_body())
    event_id = ev.json()["id"]
    await client.post(f"/events/{event_id}/join", headers=guest["headers"])

    mine = await client.get("/events/mine", headers=guest["headers"])
    assert any(it["id"] == event_id for it in mine.json()["items"])


@pytest.mark.asyncio
async def test_attendance_counted_on_finish_not_on_accept(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    ev = await client.post("/events", headers=org["headers"], json=_event_body())
    event_id = ev.json()["id"]

    await client.post(f"/events/{event_id}/join", headers=guest["headers"])
    # Принят, но событие не завершено → посещение ещё не засчитано.
    assert await _attended(client, guest["headers"]) == 0

    await client.post(f"/events/{event_id}/finish", headers=org["headers"])
    assert await _attended(client, guest["headers"]) == 1

    # Повторный finish не должен задваивать посещение.
    await client.post(f"/events/{event_id}/finish", headers=org["headers"])
    assert await _attended(client, guest["headers"]) == 1


@pytest.mark.asyncio
async def test_deleted_event_leaves_my_events(client, user_factory) -> None:
    """Удалил своё событие — его больше нет в списке.

    Удаление у нас мягкое (status=cancelled), и раньше событие продолжало висеть
    в «Моих событиях». Со стороны это выглядело так, будто кнопка не работает.
    """
    org = await user_factory("Орг")
    event_id = (await client.post("/events", headers=org["headers"],
                                  json=_event_body())).json()["id"]
    assert (await client.get("/events/mine", headers=org["headers"])).json()["items"]

    assert (await client.delete(f"/events/{event_id}",
                                headers=org["headers"])).status_code == 204
    assert (await client.get("/events/mine", headers=org["headers"])).json()["items"] == []


@pytest.mark.asyncio
async def test_participant_still_sees_cancelled_event(client, user_factory) -> None:
    """А вот участнику отмену показываем: ему важно знать, что встречи не будет."""
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    event_id = (await client.post("/events", headers=org["headers"],
                                  json=_event_body())).json()["id"]
    await client.post(f"/events/{event_id}/join", headers=guest["headers"])
    await client.delete(f"/events/{event_id}", headers=org["headers"])

    items = (await client.get("/events/mine", headers=guest["headers"])).json()["items"]
    assert [i["status"] for i in items] == ["cancelled"]
