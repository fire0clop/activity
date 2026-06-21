import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.user import User


class UserPublic(BaseModel):
    id: uuid.UUID
    name: str | None
    bio: str | None
    avatar_url: str | None
    photo_urls: list[str]
    gender: str
    age: int | None
    rating_avg: float
    rating_count: int
    events_created: int
    events_attended: int
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
            rating_avg=float(u.rating_avg),
            rating_count=u.rating_count,
            events_created=u.events_created,
            events_attended=u.events_attended,
            member_since=u.created_at,
        )


class UserPrivate(UserPublic):
    phone: str
    is_phone_verified: bool
    birth_date: date | None
    profile_completed: bool

    @classmethod
    def from_model(cls, u: User) -> "UserPrivate":
        return cls(
            **UserPublic.from_model(u).model_dump(),
            phone=u.phone,
            is_phone_verified=u.is_phone_verified,
            birth_date=u.birth_date,
            profile_completed=u.profile_completed,
        )


class UserBrief(BaseModel):
    """Краткий профиль организатора внутри карточки события."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str | None
    avatar_url: str | None
    rating_avg: float


class UpdateProfileIn(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    bio: str | None = None
    birth_date: date | None = None
    gender: str | None = Field(default=None, pattern="^(male|female|other|unspecified)$")
