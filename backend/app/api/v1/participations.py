import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Query, status
from sqlalchemy import func, select

from app.core.config import settings
from app.core.deps import CompleteUser, CurrentUser, DbSession, RedisDep
from app.core.exceptions import conflict, forbidden, not_found
from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.participation import Participation
from app.models.user import User
from app.schemas.participation import (
    JoinOut,
    MyApplicationItem,
    MyApplicationsOut,
    ParticipantItem,
    ParticipantsOut,
)
from app.schemas.user import UserPublic
from app.services import event_service, matching_service, push_service
from app.services.rate_limit import check_user_action

router = APIRouter(tags=["participations"])


@router.post("/events/{event_id}/join", response_model=JoinOut)
async def join_event(
    event_id: uuid.UUID, current_user: CompleteUser, db: DbSession, redis: RedisDep
) -> JoinOut:
    await check_user_action(
        redis, current_user.id, "join_event", settings.user_rl_joins_per_hour, 3600
    )
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

    # Критическая секция: блокируем строку события, чтобы проверка «есть место» и запись
    # статуса были атомарны относительно других join/accept/leave (иначе гонка → перебор мест).
    locked = await matching_service.lock_event(db, event_id)
    if locked is None:
        raise not_found("Событие не найдено")
    count = await matching_service.accepted_count(db, event_id)
    has_space = locked.max_participants is None or count < locked.max_participants
    # Приглашение — это уже согласие организатора: заново рассматривать заявку не нужно.
    was_invited = part is not None and part.status == "invited"
    if (locked.auto_accept or was_invited) and has_space:
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
    if new_status == "accepted":
        await matching_service.refresh_capacity_status(db, locked)
    await db.commit()  # освобождает блокировку события

    if new_status == "accepted":
        await matching_service.on_accept(db, locked, current_user)
        if was_invited:  # организатор ждёт ответа на своё приглашение
            await push_service.send_push(
                db, event.organizer_id, "Придёт",
                f"{current_user.name} принял ваше приглашение на «{event.title}»",
                {"event_id": str(event_id)},
            )
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
        # promote_waitlist берёт блокировку события, продвигает лист ожидания и синхронизирует
        # статус open/full под ней — ручной сброс full→open здесь больше не нужен (гонки нет).
        await matching_service.promote_waitlist(db, event)


ACTIVE_APPLICATION_STATUSES = ("invited", "pending", "accepted", "waitlisted")


@router.get("/participations/mine", response_model=MyApplicationsOut)
async def my_applications(
    current_user: CurrentUser,
    db: DbSession,
    status_filter: str | None = Query(
        None, alias="status", pattern="^(invited|pending|accepted|waitlisted|rejected|cancelled)$"
    ),
) -> MyApplicationsOut:
    """Мои отклики одним списком.

    До этого статус заявки жил только внутри карточки события: откликнулся на три
    штуки — и вспоминай, где что. Здесь всё видно сразу, ближайшее сверху.
    """
    statuses = (status_filter,) if status_filter else ACTIVE_APPLICATION_STATUSES

    # Количество принятых — коррелированным подзапросом, чтобы не делать запрос на событие.
    accepted_sq = (
        select(func.count())
        .select_from(Participation)
        .where(Participation.event_id == Event.id, Participation.status == "accepted")
        .correlate(Event)
        .scalar_subquery()
    )

    rows = (
        await db.execute(
            select(Participation, Event, User, accepted_sq)
            .join(Event, Event.id == Participation.event_id)
            .join(User, User.id == Event.organizer_id)
            .where(
                Participation.user_id == current_user.id,
                Participation.status.in_(statuses),
            )
            .order_by(Event.starts_at.asc())
        )
    ).all()

    return MyApplicationsOut(
        items=[
            MyApplicationItem(
                participation_id=part.id,
                status=part.status,
                created_at=part.created_at,
                event=event_service.build_list_item(
                    event,
                    organizer,
                    viewer_id=current_user.id,
                    my_status=part.status,
                    participants_current=accepted,
                    distance_km=None,
                ),
            )
            for part, event, organizer, accepted in rows
        ]
    )


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
    # Блокируем событие: решение о принятии и проверка лимита атомарны (иначе двойной
    # accept/двойной клик могут превысить max_participants).
    event = await matching_service.lock_event(db, part.event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может решать по заявкам")

    if decision == "accept":
        mx = event.max_participants
        if mx is not None and await matching_service.accepted_count(db, event.id) >= mx:
            raise conflict("event_full", "Мест больше нет")
        part.status = "accepted"
        part.decided_at = datetime.now(UTC)
        await matching_service.refresh_capacity_status(db, event)
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


@router.delete("/participations/{participation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_participant(
    participation_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> None:
    """Организатор освобождает занятое место.

    Раньше выхода не было: человек пропал — место оставалось мёртвым, и лист ожидания
    не двигался. Статус ставим «rejected», как при отказе по заявке: повторно откликнуться
    можно, а от навязчивых есть блокировка.
    """
    part = await db.get(Participation, participation_id)
    if part is None:
        raise not_found("Заявка не найдена")
    event = await db.get(Event, part.event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может убрать участника")
    if part.user_id == event.organizer_id:
        raise conflict("cannot_remove_organizer", "Организатора нельзя убрать из своего события")
    if part.status not in ("accepted", "pending", "waitlisted", "invited"):
        raise conflict("not_participating", "Этот человек и так не в составе")

    was_accepted = part.status == "accepted"
    part.status = "rejected"
    part.decided_at = datetime.now(UTC)
    await db.commit()

    # Убираем из беседы события: доступа к переписке у выбывшего быть не должно.
    conv_id = (
        await db.execute(select(Conversation.id).where(Conversation.event_id == event.id))
    ).scalar_one_or_none()
    if conv_id is not None:
        member = (
            await db.execute(
                select(ConversationMember).where(
                    ConversationMember.conversation_id == conv_id,
                    ConversationMember.user_id == part.user_id,
                )
            )
        ).scalar_one_or_none()
        if member is not None:
            await db.delete(member)
            await db.commit()

    await push_service.send_push(
        db, part.user_id, "Вы больше не в составе",
        f"Организатор «{event.title}» освободил ваше место", {"event_id": str(event.id)},
    )
    if was_accepted:
        await matching_service.promote_waitlist(db, event)
