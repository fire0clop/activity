import logging
import uuid
from datetime import UTC, datetime

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event
from app.models.participation import Participation
from app.models.report import Block
from app.models.user import User
from app.services import chat_service, push_service

logger = logging.getLogger("matching")


async def accepted_count(db: AsyncSession, event_id: uuid.UUID) -> int:
    result = await db.execute(
        select(func.count()).select_from(Participation).where(
            Participation.event_id == event_id, Participation.status == "accepted"
        )
    )
    return int(result.scalar() or 0)


async def lock_event(db: AsyncSession, event_id: uuid.UUID) -> Event | None:
    """Блокирует строку события (SELECT ... FOR UPDATE) на время транзакции.

    Сериализует конкурентные join/accept/leave по одному событию: без этого два
    одновременных отклика на последнее место оба проходили проверку count < max.
    """
    return (
        await db.execute(select(Event).where(Event.id == event_id).with_for_update())
    ).scalar_one_or_none()


async def refresh_capacity_status(db: AsyncSession, event: Event) -> None:
    """Синхронизирует open/full по фактическому числу принятых. Вызывать ПОД блокировкой события."""
    if event.max_participants is None:
        return
    cnt = await accepted_count(db, event.id)
    if cnt >= event.max_participants and event.status == "open":
        event.status = "full"
    elif cnt < event.max_participants and event.status == "full":
        event.status = "open"


async def blocked_user_ids(db: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    """Все пользователи, скрытые от данного: кого он заблокировал И кто заблокировал его."""
    rows = await db.execute(
        select(Block.blocker_id, Block.blocked_id).where(
            or_(Block.blocker_id == user_id, Block.blocked_id == user_id)
        )
    )
    blocked: set[uuid.UUID] = set()
    for blocker_id, blocked_id in rows.all():
        blocked.add(blocked_id if blocker_id == user_id else blocker_id)
    return blocked


def format_time(event: Event) -> str:
    t = event.starts_at.strftime("%d.%m %H:%M UTC")
    return f"Точное время: {t}. Место: {event.address or '—'}"


async def on_accept(db: AsyncSession, event: Event, participant: User) -> None:
    """ТОЛЬКО побочные эффекты подтверждения (чат, раскрытие времени, счётчик, push).

    Место уже зафиксировано в отдельной транзакции ПОД блокировкой события. Ошибки здесь
    логируем, но НЕ пробрасываем как 500 — иначе клиент получит ошибку по уже принятой заявке.
    """
    try:
        conv = await chat_service.get_or_create_event_conversation(db, event)
        await chat_service.ensure_member(db, conv.id, participant.id)
        participant.events_attended += 1
        await db.commit()
        await chat_service.post_message(
            db, conv.id, f"{participant.name} присоединился", sender_id=None, is_system=True
        )
        await chat_service.post_message(
            db, conv.id, format_time(event), sender_id=None, is_system=True
        )
    except Exception:  # noqa: BLE001 - место уже выдано; побочные эффекты не должны валить запрос
        logger.exception("on_accept: побочные эффекты не выполнились после выдачи места")
        await db.rollback()
        return

    # push_service сам обрабатывает свои ошибки (fail-soft), пробрасывать наружу нечего.
    await push_service.send_push(
        db, participant.id, "Заявка принята",
        f"Вас приняли в «{event.title}». {format_time(event)}", {"event_id": str(event.id)},
    )


async def promote_waitlist(db: AsyncSession, event: Event) -> None:
    """Освободилось место → продвигаем следующих из листа ожидания (по времени отклика).

    Всё продвижение идёт ПОД блокировкой события (одна транзакция), а сами waitlist-строки
    берутся FOR UPDATE SKIP LOCKED — двойное продвижение и перебор мест исключены.
    """
    if event.status in ("cancelled", "finished", "closed"):
        return
    locked = await lock_event(db, event.id)
    if locked is None:
        return

    promoted: list[uuid.UUID] = []
    while locked.max_participants is None or await accepted_count(db, event.id) < locked.max_participants:
        nxt = (
            await db.execute(
                select(Participation)
                .where(Participation.event_id == event.id, Participation.status == "waitlisted")
                .order_by(Participation.created_at.asc())
                .with_for_update(skip_locked=True)
                .limit(1)
            )
        ).scalar_one_or_none()
        if nxt is None:
            break
        nxt.status = "accepted"
        nxt.decided_at = datetime.now(UTC)
        promoted.append(nxt.user_id)

    await refresh_capacity_status(db, locked)
    await db.commit()  # освобождает блокировку события и waitlist-строк

    for uid in promoted:
        participant = await db.get(User, uid)
        if participant is not None:
            await on_accept(db, locked, participant)
