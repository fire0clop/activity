"""Холодный старт ленты: если в радиусе пусто — подсказываем ближайший радиус с событиями."""

from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Событие", "category": "walk",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 5, "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_cold_start_suggests_wider_radius(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    # Событие ~100 км севернее Москвы (0.9° широты) — вне 10 и 50 км, но внутри 200 км.
    await client.post("/events", headers=org["headers"],
                      json=_event_body(latitude=56.65, longitude=37.62))

    resp = await client.get("/events", headers=guest["headers"],
                            params={"lat": 55.75, "lng": 37.62, "radius_km": 10})
    data = resp.json()
    assert data["items"] == []
    assert data["suggested_radius_km"] == 200
    assert data["suggested_count"] >= 1


@pytest.mark.asyncio
async def test_no_suggestion_when_events_present(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/events", headers=org["headers"],
                      json=_event_body(latitude=55.76, longitude=37.63))  # рядом

    resp = await client.get("/events", headers=guest["headers"],
                            params={"lat": 55.75, "lng": 37.62, "radius_km": 10})
    data = resp.json()
    assert len(data["items"]) >= 1
    assert data["suggested_radius_km"] is None
    assert data["suggested_count"] is None
