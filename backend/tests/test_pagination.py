"""Keyset-пагинация ленты: вставка события между страницами не даёт дублей/пропусков."""

from datetime import UTC, datetime, timedelta

import pytest

NOW = datetime.now(UTC)


def _event_body(title: str, hours: int):
    return {
        "title": title, "category": "walk",
        "starts_at": (NOW + timedelta(hours=hours)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 5, "auto_accept": True,
    }


def _feed(client, headers, **extra):
    params = {"lat": 55.75, "lng": 37.62, "radius_km": 30, "limit": 2, **extra}
    return client.get("/events", headers=headers, params=params)


@pytest.mark.asyncio
async def test_keyset_pagination_stable_under_insert(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    # Три события с возрастающим временем старта (сортировка ленты — по starts_at asc).
    for i in range(3):
        await client.post("/events", headers=org["headers"], json=_event_body(f"E{i}", 24 * (i + 1)))

    page1 = (await _feed(client, guest["headers"])).json()
    assert len(page1["items"]) == 2
    cursor = page1["next_cursor"]
    assert cursor

    # Вставляем событие, которое сортируется РАНЬШЕ курсора (старт через 12ч):
    # при offset-пагинации это сдвинуло бы окно и продублировало элемент.
    await client.post("/events", headers=org["headers"], json=_event_body("Inserted", 12))

    page2 = (await _feed(client, guest["headers"], cursor=cursor)).json()

    ids = [e["id"] for e in page1["items"]] + [e["id"] for e in page2["items"]]
    assert len(ids) == len(set(ids)), "keyset не должен давать дублей при вставке"

    titles = [e["title"] for e in page1["items"] + page2["items"]]
    assert "E2" in titles, "последнее событие не должно пропасть из пагинации"
