"""Форма поддержки: адрес обязателен для публикации в App Store.

Проверяем то, ради чего она заведена: обращение доходит без входа в приложение
(часто пишут именно потому, что войти не получается) и её нельзя залить ботами.
"""

import pytest
from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.support import SupportTicket


def _body(**over):
    base = {"contact": "ivan@example.com", "message": "Не приходит код по SMS, помогите войти."}
    base.update(over)
    return base


@pytest.mark.asyncio
async def test_ticket_accepted_without_auth(client) -> None:
    resp = await client.post("/support", json=_body())
    assert resp.status_code == 204

    async with SessionLocal() as db:
        rows = (await db.execute(select(SupportTicket))).scalars().all()
    assert [(r.contact, r.is_handled) for r in rows] == [("ivan@example.com", False)]


@pytest.mark.asyncio
async def test_empty_and_short_rejected(client) -> None:
    assert (await client.post("/support", json=_body(message="ой"))).status_code == 422
    assert (await client.post("/support", json=_body(contact=""))).status_code == 422


@pytest.mark.asyncio
async def test_flood_is_cut_off(client) -> None:
    """Форма открыта всем, поэтому лимит по адресу — не украшение."""
    codes = [(await client.post("/support", json=_body())).status_code for _ in range(7)]
    assert codes.count(204) == 5
    assert codes.count(429) == 2
