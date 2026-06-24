import uuid

from fastapi import APIRouter, status
from sqlalchemy import select

from app.core.deps import CurrentUser, DbSession
from app.models.report import Block, DeviceToken, Report
from app.schemas.review import DeviceIn, ReportCreateIn, ReportOut

router = APIRouter(tags=["reports"])


@router.post("/reports", response_model=ReportOut, status_code=status.HTTP_201_CREATED)
async def create_report(body: ReportCreateIn, current_user: CurrentUser, db: DbSession) -> ReportOut:
    report = Report(
        reporter_id=current_user.id,
        target_user_id=body.target_user_id,
        target_event_id=body.target_event_id,
        reason=body.reason,
        comment=body.comment,
        status="new",
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)
    return ReportOut(id=report.id, status=report.status)


@router.post("/users/{user_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def block_user(user_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> None:
    existing = await db.execute(
        select(Block).where(Block.blocker_id == current_user.id, Block.blocked_id == user_id)
    )
    if existing.scalar_one_or_none() is None:
        db.add(Block(blocker_id=current_user.id, blocked_id=user_id))
        await db.commit()


@router.delete("/users/{user_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def unblock_user(user_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> None:
    existing = await db.execute(
        select(Block).where(Block.blocker_id == current_user.id, Block.blocked_id == user_id)
    )
    row = existing.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()


@router.post("/devices", status_code=status.HTTP_204_NO_CONTENT)
async def register_device(body: DeviceIn, current_user: CurrentUser, db: DbSession) -> None:
    existing = await db.execute(select(DeviceToken).where(DeviceToken.token == body.token))
    row = existing.scalar_one_or_none()
    if row is None:
        db.add(DeviceToken(user_id=current_user.id, token=body.token, platform=body.platform))
    else:
        row.user_id = current_user.id
        row.platform = body.platform
    await db.commit()


@router.delete("/devices/{token}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(token: str, current_user: CurrentUser, db: DbSession) -> None:
    existing = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == token, DeviceToken.user_id == current_user.id
        )
    )
    row = existing.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()
