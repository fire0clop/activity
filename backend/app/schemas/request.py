import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.user import UserBrief


class RequestCreateIn(BaseModel):
    """Заявить желание — дело пятнадцати секунд, поэтому обязательных полей минимум."""

    category: str = Field(..., min_length=1, max_length=60)
    text: str | None = Field(default=None, max_length=500)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    area: str | None = Field(default=None, max_length=200)
    radius_km: float = Field(default=10, gt=0, le=100)
    when_window: str = Field(default="week", pattern="^(today|tomorrow|weekend|week)$")


class RequestItem(BaseModel):
    id: uuid.UUID
    author: UserBrief
    category: str
    text: str | None
    area: str | None
    radius_km: float
    when_window: str
    status: str
    supports_count: int
    i_support: bool
    is_mine: bool
    distance_km: float | None
    latitude: float
    longitude: float
    fulfilled_event_id: uuid.UUID | None
    created_at: datetime
    expires_at: datetime


class RequestsOut(BaseModel):
    items: list[RequestItem]
    next_cursor: str | None


class SupportOut(BaseModel):
    supports_count: int
    i_support: bool
