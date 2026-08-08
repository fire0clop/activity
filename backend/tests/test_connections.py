"""Связи, заработанные встречами.

Главное правило под проверкой: право на контакт даёт совместная завершённая встреча,
а не поиск и не кнопка. Каталога людей в продукте нет.
"""

from datetime import UTC, datetime, timedelta

import pytest

from app.services import push_service


def _body(**over):
    base = {
        "title": "Теннис",
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


async def _met(client, org, guest, **over):
    """Организатор и гость сходили на одну встречу, событие завершено."""
    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(**over))).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])
    await client.post(f"/events/{eid}/finish", headers=org["headers"])
    return eid


@pytest.mark.asyncio
async def test_connection_appears_only_after_finished_event(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")

    eid = (await client.post("/events", headers=org["headers"], json=_body())).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])

    # событие ещё не прошло — знакомства нет
    assert (await client.get("/connections", headers=org["headers"])).json()["items"] == []

    await client.post(f"/events/{eid}/finish", headers=org["headers"])

    items = (await client.get("/connections", headers=org["headers"])).json()["items"]
    assert len(items) == 1
    assert items[0]["user"]["id"] == guest["id"]
    assert items[0]["meetings"] == 1
    assert items[0]["last_event_title"] == "Теннис"
    assert items[0]["mutual"] is False


