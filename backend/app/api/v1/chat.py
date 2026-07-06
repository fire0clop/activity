import logging
import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select, update

from app.core.config import settings
from app.core.security import decode_token
from app.db.session import SessionLocal
from app.models.conversation import Conversation, ConversationMember
from app.models.message import Message
from app.services import chat_service
from app.services.rate_limit import allow_user_action
from app.ws.manager import manager

router = APIRouter(tags=["chat-ws"])

logger = logging.getLogger("chat")

HISTORY_LIMIT = 50


async def _send_history(websocket: WebSocket, conversation_id: uuid.UUID) -> None:
    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(Message)
                .where(Message.conversation_id == conversation_id)
                .order_by(Message.created_at.desc())
                .limit(HISTORY_LIMIT)
            )
        ).scalars().all()
        rows.reverse()
        messages = [
            (await chat_service.serialize_message(db, m)).model_dump(mode="json") for m in rows
        ]
    await websocket.send_json({"type": "history", "messages": messages})


async def _broadcast_presence(conversation_id: uuid.UUID) -> None:
    await manager.broadcast(
        conversation_id,
        {"type": "presence", "online_user_ids": await manager.online_user_ids(conversation_id)},
    )


def _extract_ws_token(websocket: WebSocket, query_token: str) -> tuple[str, str | None]:
    """Достаёт access-токен. Предпочитаем Sec-WebSocket-Protocol (не попадает в логи
    reverse-proxy, в отличие от ?token=...). Формат подпротоколов: "bearer, <jwt>".

    Возвращает (token, subprotocol_to_echo). query-fallback оставлен для тестов/дев-инструментов.
    """
    proto = websocket.headers.get("sec-websocket-protocol")
    if proto:
        parts = [p.strip() for p in proto.split(",")]
        if len(parts) >= 2 and parts[0] == "bearer":
            return parts[1], "bearer"
    return query_token, None


@router.websocket("/ws/chat/{conversation_id}")
async def chat_ws(websocket: WebSocket, conversation_id: uuid.UUID, token: str = "") -> None:
    token, subprotocol = _extract_ws_token(websocket, token)
    try:
        payload = decode_token(token, expected_type="access")
        user_id = uuid.UUID(payload["sub"])
    except Exception:  # noqa: BLE001
        await websocket.close(code=4401)
        return

    async with SessionLocal() as db:
        conv = await db.get(Conversation, conversation_id)
        if conv is None or not await chat_service.is_member(db, conversation_id, user_id):
            await websocket.close(code=4403)
            return

    await manager.connect(conversation_id, user_id, websocket, subprotocol=subprotocol)
    await _send_history(websocket, conversation_id)
    await _broadcast_presence(conversation_id)

    try:
        while True:
            data = await websocket.receive_json()
            mtype = data.get("type")
            if mtype == "message":
                text = (data.get("text") or "").strip()
                if not text:
                    continue
                if not await allow_user_action(
                    websocket.app.state.redis, user_id, "chat_message",
                    settings.user_rl_messages_per_min, 60,
                ):
                    await websocket.send_json(
                        {"type": "error", "code": "rate_limited",
                         "detail": "Слишком много сообщений, подождите минуту"}
                    )
                    continue
                async with SessionLocal() as db2:
                    # Перечитываем архивный статус: беседа могла быть архивирована
                    # свипером уже ПОСЛЕ подключения этого сокета.
                    conv = await db2.get(Conversation, conversation_id)
                    if conv is None or conv.is_archived:
                        await websocket.send_json(
                            {"type": "error", "code": "forbidden", "detail": "Беседа архивирована"}
                        )
                        continue
                    await chat_service.post_message(db2, conversation_id, text, sender_id=user_id)
            elif mtype == "typing":
                await manager.broadcast(
                    conversation_id, {"type": "typing", "user_id": str(user_id)}
                )
            elif mtype == "read":
                last_id = data.get("last_message_id")
                if last_id:
                    async with SessionLocal() as db3:
                        await db3.execute(
                            update(ConversationMember)
                            .where(
                                ConversationMember.conversation_id == conversation_id,
                                ConversationMember.user_id == user_id,
                            )
                            .values(last_read_message_id=uuid.UUID(last_id))
                        )
                        await db3.commit()
    except WebSocketDisconnect:
        await manager.disconnect(conversation_id, user_id, websocket)
        await _broadcast_presence(conversation_id)
    except Exception:  # noqa: BLE001
        logger.exception("chat ws: unexpected error, closing connection")
        await manager.disconnect(conversation_id, user_id, websocket)
        await _broadcast_presence(conversation_id)
