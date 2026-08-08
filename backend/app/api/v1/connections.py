import uuid

from fastapi import APIRouter

from app.core.deps import CompleteUser, CurrentUser, DbSession
from app.core.exceptions import forbidden, not_found
from app.models.user import User
from app.schemas.connection import ConnectionItem, ConnectionsOut, DirectChatOut
from app.schemas.user import UserPublic
from app.services import connection_service, matching_service

router = APIRouter(tags=["connections"])


@router.get("/connections", response_model=ConnectionsOut)
async def my_connections(current_user: CurrentUser, db: DbSession) -> ConnectionsOut:
    """С кем я уже виделся.

    Не каталог людей: сюда попадают только те, с кем была общая завершённая встреча.
    Заблокированные в обе стороны из списка исключены.
    """
    blocked = await matching_service.blocked_user_ids(db, current_user.id)
    items = [
        ConnectionItem(
            user=UserPublic.from_model(c.user),
            meetings=c.meetings,
            last_met_at=c.last_met_at,
            last_event_title=c.last_event_title,
            i_follow=c.i_follow,
            follows_me=c.follows_me,
            mutual=c.mutual,
        )
        for c in await connection_service.list_connections(db, current_user.id)
        if c.user.id not in blocked
    ]
    return ConnectionsOut(items=items)


@router.post("/connections/{user_id}/chat", response_model=DirectChatOut)
async def open_direct_chat(
    user_id: uuid.UUID, current_user: CompleteUser, db: DbSession
) -> DirectChatOut:
    """Открыть личную переписку. Право даёт совместная встреча, а не кнопка.

    Идемпотентно: если беседа уже есть, вернётся она же.
    """
    if user_id == current_user.id:
        raise forbidden("Нельзя написать самому себе")
    if await db.get(User, user_id) is None:
        raise not_found("Пользователь не найден")

    blocked = await matching_service.blocked_user_ids(db, current_user.id)
    if user_id in blocked:
        raise forbidden("Действие недоступно")
    if not await connection_service.have_met(db, current_user.id, user_id):
        raise forbidden("Написать можно тем, с кем вы были на одной встрече")

    conv = await connection_service.get_or_create_direct(db, current_user.id, user_id)
    return DirectChatOut(conversation_id=conv.id)
