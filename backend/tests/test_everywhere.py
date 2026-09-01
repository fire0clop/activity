"""Лента без привязки к городу.

Ревью App Store велось с устройства в Купертино, а события были в Москве —
лента оказалась пустой, и проверяющий не увидел приложение вовсе. Режим «везде»
показывает всё независимо от того, где человек находится.
"""

from datetime import UTC, datetime, timedelta

import pytest


def _event(**over):
    base = {
        "title": "Теннис", "category": "sport",
        "starts_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
        "latitude": 55.75, "longitude": 37.62, "address": "Корт",
        "min_participants": 2, "max_participants": 4, "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_everywhere_shows_events_from_all_cities(client, user_factory) -> None:
    org = await user_factory("Орг")
    await client.post("/events", headers=org["headers"], json=_event(title="Москва"))
    await client.post("/events", headers=org["headers"],
                      json=_event(title="Купертино", latitude=37.33, longitude=-122.01))
    await client.post("/events", headers=org["headers"],
                      json=_event(title="Владивосток", latitude=43.12, longitude=131.89))

    viewer = await user_factory("Зритель")
    # Без координат — видно всё, где бы человек ни был.
    everywhere = (await client.get("/events", headers=viewer["headers"])).json()
    assert {i["title"] for i in everywhere["items"]} == {"Москва", "Купертино", "Владивосток"}

    # С координатами — только рядом, прежнее поведение не изменилось.
    near = (await client.get("/events", headers=viewer["headers"],
                             params={"lat": 55.75, "lng": 37.62, "radius_km": 25})).json()
    assert [i["title"] for i in near["items"]] == ["Москва"]


@pytest.mark.asyncio
async def test_everywhere_has_no_distance_and_no_radius_hint(client, user_factory) -> None:
    """Расстояние считать не от чего, а подсказка «расширьте радиус» бессмысленна."""
    org = await user_factory("Орг")
    await client.post("/events", headers=org["headers"], json=_event())
    viewer = await user_factory("Зритель")

    resp = (await client.get("/events", headers=viewer["headers"])).json()
    assert resp["items"][0]["distance_km"] is None
    assert resp["suggested_radius_km"] is None


@pytest.mark.asyncio
async def test_everywhere_keeps_filters(client, user_factory) -> None:
    """Отсутствие города не должно отключать остальные фильтры."""
    org = await user_factory("Орг")
    await client.post("/events", headers=org["headers"],
                      json=_event(title="Теннис", category="sport"))
    await client.post("/events", headers=org["headers"],
                      json=_event(title="Настолки", category="boardgames",
                                  latitude=37.33, longitude=-122.01))
    viewer = await user_factory("Зритель")

    only_sport = (await client.get("/events", headers=viewer["headers"],
                                   params={"category": "sport"})).json()
    assert [i["title"] for i in only_sport["items"]] == ["Теннис"]

    found = (await client.get("/events", headers=viewer["headers"],
                              params={"query": "настолк"})).json()
    assert [i["title"] for i in found["items"]] == ["Настолки"]


@pytest.mark.asyncio
async def test_everywhere_hides_blocked_organizers(client, user_factory) -> None:
    """Блокировка сильнее режима «везде»."""
    org = await user_factory("Орг")
    viewer = await user_factory("Зритель")
    await client.post("/events", headers=org["headers"], json=_event(title="Скрыть"))
    await client.post(f"/users/{org['id']}/block", headers=viewer["headers"])

    resp = (await client.get("/events", headers=viewer["headers"])).json()
    assert resp["items"] == []


@pytest.mark.asyncio
async def test_wishes_everywhere(client, user_factory) -> None:
    author = await user_factory("Автор")
    viewer = await user_factory("Зритель")
    for lat, lng, text in ((55.75, 37.62, "Москва"), (37.33, -122.01, "Купертино")):
        await client.post("/requests", headers=author["headers"],
                          json={"category": "tennis", "text": text, "latitude": lat,
                                "longitude": lng, "radius_km": 10, "when_window": "week"})

    resp = (await client.get("/requests", headers=viewer["headers"])).json()
    assert {i["text"] for i in resp["items"]} == {"Москва", "Купертино"}
