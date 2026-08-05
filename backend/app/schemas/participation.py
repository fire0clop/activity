import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.event import EventListItem
from app.schemas.user import UserPublic


class JoinOut(BaseModel):
    status: str


class MyApplicationItem(BaseModel):
    """Строка экрана «Мои заявки»: статус отклика вместе с самим событием."""

    participation_id: uuid.UUID
    status: str
    created_at: datetime
    event: EventListItem


class MyApplicationsOut(BaseModel):
    items: list[MyApplicationItem]


class ParticipantItem(BaseModel):
    participation_id: uuid.UUID
    user: UserPublic
    status: str
    created_at: datetime


class ParticipantsOut(BaseModel):
    items: list[ParticipantItem]
