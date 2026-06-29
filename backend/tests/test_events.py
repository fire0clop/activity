from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Гидроциклы",
        "description": "делим прокат",
        "category": "watersport",
        "starts_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
        "ends_at": (datetime.now(UTC) + timedelta(days=2, hours=3)).isoformat(),
        "latitude": 55.91,
        "longitude": 37.81,
        "address": "Пирс 3",
        "min_participants": 2,
        "max_participants": 4,
        "price": 4000,
        "price_split": "shared",
        "auto_accept": False,
    }
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_profile_gating(client, user_factory) -> None:
    u = await user_factory("Аноним", complete=False)
    resp = await client.post("/events", headers=u["headers"], json=_event_body())
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "profile_incomplete"


@pytest.mark.asyncio
async def test_create_validation(client, user_factory) -> None:
    u = await user_factory("Орг")
    # время в прошлом
    past = await client.post("/events", headers=u["headers"],
                             json=_event_body(starts_at=(datetime.now(UTC) - timedelta(days=1)).isoformat()))
    assert past.status_code == 422
    # max < min
    bad = await client.post("/events", headers=u["headers"],
                            json=_event_body(min_participants=5, max_participants=3))
    assert bad.status_code == 422


@pytest.mark.asyncio
async def test_create_with_yandex_link(client, user_factory) -> None:
    org = await user_factory("Орг")
    body = _event_body()
    body.pop("latitude")
    body.pop("longitude")
    body["map_url"] = "https://yandex.ru/maps/?ll=37.62,55.75&pt=37.617635,55.755814"
    resp = await client.post("/events", headers=org["headers"], json=body)
    assert resp.status_code == 201
    d = resp.json()
    assert abs(d["latitude"] - 55.755814) < 0.001     # точка из pt, не центр ll
    assert abs(d["longitude"] - 37.617635) < 0.001
    assert d["map_url"] is not None


@pytest.mark.asyncio
async def test_geo_feed_and_time_hiding(client, user_factory) -> None:
    org = await user_factory("Орг")
    created = await client.post("/events", headers=org["headers"], json=_event_body())
    assert created.status_code == 201
    ev = created.json()
    assert ev["time_disclosed"] is True  # организатор видит время
    assert ev["starts_at"] is not None

    viewer = await user_factory("Зритель")
    feed = await client.get("/events", headers=viewer["headers"],
                            params={"lat": 55.90, "lng": 37.80, "radius_km": 20})
    assert feed.status_code == 200
    items = feed.json()["items"]
    assert len(items) == 1
    it = items[0]
    assert it["time_disclosed"] is False        # время скрыто
    assert it["starts_at"] is None
    assert it["day"] is not None
    assert it["distance_km"] is not None
    assert it["participants_current"] == 1

    # далеко → не в ленте
    far = await client.get("/events", headers=viewer["headers"],
                           params={"lat": 40.0, "lng": -70.0, "radius_km": 5})
    assert far.json()["items"] == []


@pytest.mark.asyncio
async def test_finish_enables_reviews(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    ev = (await client.post("/events", headers=org["headers"],
                            json=_event_body(auto_accept=True))).json()
    eid = ev["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])

    # до finish отзыв нельзя
    early = await client.post(f"/events/{eid}/reviews", headers=org["headers"],
                              json={"target_id": guest["id"], "rating": 5})
    assert early.status_code == 422

    fin = await client.post(f"/events/{eid}/finish", headers=org["headers"])
    assert fin.status_code == 200
    assert fin.json()["status"] == "finished"

    ok = await client.post(f"/events/{eid}/reviews", headers=org["headers"],
                           json={"target_id": guest["id"], "rating": 5, "comment": "класс"})
    assert ok.status_code == 201

    # рейтинг пересчитался
    pub = (await client.get(f"/users/{guest['id']}", headers=org["headers"])).json()
    assert pub["rating_avg"] == 5.0
    assert pub["rating_count"] == 1
