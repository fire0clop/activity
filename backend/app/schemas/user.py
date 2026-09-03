import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.user import User


def rating_or_none(u: User) -> float | None:
    """Рейтинг существует только с первого отзыва.

    Ноль наружу не отдаём никогда: «0.0» читается как худшая возможная оценка,
    хотя означает лишь отсутствие истории. Клиент по null показывает «новичок».
    """
    return float(u.rating_avg) if u.rating_count > 0 else None


class UserPublic(BaseModel):
    id: uuid.UUID
    name: str | None
    bio: str | None
    avatar_url: str | None
    photo_urls: list[str]
    gender: str
    age: int | None
    rating_avg: float | None
    rating_count: int
    events_created: int
    events_attended: int
    no_show_count: int
    member_since: datetime

    @classmethod
    def from_model(cls, u: User) -> "UserPublic":
        return cls(
            id=u.id,
            name=u.name,
            bio=u.bio,
            avatar_url=u.avatar_url,
            photo_urls=list(u.photo_urls or []),
            gender=u.gender,
            age=u.age,
            rating_avg=rating_or_none(u),
            rating_count=u.rating_count,
            events_created=u.events_created,
            events_attended=u.events_attended,
            no_show_count=u.no_show_count,
            member_since=u.created_at,
        )


class UserPrivate(UserPublic):
    phone: str | None
    is_phone_verified: bool
    birth_date: date | None
    profile_completed: bool
    tos_accepted_version: str | None = None

    @classmethod
    def from_model(cls, u: User) -> "UserPrivate":
        return cls(
            **UserPublic.from_model(u).model_dump(),
            phone=u.phone,
            is_phone_verified=u.is_phone_verified,
            birth_date=u.birth_date,
            profile_completed=u.profile_completed,
            tos_accepted_version=u.tos_accepted_version,
        )


class UserBrief(BaseModel):
    """Краткий профиль организатора внутри карточки события."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str | None
    avatar_url: str | None
    rating_avg: float | None  # null, пока нет ни одного отзыва
    rating_count: int = 0

    @classmethod
    def from_model(cls, u: User) -> "UserBrief":
        return cls(
            id=u.id,
            name=u.name,
            avatar_url=u.avatar_url,
            rating_avg=rating_or_none(u),
            rating_count=u.rating_count,
        )


class UpdateProfileIn(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    bio: str | None = None
    # Версия правил сообщества, с которой человек согласился на экране входа.
    tos_accepted_version: str | None = Field(default=None, max_length=20)
    birth_date: date | None = None
    gender: str | None = Field(default=None, pattern="^(male|female|other|unspecified)$")