@pytest.mark.asyncio
async def test_meetings_accumulate_and_mutual_follow_marks_own(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await _met(client, org, guest, title="Первая")
    await _met(client, org, guest, title="Вторая")

    await client.post(f"/users/{guest['id']}/follow", headers=org["headers"])
    await client.post(f"/users/{org['id']}/follow", headers=guest["headers"])

    item = (await client.get("/connections", headers=org["headers"])).json()["items"][0]
    assert item["meetings"] == 2
    assert item["last_event_title"] == "Вторая"
    assert item["i_follow"] and item["follows_me"] and item["mutual"]


@pytest.mark.asyncio
async def test_stranger_is_not_a_connection(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    outsider = await user_factory("Чужак")
    await _met(client, org, guest)

    # посторонний не видит никого и не виден никому
    assert (await client.get("/connections", headers=outsider["headers"])).json()["items"] == []
    ids = [i["user"]["id"] for i in
           (await client.get("/connections", headers=org["headers"])).json()["items"]]
    assert outsider["id"] not in ids


@pytest.mark.asyncio
async def test_direct_chat_requires_shared_meeting(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    outsider = await user_factory("Чужак")

    # без общей встречи — нельзя
    denied = await client.post(f"/connections/{guest['id']}/chat", headers=outsider["headers"])
    assert denied.status_code == 403

    await _met(client, org, guest)
    ok = await client.post(f"/connections/{guest['id']}/chat", headers=org["headers"])
    assert ok.status_code == 200
    cid = ok.json()["conversation_id"]

    # идемпотентно: второй вызов возвращает ту же беседу
    again = await client.post(f"/connections/{guest['id']}/chat", headers=org["headers"])
    assert again.json()["conversation_id"] == cid

    # и с другой стороны — тоже она
    from_other_side = await client.post(f"/connections/{org['id']}/chat", headers=guest["headers"])
    assert from_other_side.json()["conversation_id"] == cid


@pytest.mark.asyncio
async def test_direct_chat_named_by_peer(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await _met(client, org, guest)
    cid = (await client.post(f"/connections/{guest['id']}/chat",
                             headers=org["headers"])).json()["conversation_id"]

    mine = (await client.get("/conversations", headers=org["headers"])).json()["items"]
    direct = next(c for c in mine if c["id"] == cid)
    assert direct["type"] == "direct"
    assert direct["title"] == "Гость"   # у личной беседы нет своего названия

    theirs = (await client.get("/conversations", headers=guest["headers"])).json()["items"]
    assert next(c for c in theirs if c["id"] == cid)["title"] == "Орг"


@pytest.mark.asyncio
async def test_cannot_chat_with_self(client, user_factory) -> None:
    org = await user_factory("Орг")
    resp = await client.post(f"/connections/{org['id']}/chat", headers=org["headers"])
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_invite_only_known_people(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    friend = await user_factory("Знакомый")
    stranger = await user_factory("Незнакомец")
    await client.post("/devices", headers=friend["headers"],
                      json={"token": "tok-friend", "platform": "ios"})
    await _met(client, org, friend)

    new_event = (await client.post("/events", headers=org["headers"],
                                   json=_body(title="Новая движуха",
                                              auto_accept=False))).json()["id"]
    resp = await client.post(f"/events/{new_event}/invite", headers=org["headers"],
                             json={"user_ids": [friend["id"], stranger["id"]]})
    assert resp.status_code == 200
    assert resp.json() == {"invited": 1, "skipped": 1}   # незнакомца звать нельзя
    assert any(p["title"] == "Вас зовут" and p["token"] == "tok-friend" for p in apns_recorder)

    # приглашённый видит приглашение, но в составе его ещё нет
    detail = (await client.get(f"/events/{new_event}", headers=friend["headers"])).json()
    assert detail["my_participation"]["status"] == "invited"
    assert detail["participants_current"] == 1          # только организатор


@pytest.mark.asyncio
async def test_invited_join_skips_review(client, user_factory) -> None:
    """Организатор уже сказал «да» — рассматривать заявку повторно не нужно."""
    org = await user_factory("Орг")
    friend = await user_factory("Знакомый")
    await _met(client, org, friend)

    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(title="Новая", auto_accept=False))).json()["id"]
    await client.post(f"/events/{eid}/invite", headers=org["headers"],
                      json={"user_ids": [friend["id"]]})

    joined = await client.post(f"/events/{eid}/join", headers=friend["headers"])
    assert joined.json()["status"] == "accepted"        # без auto_accept и без ожидания

    detail = (await client.get(f"/events/{eid}", headers=friend["headers"])).json()
    assert detail["chat_available"] is True


@pytest.mark.asyncio
async def test_invitation_can_be_declined(client, user_factory) -> None:
    org = await user_factory("Орг")
    friend = await user_factory("Знакомый")
    await _met(client, org, friend)
    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(title="Новая"))).json()["id"]
    await client.post(f"/events/{eid}/invite", headers=org["headers"],
                      json={"user_ids": [friend["id"]]})

    assert (await client.delete(f"/events/{eid}/join",
                                headers=friend["headers"])).status_code == 204
    detail = (await client.get(f"/events/{eid}", headers=friend["headers"])).json()
    assert detail["my_participation"]["status"] == "cancelled"


@pytest.mark.asyncio
async def test_invite_requires_organizer(client, user_factory) -> None:
    org = await user_factory("Орг")
    friend = await user_factory("Знакомый")
    await _met(client, org, friend)
    eid = (await client.post("/events", headers=org["headers"], json=_body())).json()["id"]

    resp = await client.post(f"/events/{eid}/invite", headers=friend["headers"],
                             json={"user_ids": [org["id"]]})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_invitation_shows_in_my_applications(client, user_factory) -> None:
    org = await user_factory("Орг")
    friend = await user_factory("Знакомый")
    await _met(client, org, friend)
    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(title="Позвали сюда"))).json()["id"]
    await client.post(f"/events/{eid}/invite", headers=org["headers"],
                      json={"user_ids": [friend["id"]]})

    items = (await client.get("/participations/mine", headers=friend["headers"])).json()["items"]
    invited = [i for i in items if i["status"] == "invited"]
    assert [i["event"]["title"] for i in invited] == ["Позвали сюда"]


@pytest.mark.asyncio
async def test_blocked_person_disappears_from_connections(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await _met(client, org, guest)
    assert (await client.get("/connections", headers=org["headers"])).json()["items"]

    await client.post(f"/users/{guest['id']}/block", headers=org["headers"])
    assert (await client.get("/connections", headers=org["headers"])).json()["items"] == []
