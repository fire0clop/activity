import asyncio
import json
import logging
import uuid
from collections import defaultdict

from fastapi import WebSocket
from redis.asyncio import Redis

logger = logging.getLogger("ws")

_CHANNEL = "ws:events"


def _online_key(conversation_id: uuid.UUID) -> str:
    return f"ws:online:{conversation_id}"


class ConnectionManager:
    """WebSocket-пул с fan-out через Redis pub/sub (масштабирование на N инстансов).

    broadcast() публикует в общий Redis-канал; слушатель на КАЖДОМ инстансе доставляет
    сообщение своим локальным сокетам. Presence хранится в Redis-сете на беседу,
    поэтому онлайн виден между инстансами.
    """

    def __init__(self) -> None:
        self._rooms: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)
        # локальный счётчик соединений на (conversation, user) — для корректного presence
        self._local_user_conns: dict[tuple[uuid.UUID, uuid.UUID], int] = defaultdict(int)
        self._redis: Redis | None = None
        self._listener_task: asyncio.Task | None = None

    async def start(self, redis: Redis) -> None:
        self._redis = redis
        self._pubsub = redis.pubsub()
        await self._pubsub.subscribe(_CHANNEL)
        self._listener_task = asyncio.create_task(self._listen())
        logger.info("ws manager: redis pub/sub listener started")

    async def stop(self) -> None:
        if self._listener_task:
            self._listener_task.cancel()
        if self._redis is not None:
            try:
                await self._pubsub.unsubscribe(_CHANNEL)
                await self._pubsub.aclose()
            except Exception:  # noqa: BLE001
                pass

    async def _listen(self) -> None:
        try:
            async for msg in self._pubsub.listen():
                if msg.get("type") != "message":
                    continue
                try:
                    data = json.loads(msg["data"])
                    cid = uuid.UUID(data["conversation_id"])
                    await self._deliver_local(cid, data["payload"])
                except Exception:  # noqa: BLE001
                    logger.exception("ws listener: failed to deliver message")
        except asyncio.CancelledError:
            pass

    async def _deliver_local(self, conversation_id: uuid.UUID, payload: dict) -> None:
        dead: list[WebSocket] = []
        for ws in list(self._rooms.get(conversation_id, set())):
            try:
                await ws.send_json(payload)
            except Exception:  # noqa: BLE001
                dead.append(ws)
        for ws in dead:
            self._rooms.get(conversation_id, set()).discard(ws)

    async def connect(self, conversation_id: uuid.UUID, user_id: uuid.UUID, ws: WebSocket) -> None:
        await ws.accept()
        self._rooms[conversation_id].add(ws)
        self._local_user_conns[(conversation_id, user_id)] += 1
        if self._redis is not None:
            await self._redis.sadd(_online_key(conversation_id), str(user_id))

    async def disconnect(self, conversation_id: uuid.UUID, user_id: uuid.UUID, ws: WebSocket) -> None:
        self._rooms.get(conversation_id, set()).discard(ws)
        key = (conversation_id, user_id)
        self._local_user_conns[key] = max(0, self._local_user_conns[key] - 1)
        if self._local_user_conns[key] == 0:
            self._local_user_conns.pop(key, None)
            if self._redis is not None:
                await self._redis.srem(_online_key(conversation_id), str(user_id))
        if conversation_id in self._rooms and not self._rooms[conversation_id]:
            del self._rooms[conversation_id]

    async def broadcast(self, conversation_id: uuid.UUID, payload: dict) -> None:
        if self._redis is not None:
            await self._redis.publish(
                _CHANNEL,
                json.dumps({"conversation_id": str(conversation_id), "payload": payload}),
            )
        else:  # фолбэк без Redis (например, в части тестов)
            await self._deliver_local(conversation_id, payload)

    async def online_user_ids(self, conversation_id: uuid.UUID) -> list[str]:
        if self._redis is None:
            return []
        members = await self._redis.smembers(_online_key(conversation_id))
        return [m.decode() if isinstance(m, bytes) else m for m in members]


manager = ConnectionManager()
