"""Тесты конкурентности из Блока 1 аудита: выдача мест и продвижение waitlist
не должны превышать max_participants при одновременных запросах.

Без блокировки строки события (SELECT ... FOR UPDATE) два параллельных join на
последнее место оба читали count < max и оба принимались — перебор мест.
"""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Забег",
        "description": "бежим вместе",
        "category": "sport",
        "starts_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
        "ends_at": (datetime.now(UTC) + timedelta(days=2, hours=1)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "address": "Парк",
        # Организатор сам занимает 1 место (accepted при создании). При max=3 после
        # организатора и одного гостя остаётся ровно одно место для конкурентной пары.
        "min_participants": 2,
        "max_participants": 3,
        "price": 0,
        "price_split": "free",
        "auto_accept": True,
    }
    base.update(over)
    return base


async def _accepted_count(client, headers, event_id: str) -> int:
    r = await client.get(f"/events/{event_id}/participants",
                         headers=headers, params={"status": "accepted"})
    return len(r.json()["items"])


@pytest.mark.asyncio
async def test_concurrent_joins_do_not_exceed_capacity(client, user_factory) -> None:
    org = await user_factory("Орг")
    g1 = await user_factory("Гость1")
    g2 = await user_factory("Гость2")
    g3 = await user_factory("Гость3")

    # max=3, auto_accept. Организатор(1) + g1(1) = 2 занято, остаётся ровно одно место.
    ev = await client.post("/events", headers=org["headers"], json=_event_body())
    event_id = ev.json()["id"]
    await client.post(f"/events/{event_id}/join", headers=g1["headers"])

    # Два гостя откликаются ОДНОВРЕМЕННО на единственное оставшееся место.
    r2, r3 = await asyncio.gather(
        client.post(f"/events/{event_id}/join", headers=g2["headers"]),
        client.post(f"/events/{event_id}/join", headers=g3["headers"]),
    )
    statuses = sorted([r2.json()["status"], r3.json()["status"]])

    # Ровно один принят, второй — в листе ожидания. Перебора быть не должно.
    assert statuses == ["accepted", "waitlisted"], statuses
    assert await _accepted_count(client, org["headers"], event_id) == 3


@pytest.mark.asyncio
async def test_concurrent_accepts_do_not_exceed_capacity(client, user_factory) -> None:
    org = await user_factory("Орг")
    g1 = await user_factory("Гость1")
    g2 = await user_factory("Гость2")
    g3 = await user_factory("Гость3")

    # Ручное подтверждение (auto_accept=False), max=3. Организатор(1)+g1(1) займут 2 места.
    ev = await client.post("/events", headers=org["headers"], json=_event_body(auto_accept=False))
    event_id = ev.json()["id"]
    await client.post(f"/events/{event_id}/join", headers=g1["headers"])
    for g in (g2, g3):
        await client.post(f"/events/{event_id}/join", headers=g["headers"])

    pending = (await client.get(f"/events/{event_id}/participants",
                                headers=org["headers"], params={"status": "pending"})).json()["items"]
    ids = [p["participation_id"] for p in pending]

    # Сначала подтверждаем g1 (занимает 1-е место), затем ОДНОВРЕМЕННО g2 и g3 на последнее.
    g1_pid = next(p["participation_id"] for p in pending if p["user"]["name"] == "Гость1")
    await client.post(f"/participations/{g1_pid}/accept", headers=org["headers"])
    rest = [pid for pid in ids if pid != g1_pid]

    r1, r2 = await asyncio.gather(
        client.post(f"/participations/{rest[0]}/accept", headers=org["headers"]),
        client.post(f"/participations/{rest[1]}/accept", headers=org["headers"]),
    )
    # Один accept проходит, второй упирается в event_full (409). Принято ровно 2 (включая g1).
    codes = sorted([r1.status_code, r2.status_code])
    assert codes == [200, 409], codes
    assert await _accepted_count(client, org["headers"], event_id) == 3
