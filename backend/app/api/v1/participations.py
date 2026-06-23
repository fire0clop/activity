import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Query, status
from sqlalchemy import select

from app.core.deps import CompleteUser, CurrentUser, DbSession
from app.core.exceptions import conflict, forbidden, not_found
from app.models.event import Event
from app.models.participation import Participation
from app.models.user import User
from app.schemas.participation import JoinOut, ParticipantItem, ParticipantsOut
from app.schemas.user import UserPublic
from app.services import matching_service, push_service

router = APIRouter(tags=["participations"])


@router.post("/events/{event_id}/join", response_model=JoinOut)
async def join_event(event_id: uuid.UUID, current_user: CompleteUser, db: DbSession) -> JoinOut:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.status in ("closed", "cancelled", "finished"):
        raise conflict("event_closed", "Событие закрыто")
    if event.organizer_id == current_user.id:
        raise conflict("already_joined", "Вы организатор этого события")

    # Блокировки: нельзя присоединиться к событию того, кто заблокирован (в любую сторону).
    blocked = await matching_service.blocked_user_ids(db, current_user.id)
    if event.organizer_id in blocked:
        raise forbidden("Действие недоступно")

    existing = await db.execute(
        select(Participation).where(
            Participation.event_id == event_id, Participation.user_id == current_user.id
        )
    )
    part = existing.scalar_one_or_none()
    if part is not None and part.status in ("pending", "accepted", "waitlisted"):
        raise conflict("already_joined", "Вы уже откликнулись")

    count = await matching_service.accepted_count(db, event_id)
    has_space = event.max_participants is None or count < event.max_participants
    if event.auto_accept and has_space:
        new_status = "accepted"
    elif has_space:
        new_status = "pending"
    else:
        new_status = "waitlisted"

    if part is not None:  # повторный отклик после cancelled/rejected
        part.status = new_status
        part.decided_at = datetime.now(UTC) if new_status == "accepted" else None
    else:
        part = Participation(
            event_id=event_id, user_id=current_user.id, status=new_status,
            decided_at=datetime.now(UTC) if new_status == "accepted" else None,
        )
        db.add(part)
    await db.commit()

    if new_status == "accepted":
        await matching_service.on_accept(db, event, current_user)
    else:
        await push_service.send_push(
            db, event.organizer_id, "Новая заявка",
            f"{current_user.name} хочет присоединиться к «{event.title}»",
            {"event_id": str(event_id)},
        )
    return JoinOut(status=new_status)


@router.delete("/events/{event_id}/join", status_code=status.HTTP_204_NO_CONTENT)
async def leave_event(event_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> None:
    result = await db.execute(
        select(Participation).where(
            Participation.event_id == event_id, Participation.user_id == current_user.id
        )
    )
    part = result.scalar_one_or_none()
    if part is None:
        raise not_found("Заявка не найдена")
    was_accepted = part.status == "accepted"
    part.status = "cancelled"
    await db.commit()

    if was_accepted:
        event = await db.get(Event, event_id)
        if event.status == "full":
            event.status = "open"
            await db.commit()
        await matching_service.promote_waitlist(db, event)


@router.get("/events/{event_id}/participants", response_model=ParticipantsOut)
async def list_participants(
    event_id: uuid.UUID,
    current_user: CurrentUser,
    db: DbSession,
    status_filter: str | None = Query(None, alias="status"),
) -> ParticipantsOut:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")

    is_organizer = event.organizer_id == current_user.id
    stmt = select(Participation, User).join(User, User.id == Participation.user_id).where(
        Participation.event_id == event_id
    )
    if not is_organizer:
        # Не организатор видит только подтверждённых (что бы ни передал в status).
        stmt = stmt.where(Participation.status == "accepted")
    elif status_filter:
        stmt = stmt.where(Participation.status == status_filter)

    rows = (await db.execute(stmt.order_by(Participation.created_at.asc()))).all()
    items = [
        ParticipantItem(
            participation_id=p.id, user=UserPublic.from_model(u),
            status=p.status, created_at=p.created_at,
        )
        for p, u in rows
    ]
    return ParticipantsOut(items=items)


async def _decide(participation_id: uuid.UUID, current_user: User, db: DbSession,
                  decision: str) -> JoinOut:
    part = await db.get(Participation, participation_id)
    if part is None:
        raise not_found("Заявка не найдена")
    event = await db.get(Event, part.event_id)
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может решать по заявкам")

    if decision == "accept":
        mx = event.max_participants
        if mx is not None and await matching_service.accepted_count(db, event.id) >= mx:
            raise conflict("event_full", "Мест больше нет")
        part.status = "accepted"
        part.decided_at = datetime.now(UTC)
        await db.commit()
        participant = await db.get(User, part.user_id)
        await matching_service.on_accept(db, event, participant)
        return JoinOut(status="accepted")

    part.status = "rejected"
    part.decided_at = datetime.now(UTC)
    await db.commit()
    await push_service.send_push(
        db, part.user_id, "Заявка отклонена",
        f"Организатор «{event.title}» отклонил вашу заявку", {"event_id": str(event.id)},
    )
    return JoinOut(status="rejected")


@router.post("/participations/{participation_id}/accept", response_model=JoinOut)
async def accept_participation(
    participation_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> JoinOut:
    return await _decide(participation_id, current_user, db, "accept")


@router.post("/participations/{participation_id}/reject", response_model=JoinOut)
async def reject_participation(
    participation_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> JoinOut:
    return await _decide(participation_id, current_user, db, "reject")
