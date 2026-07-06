"""Блок 3: модерация — разбор жалоб и бан пользователей через /admin (X-Admin-Key)."""

import pytest

from app.core.config import settings

ADMIN_KEY = "test-admin-key"


@pytest.fixture(autouse=True)
def _enable_admin():
    prev = settings.admin_api_key
    settings.admin_api_key = ADMIN_KEY
    yield
    settings.admin_api_key = prev


def _hdr(user):
    return user["headers"]


@pytest.mark.asyncio
async def test_admin_requires_key(client, user_factory) -> None:
    await user_factory("Кто-то")
    # Без ключа — 403.
    assert (await client.get("/admin/reports")).status_code == 403
    # С неверным ключом — 403.
    assert (await client.get("/admin/reports", headers={"X-Admin-Key": "wrong"})).status_code == 403
    # С верным — 200.
    ok = await client.get("/admin/reports", headers={"X-Admin-Key": ADMIN_KEY})
    assert ok.status_code == 200


@pytest.mark.asyncio
async def test_report_review_flow(client, user_factory) -> None:
    reporter = await user_factory("Жалобщик")
    target = await user_factory("Нарушитель")
    await client.post("/reports", headers=_hdr(reporter),
                      json={"target_user_id": target["id"], "reason": "spam", "comment": "бот"})

    admin = {"X-Admin-Key": ADMIN_KEY}
    reports = (await client.get("/admin/reports", headers=admin, params={"status": "new"})).json()
    assert len(reports) == 1
    rid = reports[0]["id"]

    upd = await client.post(f"/admin/reports/{rid}/status", headers=admin, json={"status": "reviewed"})
    assert upd.status_code == 200 and upd.json()["status"] == "reviewed"
    # Больше нет "new".
    assert (await client.get("/admin/reports", headers=admin, params={"status": "new"})).json() == []


@pytest.mark.asyncio
async def test_ban_blocks_authentication(client, user_factory) -> None:
    victim = await user_factory("Бан")
    admin = {"X-Admin-Key": ADMIN_KEY}

    # До бана — доступ есть.
    assert (await client.get("/users/me", headers=_hdr(victim))).status_code == 200

    ban = await client.post(f"/admin/users/{victim['id']}/ban", headers=admin)
    assert ban.status_code == 204
    # Забаненный не проходит аутентификацию (403 account_banned).
    blocked = await client.get("/users/me", headers=_hdr(victim))
    assert blocked.status_code == 403
    assert blocked.json()["error"]["code"] == "account_banned"

    # Разбан возвращает доступ.
    assert (await client.post(f"/admin/users/{victim['id']}/unban", headers=admin)).status_code == 204
    assert (await client.get("/users/me", headers=_hdr(victim))).status_code == 200
