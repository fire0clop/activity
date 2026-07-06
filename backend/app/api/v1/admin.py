"""Модерация (App Store Guideline 1.2 для UGC): разбор жалоб и бан пользователей.

Доступ по ключу оператора в заголовке X-Admin-Key (ADMIN_API_KEY). Пустой ключ в
конфиге полностью отключает админ-доступ (deny-by-default).
"""

import secrets
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Query
from pydantic import BaseModel
from sqlalchemy import select, update

from app.core.config import settings
from app.core.deps import DbSession
from app.core.exceptions import AppError, not_found
from app.models.report import Report
from app.models.user import RefreshToken, User

router = APIRouter(prefix="/admin", tags=["admin"])

_VALID_REPORT_STATUS = {"new", "reviewed", "actioned"}


async def require_admin(x_admin_key: Annotated[str, Header()] = "") -> None:
    key = settings.admin_api_key
    # Пустой ключ => админка выключена. Сравнение постоянного времени против тайминга.
    if not key or not secrets.compare_digest(x_admin_key, key):
        raise AppError("forbidden", "Нет доступа", 403)


AdminGuard = Annotated[None, Depends(require_admin)]


class ReportOut(BaseModel):
    id: uuid.UUID
    reporter_id: uuid.UUID
    target_user_id: uuid.UUID | None
    target_event_id: uuid.UUID | None
    reason: str
    comment: str | None
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


class ReportStatusIn(BaseModel):
    status: str


@router.get("/reports", response_model=list[ReportOut])
async def list_reports(
    _: AdminGuard,
    db: DbSession,
    status_filter: str | None = Query(None, alias="status"),
    limit: int = Query(50, ge=1, le=200),
) -> list[Report]:
    stmt = select(Report).order_by(Report.created_at.desc()).limit(limit)
    if status_filter:
        stmt = stmt.where(Report.status == status_filter)
    return list((await db.execute(stmt)).scalars().all())


@router.post("/reports/{report_id}/status", response_model=ReportOut)
async def set_report_status(
    report_id: uuid.UUID, body: ReportStatusIn, _: AdminGuard, db: DbSession
) -> Report:
    if body.status not in _VALID_REPORT_STATUS:
        raise AppError("validation_error", "Недопустимый статус жалобы", 422)
    report = await db.get(Report, report_id)
    if report is None:
        raise not_found("Жалоба не найдена")
    report.status = body.status
    await db.commit()
    await db.refresh(report)
    return report


@router.post("/users/{user_id}/ban", status_code=204)
async def ban_user(user_id: uuid.UUID, _: AdminGuard, db: DbSession) -> None:
    user = await db.get(User, user_id)
    if user is None:
        raise not_found("Пользователь не найден")
    user.is_banned = True
    # Гасим refresh-токены, чтобы забаненный не получал новые access-токены.
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked.is_(False))
        .values(revoked=True)
    )
    await db.commit()


@router.post("/users/{user_id}/unban", status_code=204)
async def unban_user(user_id: uuid.UUID, _: AdminGuard, db: DbSession) -> None:
    user = await db.get(User, user_id)
    if user is None:
        raise not_found("Пользователь не найден")
    user.is_banned = False
    await db.commit()
