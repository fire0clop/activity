import uuid
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import AppError, profile_incomplete, unauthorized
from app.core.security import decode_token
from app.db.session import get_session
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)

DbSession = Annotated[AsyncSession, Depends(get_session)]


def get_redis(request: Request) -> Redis:
    return request.app.state.redis


RedisDep = Annotated[Redis, Depends(get_redis)]


async def get_current_user(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    if credentials is None:
        raise unauthorized("Требуется заголовок Authorization")
    payload = decode_token(credentials.credentials, expected_type="access")
    user_id = uuid.UUID(payload["sub"])
    user = await db.get(User, user_id)
    if user is None:
        raise unauthorized("Пользователь не найден")
    if user.is_banned:
        raise AppError("account_banned", "Аккаунт заблокирован", 403)
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


async def require_complete_profile(current_user: CurrentUser) -> User:
    """Гейт для действий: создать/откликнуться/писать — только с полным профилем (ROADMAP §4)."""
    if not current_user.profile_completed:
        raise profile_incomplete()
    return current_user


CompleteUser = Annotated[User, Depends(require_complete_profile)]
