import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.user import UserPublic


class JoinOut(BaseModel):
    status: str


class ParticipantItem(BaseModel):
    participation_id: uuid.UUID
    user: UserPublic
    status: str
    created_at: datetime


class ParticipantsOut(BaseModel):
    items: list[ParticipantItem]
