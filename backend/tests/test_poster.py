"""Афиша и категории.

Афиша — не пользовательский контент: заводит её оператор, а люди только смотрят и
собирают под неё компанию. Это и проверяем.
"""

from datetime import UTC, datetime, timedelta

import pytest

from app.core.config import settings


def _poster(**over):
    base = {
        "title": "Концерт в Главclub",
        "category": "concert",
        "starts_at": (datetime.now(UTC) + timedelta(days=3)).isoformat(),
        "venue": "Главclub Green Concert",
        "address": "Орджоникидзе, 11",
        "latitude": 55.71,
        "longitude": 37.61,
        "price_from": 2500,
        "source_url": "https://example.org/tickets/1",
        "source_name": "Организатор",
    }
    base.update(over)
    return base


@pytest.fixture
def admin_headers(monkeypatch):
    monkeypatch.setattr(settings, "admin_api_key", "test-admin-key")
    return {"X-Admin-Key": "test-admin-key"}


@pytest.mark.asyncio
async def test_poster_is_operator_only(client, user_factory, admin_headers) -> None:
    user = await user_factory("Обычный")
    denied = await client.post("/poster", headers=user["headers"], json=_poster())
    assert denied.status_code == 403

    created = await client.post("/poster", headers=admin_headers, json=_poster())
    assert created.status_code == 201
    assert created.json()["gatherings_count"] == 0


@pytest.mark.asyncio
async def test_poster_visible_nearby_and_sorted_by_date(client, user_factory, admin_headers) -> None:
    viewer = await user_factory("Зритель")
    later = (datetime.now(UTC) + timedelta(days=9)).isoformat()
    sooner = (datetime.now(UTC) + timedelta(days=2)).isoformat()
    await client.post("/poster", headers=admin_headers,
                      json=_poster(title="Поздний", starts_at=later))
    await client.post("/poster", headers=admin_headers,
                      json=_poster(title="Скорый", starts_at=sooner))

    feed = (await client.get("/poster", headers=viewer["headers"],
                             params={"lat": 55.71, "lng": 37.61, "radius_km": 50})).json()
    assert [i["title"] for i in feed["items"]] == ["Скорый", "Поздний"]


@pytest.mark.asyncio
async def test_past_and_hidden_are_not_shown(client, user_factory, admin_headers) -> None:
    viewer = await user_factory("Зритель")
    gone = (await client.post("/poster", headers=admin_headers,
                              json=_poster(title="Снимут"))).json()["id"]
    await client.delete(f"/poster/{gone}", headers=admin_headers)

    feed = (await client.get("/poster", headers=viewer["headers"],
                             params={"lat": 55.71, "lng": 37.61})).json()
    assert feed["items"] == []


@pytest.mark.asyncio
async def test_gathering_from_poster_counts(client, user_factory, admin_headers) -> None:
    """Ради этой связи афиша и заведена: чужой концерт становится поводом собраться."""
    organizer = await user_factory("Организатор")
    poster_id = (await client.post("/poster", headers=admin_headers,
                                   json=_poster())).json()["id"]

    event = await client.post("/events", headers=organizer["headers"], json={
        "title": "Идём на концерт вместе",
        "starts_at": (datetime.now(UTC) + timedelta(days=3)).isoformat(),
        "latitude": 55.71, "longitude": 37.61,
        "min_participants": 2, "max_participants": 4,
        "price_split": "free", "auto_accept": True,
        "poster_id": poster_id,
    })
    assert event.status_code == 201
    assert event.json()["poster_id"] == poster_id

    card = (await client.get(f"/poster/{poster_id}", headers=organizer["headers"])).json()
    assert card["gatherings_count"] == 1


@pytest.mark.asyncio
async def test_custom_category_is_normalized(client, user_factory) -> None:
    """«Йога», «йога» и «ЙОГА» обязаны быть одной категорией, иначе фильтр бесполезен."""
    org = await user_factory("Орг")
    body = {
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 4,
        "price_split": "free", "auto_accept": True,
    }
    a = (await client.post("/events", headers=org["headers"],
                           json={**body, "title": "Раз", "category": "  Йога "})).json()
    b = (await client.post("/events", headers=org["headers"],
                           json={**body, "title": "Два", "category": "ЙОГА"})).json()
    assert a["category"] == b["category"] == "yoga"

    c = (await client.post("/events", headers=org["headers"],
                           json={**body, "title": "Три",
                                 "category": "  Настольный   ТЕННИС "})).json()
    assert c["category"] == "настольный теннис"


@pytest.mark.asyncio
async def test_categories_list_includes_custom(client, user_factory) -> None:
    org = await user_factory("Орг")
    await client.post("/events", headers=org["headers"], json={
        "title": "Пинг-понг", "category": "настольный теннис",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 4,
        "price_split": "free", "auto_accept": True,
    })

    items = (await client.get("/categories", headers=org["headers"])).json()["items"]
    by_key = {i["key"]: i for i in items}
    assert by_key["walk"]["is_canonical"] is True
    assert by_key["настольный теннис"]["is_canonical"] is False
    assert by_key["настольный теннис"]["usage"] == 1
    assert by_key["настольный теннис"]["title"] == "Настольный теннис"
