"""«Ищу компанию»: намерение без обязательств.

Проверяем то, ради чего это заведено: заявить желание дёшево, спрос виден организатору,
а превращение запроса в событие доходит до всех, кто его ждал.
"""

from datetime import UTC, datetime, timedelta

import pytest

from app.services import push_service


def _req(**over):
    base = {
        "category": "tennis",
        "text": "хочу на теннис вечером, ракетка есть",
        "latitude": 55.75,
        "longitude": 37.62,
        "area": "Приморский район",
        "radius_km": 10,
        "when_window": "week",
    }
    base.update(over)
    return base


def _event(**over):
    base = {
        "title": "Теннис в парке",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "min_participants": 2,
        "max_participants": 4,
        "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.fixture
def apns_recorder(monkeypatch):
    sent: list[dict] = []

    async def fake_send(token, title, body, data):
        sent.append({"token": token, "title": title, "body": body, "data": data})
        return True, False

    monkeypatch.setattr(push_service, "apns_enabled", lambda: True)
    monkeypatch.setattr(push_service, "_send_apns", fake_send)
    return sent


@pytest.mark.asyncio
async def test_create_and_see_nearby(client, user_factory) -> None:
    author = await user_factory("Автор")
    viewer = await user_factory("Зритель")

    created = await client.post("/requests", headers=author["headers"], json=_req())
    assert created.status_code == 201
    assert created.json()["supports_count"] == 0
    assert created.json()["is_mine"] is True

    feed = (await client.get("/requests", headers=viewer["headers"],
                             params={"lat": 55.75, "lng": 37.62, "radius_km": 10})).json()
    assert len(feed["items"]) == 1
    item = feed["items"][0]
    assert item["category"] == "tennis"
    assert item["area"] == "Приморский район"
    assert item["is_mine"] is False
    assert item["distance_km"] == 0.0


@pytest.mark.asyncio
async def test_far_request_not_shown(client, user_factory) -> None:
    author = await user_factory("Автор")
    viewer = await user_factory("Зритель")
    await client.post("/requests", headers=author["headers"],
                      json=_req(latitude=59.93, longitude=30.33))   # другой город

    feed = (await client.get("/requests", headers=viewer["headers"],
                             params={"lat": 55.75, "lng": 37.62, "radius_km": 25})).json()
    assert feed["items"] == []


@pytest.mark.asyncio
async def test_support_signals_demand(client, user_factory) -> None:
    author = await user_factory("Автор")
    a = await user_factory("Плюсующий1")
    b = await user_factory("Плюсующий2")
    rid = (await client.post("/requests", headers=author["headers"],
                             json=_req())).json()["id"]

    assert (await client.post(f"/requests/{rid}/support",
                              headers=a["headers"])).json()["supports_count"] == 1
    # идемпотентно: повторный «+1» не удваивает счётчик
    assert (await client.post(f"/requests/{rid}/support",
                              headers=a["headers"])).json()["supports_count"] == 1
    assert (await client.post(f"/requests/{rid}/support",
                              headers=b["headers"])).json()["supports_count"] == 2

    feed = (await client.get("/requests", headers=a["headers"],
                             params={"lat": 55.75, "lng": 37.62})).json()
    assert feed["items"][0]["i_support"] is True

    off = await client.delete(f"/requests/{rid}/support", headers=a["headers"])
    assert off.json() == {"supports_count": 1, "i_support": False}


@pytest.mark.asyncio
async def test_cannot_support_own_request(client, user_factory) -> None:
    author = await user_factory("Автор")
    rid = (await client.post("/requests", headers=author["headers"],
                             json=_req())).json()["id"]
    resp = await client.post(f"/requests/{rid}/support", headers=author["headers"])
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_demand_sorted_first(client, user_factory) -> None:
    """Наверху то, чего хотят многие: спрос важнее свежести."""
    a1 = await user_factory("Автор1")
    a2 = await user_factory("Автор2")
    fan = await user_factory("Поддержал")
    quiet = (await client.post("/requests", headers=a1["headers"],
                               json=_req(category="walk"))).json()["id"]
    popular = (await client.post("/requests", headers=a2["headers"],
                                 json=_req(category="sport"))).json()["id"]
    await client.post(f"/requests/{popular}/support", headers=fan["headers"])

    feed = (await client.get("/requests", headers=fan["headers"],
                             params={"lat": 55.75, "lng": 37.62})).json()
    assert [i["id"] for i in feed["items"]] == [popular, quiet]


@pytest.mark.asyncio
async def test_fulfilling_request_notifies_author_and_supporters(
    client, user_factory, apns_recorder
) -> None:
    author = await user_factory("Автор")
    fan = await user_factory("Поддержал")
    organizer = await user_factory("Организатор")
    for u, tok in ((author, "tok-author"), (fan, "tok-fan")):
        await client.post("/devices", headers=u["headers"],
                          json={"token": tok, "platform": "ios"})

    rid = (await client.post("/requests", headers=author["headers"],
                             json=_req())).json()["id"]
    await client.post(f"/requests/{rid}/support", headers=fan["headers"])

    created = await client.post("/events", headers=organizer["headers"],
                                json=_event(from_request_id=rid))
    assert created.status_code == 201

    tokens = {p["token"] for p in apns_recorder}
    assert {"tok-author", "tok-fan"} <= tokens
    assert any(p["title"] == "Ваше «хочу» сбылось" and p["token"] == "tok-author"
               for p in apns_recorder)

    # запрос закрыт и пропал из ленты
    feed = (await client.get("/requests", headers=fan["headers"],
                             params={"lat": 55.75, "lng": 37.62})).json()
    assert feed["items"] == []


@pytest.mark.asyncio
async def test_author_can_cancel(client, user_factory) -> None:
    author = await user_factory("Автор")
    other = await user_factory("Чужой")
    rid = (await client.post("/requests", headers=author["headers"],
                             json=_req())).json()["id"]

    assert (await client.delete(f"/requests/{rid}", headers=other["headers"])).status_code == 403
    assert (await client.delete(f"/requests/{rid}", headers=author["headers"])).status_code == 204

    feed = (await client.get("/requests", headers=other["headers"],
                             params={"lat": 55.75, "lng": 37.62})).json()
    assert feed["items"] == []


@pytest.mark.asyncio
async def test_blocked_author_hidden(client, user_factory) -> None:
    author = await user_factory("Автор")
    viewer = await user_factory("Зритель")
    await client.post("/requests", headers=author["headers"], json=_req())
    await client.post(f"/users/{author['id']}/block", headers=viewer["headers"])

    feed = (await client.get("/requests", headers=viewer["headers"],
                             params={"lat": 55.75, "lng": 37.62})).json()
    assert feed["items"] == []


@pytest.mark.asyncio
async def test_expired_request_leaves_feed(client, user_factory) -> None:
    """Протухшие желания не должны копиться в ленте."""
    import uuid as _uuid

    from sqlalchemy import select

    from app.db.session import SessionLocal
    from app.models.request import CompanyRequest
    from app.services import request_service

    author = await user_factory("Автор")
    viewer = await user_factory("Зритель")
    rid = (await client.post("/requests", headers=author["headers"],
                             json=_req(when_window="today"))).json()["id"]

    async with SessionLocal() as db:
        req = (await db.execute(
            select(CompanyRequest).where(CompanyRequest.id == _uuid.UUID(rid))
        )).scalar_one()
        req.expires_at = datetime.now(UTC) - timedelta(hours=1)
        await db.commit()
        assert await request_service.expire_stale(db) == 1
        await db.commit()

    feed = (await client.get("/requests", headers=viewer["headers"],
                             params={"lat": 55.75, "lng": 37.62})).json()
    assert feed["items"] == []


@pytest.mark.asyncio
async def test_incomplete_profile_cannot_post(client, user_factory) -> None:
    """Заявить желание — тоже действие в общей ленте: профиль должен быть заполнен."""
    from app.db.session import SessionLocal
    from app.models.user import User

    author = await user_factory("Автор")
    async with SessionLocal() as db:
        import uuid as _uuid
        u = await db.get(User, _uuid.UUID(author["id"]))
        u.bio = None
        await db.commit()

    resp = await client.post("/requests", headers=author["headers"], json=_req())
    assert resp.status_code == 403
