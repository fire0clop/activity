"""Подписки на категорию/район: CRUD и пуш при создании подходящего события."""

from datetime import UTC, datetime, timedelta

import pytest

from app.services import push_service


def _event_body(**over):
    base = {
        "title": "Каток",
        "category": "sport",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "min_participants": 2,
        "max_participants": 5,
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
async def test_subscription_crud_and_validation(client, user_factory) -> None:
    u = await user_factory("Подписчик")
    # без критериев — 422
    bad = await client.post("/subscriptions", headers=u["headers"], json={})
    assert bad.status_code == 422

    created = await client.post(
        "/subscriptions", headers=u["headers"], json={"category": "sport"})
    assert created.status_code == 201
    sid = created.json()["id"]

    items = (await client.get("/subscriptions", headers=u["headers"])).json()["items"]
    assert len(items) == 1 and items[0]["category"] == "sport"

    assert (await client.delete(f"/subscriptions/{sid}", headers=u["headers"])).status_code == 204
    assert (await client.get("/subscriptions", headers=u["headers"])).json()["items"] == []


@pytest.mark.asyncio
async def test_matching_event_triggers_push(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    fan = await user_factory("Фанат")
    await client.post("/devices", headers=fan["headers"],
                      json={"token": "tok-fan", "platform": "ios"})
    # подписка: категория sport в радиусе 10 км от центра Москвы
    await client.post("/subscriptions", headers=fan["headers"],
                      json={"category": "sport", "latitude": 55.75, "longitude": 37.62,
                            "radius_km": 10})

    eid = (await client.post("/events", headers=org["headers"],
                             json=_event_body())).json()["id"]

    got = [p for p in apns_recorder if p["token"] == "tok-fan"]
    assert got and got[-1]["title"] == "Новое событие по подписке"
    assert got[-1]["data"]["event_id"] == eid


@pytest.mark.asyncio
async def test_non_matching_event_no_push(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    fan = await user_factory("Фанат")
    await client.post("/devices", headers=fan["headers"],
                      json={"token": "tok-fan", "platform": "ios"})

    # другая категория
    await client.post("/subscriptions", headers=fan["headers"], json={"category": "music"})
    await client.post("/events", headers=org["headers"], json=_event_body(category="sport"))
    assert not [p for p in apns_recorder if p["token"] == "tok-fan"]

    # своя категория, но далеко (Сочи ~1360 км)
    await client.post("/subscriptions", headers=fan["headers"],
                      json={"category": "sport", "latitude": 43.60, "longitude": 39.73,
                            "radius_km": 10})
    await client.post("/events", headers=org["headers"], json=_event_body(title="Каток-2"))
    assert not [p for p in apns_recorder if p["token"] == "tok-fan"]


@pytest.mark.asyncio
async def test_organizer_not_notified_about_own_event(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    await client.post("/devices", headers=org["headers"],
                      json={"token": "tok-org", "platform": "ios"})
    await client.post("/subscriptions", headers=org["headers"], json={"category": "sport"})
    await client.post("/events", headers=org["headers"], json=_event_body())
    assert not [p for p in apns_recorder if p["title"] == "Новое событие по подписке"]
