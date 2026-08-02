import uuid
from datetime import datetime

from pydantic import BaseModel, Field, model_validator

from app.schemas.user import UserPublic


class ReviewCreateIn(BaseModel):
    target_id: uuid.UUID
    rating: int | None = Field(default=None, ge=1, le=5)
    comment: str | None = None
    attended: bool = True

    @model_validator(mode="after")
    def check_rating_matches_attendance(self) -> "ReviewCreateIn":
        """Оценка и явка связаны: пришёл — ставим звёзды, не пришёл — оценивать нечего."""
        if self.attended and self.rating is None:
            raise ValueError("Поставьте оценку от 1 до 5")
        if not self.attended:
            self.rating = None
        return self


class ReviewOut(BaseModel):
    id: uuid.UUID
    event_id: uuid.UUID
    author: UserPublic
    target_id: uuid.UUID
    rating: int | None
    comment: str | None
    attended: bool
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
