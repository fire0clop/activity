from datetime import UTC, datetime, timedelta

import pytest


def _body(**over):
    base = {
        "title": "Теннис",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "min_participants": 2,
        "max_participants": 2,  # организатор + 1 место
        "auto_accept": False,
    }
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_join_accept_creates_chat_and_discloses_time(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    ev = (await client.post("/events", headers=org["headers"], json=_body())).json()
    eid = ev["id"]

    j = await client.post(f"/events/{eid}/join", headers=guest["headers"])
    assert j.json()["status"] == "pending"

    # организатор видит pending
    parts = (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                              params={"status": "pending"})).json()["items"]
    assert len(parts) == 1
    pid = parts[0]["participation_id"]

    acc = await client.post(f"/participations/{pid}/accept", headers=org["headers"])
    assert acc.json()["status"] == "accepted"

    # гостю время раскрыто + есть чат
    detail = (await client.get(f"/events/{eid}", headers=guest["headers"])).json()
    assert detail["time_disclosed"] is True
    assert detail["my_participation"]["status"] == "accepted"
    assert detail["chat_available"] is True
    assert detail["conversation_id"]
    assert detail["participants_current"] == 2
    # превью принятых участников видно всем (организатор + гость)
    assert len(detail["accepted_participants"]) == 2

    # в чате есть системные сообщения (присоединение + время)
    cid = detail["conversation_id"]
    msgs = (await client.get(f"/conversations/{cid}/messages", headers=guest["headers"])).json()["items"]
    assert any(m["is_system"] and "Встречаемся" in m["text"] for m in msgs)


@pytest.mark.asyncio
async def test_waitlist_promotion(client, user_factory) -> None:
    org = await user_factory("Орг")
    g1 = await user_factory("Гость1")
    g2 = await user_factory("Гость2")
    ev = (await client.post("/events", headers=org["headers"],
                            json=_body(auto_accept=True, max_participants=2))).json()
    eid = ev["id"]

    # g1 заполняет единственное место
    assert (await client.post(f"/events/{eid}/join", headers=g1["headers"])).json()["status"] == "accepted"
    # g2 в лист ожидания
    assert (await client.post(f"/events/{eid}/join", headers=g2["headers"])).json()["status"] == "waitlisted"

    # g1 выходит → g2 продвигается
    await client.delete(f"/events/{eid}/join", headers=g1["headers"])
    detail = (await client.get(f"/events/{eid}", headers=g2["headers"])).json()
    assert detail["my_participation"]["status"] == "accepted"


@pytest.mark.asyncio
async def test_block_hides_event(client, user_factory) -> None:
    org = await user_factory("Орг")
    viewer = await user_factory("Зритель")
    ev = (await client.post("/events", headers=org["headers"], json=_body())).json()

    # видно до блокировки
    feed = (await client.get("/events", headers=viewer["headers"],
                             params={"lat": 55.75, "lng": 37.62, "radius_km": 10})).json()
    assert len(feed["items"]) == 1

    # viewer блокирует организатора → событие исчезает из ленты
    await client.post(f"/users/{org['id']}/block", headers=viewer["headers"])
    feed2 = (await client.get("/events", headers=viewer["headers"],
                              params={"lat": 55.75, "lng": 37.62, "radius_km": 10})).json()
    assert feed2["items"] == []

    # и присоединиться нельзя
    j = await client.post(f"/events/{ev['id']}/join", headers=viewer["headers"])
    assert j.status_code == 403


@pytest.mark.asyncio
async def test_reject(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    ev = (await client.post("/events", headers=org["headers"], json=_body())).json()
    eid = ev["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])
    parts = (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                              params={"status": "pending"})).json()["items"]
    pid = parts[0]["participation_id"]
    rej = await client.post(f"/participations/{pid}/reject", headers=org["headers"])
    assert rej.json()["status"] == "rejected"
