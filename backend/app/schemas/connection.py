import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.user import UserPublic


class ConnectionItem(BaseModel):
    """Знакомый: с кем виделись, сколько раз и когда в последний раз."""

    user: UserPublic
    meetings: int
    last_met_at: datetime
    last_event_title: str
    i_follow: bool
    follows_me: bool
    mutual: bool


class ConnectionsOut(BaseModel):
    items: list[ConnectionItem]


class DirectChatOut(BaseModel):
    conversation_id: uuid.UUID


class InviteIn(BaseModel):
    user_ids: list[uuid.UUID]


class InviteOut(BaseModel):
    invited: int
    skipped: int
