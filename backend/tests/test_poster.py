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


# --- Импорт из внешнего источника -----------------------------------------

_RAW_OK = {
    "id": 172178,
    "short_title": "концерт в главclub",
    "title": "Полное название",
    "description": "Описание",
    "categories": ["concert"],
    "dates": [{"start": 4102444800, "end": 4102448400}],   # заведомо в будущем
    "place": {"title": "Главclub", "address": "Орджоникидзе, 11",
              "coords": {"lat": 55.71, "lon": 37.61}},
    "price": "от 2500 рублей",
    "is_free": False,
    "images": [{"image": "https://example.org/a.jpg"}],
    "site_url": "https://example.org/e/1",
}
_RAW_PAST = {**_RAW_OK, "id": 3, "dates": [{"start": 1, "end": 2}]}
_RAW_NO_PLACE = {**_RAW_OK, "id": 4, "place": None}


@pytest.mark.asyncio
async def test_import_creates_updates_and_skips(client, user_factory, monkeypatch) -> None:
    """Импорт идемпотентен и отбрасывает то, что нельзя показать в гео-афише."""
    from app.db.session import SessionLocal
    from app.services import poster_import

    monkeypatch.setattr(poster_import, "fetch_city",
                        lambda city, *, limit: [_RAW_OK, _RAW_PAST, _RAW_NO_PLACE])

    async with SessionLocal() as db:
        first = await poster_import.import_city(db, "msk")
        assert (first["created"], first["skipped"]) == (1, 2)

        # повторный прогон обновляет ту же карточку, а не плодит дубликаты
        second = await poster_import.import_city(db, "msk")
        assert (second["created"], second["updated"]) == (0, 1)

    viewer = await user_factory("Зритель")
    feed = (await client.get("/poster", headers=viewer["headers"],
                             params={"lat": 55.71, "lng": 37.61})).json()
    assert len(feed["items"]) == 1
    item = feed["items"][0]
    assert item["title"] == "Концерт в главclub"     # источник даёт нижний регистр
    assert item["price_from"] == 2500                # цена вытащена из фразы
    assert item["category"] == "concert"
    assert item["source_name"] == "KudaGo"


@pytest.mark.asyncio
async def test_import_endpoint_requires_admin(client, user_factory, admin_headers,
                                              monkeypatch) -> None:
    from app.services import poster_import

    monkeypatch.setattr(poster_import, "fetch_city", lambda city, *, limit: [_RAW_OK])
    user = await user_factory("Обычный")

    assert (await client.post("/poster/import", headers=user["headers"])).status_code == 403
    ok = await client.post("/poster/import", headers=admin_headers, params={"city": "msk"})
    assert ok.status_code == 200
    assert ok.json()[0]["created"] == 1

    bad_city = await client.post("/poster/import", headers=admin_headers,
                                 params={"city": "paris"})
    assert bad_city.status_code == 404


def test_price_is_parsed_from_free_text() -> None:
    from app.services.poster_import import _parse_price

    assert _parse_price("от 2 500 рублей", False) == 2500
    assert _parse_price("вход свободный", True) is None
    assert _parse_price("", False) is None
    assert _parse_price("билеты уточняйте", False) is None
