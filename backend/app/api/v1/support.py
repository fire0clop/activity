"""Приём обращений из формы поддержки.

Адрес поддержки обязателен для публикации в App Store, а открытую почту на
странице держать не хотим — её сразу находят спам-боты. Поэтому форма пишет
сюда, а обращения читаются из базы.
"""

import logging

from fastapi import APIRouter, Request, status

from app.core.deps import DbSession, RedisDep
from app.core.exceptions import AppError
from app.models.support import SupportTicket
from app.schemas.support import SupportTicketIn

logger = logging.getLogger("support")
router = APIRouter(prefix="/support", tags=["support"])

MAX_PER_HOUR = 5


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
async def create_ticket(
    body: SupportTicketIn, request: Request, db: DbSession, redis: RedisDep
) -> None:
    # Форма анонимная, поэтому считаем по адресу: иначе её зальют ботами.
    ip = request.client.host if request.client else "unknown"
    key = f"support:{ip}"
    try:
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, 3600)
        if count > MAX_PER_HOUR:
            raise AppError("rate_limited", "Слишком много обращений, попробуйте позже", 429,
                           headers={"Retry-After": "3600"})
    except AppError:
        raise
    except Exception:  # noqa: BLE001 — Redis лежит: обращение важнее лимита
        logger.warning("support: Redis недоступен, лимит пропущен", exc_info=True)

    ticket = SupportTicket(contact=body.contact.strip(), message=body.message.strip())
    db.add(ticket)
    await db.commit()
    # Дублируем в лог: так обращение видно сразу, без похода в базу.
    logger.info("обращение в поддержку от %s: %s", ticket.contact, ticket.message[:200])
