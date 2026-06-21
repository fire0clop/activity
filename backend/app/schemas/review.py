import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.user import UserPublic


class ReviewCreateIn(BaseModel):
    target_id: uuid.UUID
    rating: int = Field(..., ge=1, le=5)
    comment: str | None = None


class ReviewOut(BaseModel):
    id: uuid.UUID
    event_id: uuid.UUID
    author: UserPublic
    target_id: uuid.UUID
    rating: int
    comment: str | None
    created_at: datetime


class ReviewsOut(BaseModel):
    items: list[ReviewOut]
    next_cursor: str | None


class ReportCreateIn(BaseModel):
    target_user_id: uuid.UUID | None = None
    target_event_id: uuid.UUID | None = None
    reason: str = Field(..., pattern="^(spam|inappropriate|safety|other)$")
    comment: str | None = None


class ReportOut(BaseModel):
    id: uuid.UUID
    status: str


class DeviceIn(BaseModel):
    token: str
    platform: str = Field(..., pattern="^(ios|android)$")
