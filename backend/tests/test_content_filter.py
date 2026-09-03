"""Фильтр недопустимого текста (App Store 1.2: filtering objectionable content).

Две вещи под проверкой: грязь не проходит ни в одну дверь, а обычная речь —
включая слова, похожие на маты по подстроке, — проходит свободно.
"""

from datetime import UTC, datetime, timedelta

import pytest

from app.services.content_filter import is_objectionable


def test_obvious_profanity_caught() -> None:
    assert is_objectionable("Пиздец какой вечер")
    assert is_objectionable("собрались одни мудаки")   # словоформа от корня
    assert is_objectionable("ЁБАНЫЙ стыд")             # регистр и «ё»
    assert is_objectionable("what the fuck")


def test_innocent_lookalikes_pass() -> None:
    """Слова, в которых мат — лишь подстрока, фильтр трогать не должен."""
    for text in ("ребята, собираемся у входа",         # «ебят» внутри слова
                 "возьмите скипидар и растворитель",   # «пидар» внутри слова
                 "оскорбление — повод для жалобы",
                 "рубля не хватает",                   # «бля» внутри слова
                 "команда употребила все силы"):
        assert not is_objectionable(text), text


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
async def test_event_with_profanity_rejected(client, user_factory) -> None:
    org = await user_factory("Орг")
    resp = await client.post("/events", headers=org["headers"],
                             json=_event(title="Пиздатый вечер"))
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "objectionable_content"

    ok = await client.post("/events", headers=org["headers"],
                           json=_event(title="Ребята, собираемся!"))
    assert ok.status_code == 201


@pytest.mark.asyncio
async def test_wish_and_profile_filtered(client, user_factory) -> None:
    u = await user_factory("Автор")
    resp = await client.post("/requests", headers=u["headers"],
                             json={"category": "bar", "text": "хочу нажраться, блядь",
                                   "latitude": 55.75, "longitude": 37.62,
                                   "radius_km": 10, "when_window": "week"})
    assert resp.status_code == 422

    resp = await client.patch("/users/me", headers=u["headers"],
                              json={"bio": "мудацкое настроение"})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_block_lands_in_moderation_queue(client, user_factory) -> None:
    """Блокировка — сигнал модерации, а не только личный фильтр (1.2)."""
    from sqlalchemy import select

    from app.db.session import SessionLocal
    from app.models.report import Report

    a = await user_factory("Блокирующий")
    b = await user_factory("Обидчик")
    assert (await client.post(f"/users/{b['id']}/block",
                              headers=a["headers"])).status_code == 204

    async with SessionLocal() as db:
        rows = (await db.execute(select(Report).where(
            Report.reason == "block"))).scalars().all()
    assert [(str(r.target_user_id), r.status) for r in rows] == [(b["id"], "new")]
