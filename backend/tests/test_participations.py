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


@pytest.mark.asyncio
async def test_my_applications_lists_active_only(client, user_factory) -> None:
    """Свои отклики видно одним списком, а не по одному внутри карточек."""
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    e1 = (await client.post("/events", headers=org["headers"],
                            json=_body(title="Теннис"))).json()["id"]
    e2 = (await client.post("/events", headers=org["headers"],
                            json=_body(title="Прогулка", auto_accept=True))).json()["id"]

    await client.post(f"/events/{e1}/join", headers=guest["headers"])   # pending
    await client.post(f"/events/{e2}/join", headers=guest["headers"])   # accepted

    items = (await client.get("/participations/mine", headers=guest["headers"])).json()["items"]
    by_title = {i["event"]["title"]: i["status"] for i in items}
    assert by_title == {"Теннис": "pending", "Прогулка": "accepted"}

    # отменённый отклик уходит из активного списка, но доступен фильтром
    await client.delete(f"/events/{e1}/join", headers=guest["headers"])
    active = (await client.get("/participations/mine", headers=guest["headers"])).json()["items"]
    assert [i["event"]["title"] for i in active] == ["Прогулка"]

    cancelled = (await client.get("/participations/mine", headers=guest["headers"],
                                  params={"status": "cancelled"})).json()["items"]
    assert [i["event"]["title"] for i in cancelled] == ["Теннис"]


@pytest.mark.asyncio
async def test_organizer_removes_participant_and_waitlist_moves(client, user_factory) -> None:
    """Освобождённое место должно уходить очереди, а не пропадать."""
    org = await user_factory("Орг")
    g1 = await user_factory("Гость1")
    g2 = await user_factory("Гость2")
    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(auto_accept=True, max_participants=2))).json()["id"]

    assert (await client.post(f"/events/{eid}/join",
                              headers=g1["headers"])).json()["status"] == "accepted"
    assert (await client.post(f"/events/{eid}/join",
                              headers=g2["headers"])).json()["status"] == "waitlisted"

    pid = next(
        p["participation_id"]
        for p in (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                                   params={"status": "accepted"})).json()["items"]
        if p["user"]["id"] == g1["id"]
    )
    assert (await client.delete(f"/participations/{pid}",
                                headers=org["headers"])).status_code == 204

    # g1 выбыл, g2 подтянулся из очереди
    d1 = (await client.get(f"/events/{eid}", headers=g1["headers"])).json()
    assert d1["my_participation"]["status"] == "rejected"
    d2 = (await client.get(f"/events/{eid}", headers=g2["headers"])).json()
    assert d2["my_participation"]["status"] == "accepted"


@pytest.mark.asyncio
async def test_remove_participant_requires_organizer(client, user_factory) -> None:
    org = await user_factory("Орг")
    g1 = await user_factory("Гость1")
    other = await user_factory("Посторонний")
    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(auto_accept=True, max_participants=3))).json()["id"]
    await client.post(f"/events/{eid}/join", headers=g1["headers"])

    pid = next(
        p["participation_id"]
        for p in (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                                   params={"status": "accepted"})).json()["items"]
        if p["user"]["id"] == g1["id"]
    )
    assert (await client.delete(f"/participations/{pid}",
                                headers=other["headers"])).status_code == 403

    # и самого себя организатор из состава не выкинет
    own = next(
        p["participation_id"]
        for p in (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                                   params={"status": "accepted"})).json()["items"]
        if p["user"]["id"] == org["id"]
    )
    assert (await client.delete(f"/participations/{own}",
                                headers=org["headers"])).status_code == 409
