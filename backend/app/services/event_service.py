import uuid

from app.models.event import Event
from app.models.user import User
from app.schemas.event import EventDetail, EventListItem, MyParticipation
from app.schemas.user import UserBrief


def _time_disclosed(viewer_id: uuid.UUID | None, organizer_id: uuid.UUID, my_status: str | None) -> bool:
    """Точное время видно только организатору и подтверждённым участникам (ROADMAP §4)."""
    if viewer_id is not None and viewer_id == organizer_id:
        return True
    return my_status == "accepted"


def build_list_item(
    event: Event,
    organizer: User,
    *,
    viewer_id: uuid.UUID | None,
    my_status: str | None,
    participants_current: int,
    distance_km: float | None,
) -> EventListItem:
    disclosed = _time_disclosed(viewer_id, event.organizer_id, my_status)
    return EventListItem(
        id=event.id,
        title=event.title,
        category=event.category,
        day=event.starts_at.date(),
        starts_at=event.starts_at if disclosed else None,
        ends_at=event.ends_at if disclosed else None,
        time_disclosed=disclosed,
        latitude=event.latitude,
        longitude=event.longitude,
        address=event.address,
        map_url=event.map_url,
        cover_url=event.cover_url,
        photo_urls=list(event.photo_urls or []),
        participants_current=participants_current,
        participants_max=event.max_participants,
        price=float(event.price) if event.price is not None else None,
        price_split=event.price_split,
        status=event.status,
        distance_km=distance_km,
        organizer=UserBrief(
            id=organizer.id,
            name=organizer.name,
            avatar_url=organizer.avatar_url,
            rating_avg=float(organizer.rating_avg),
        ),
    )


def build_detail(
    event: Event,
    organizer: User,
    *,
    viewer_id: uuid.UUID,
    my_status: str | None,
    participants_current: int,
    distance_km: float | None,
    conversation_id: uuid.UUID | None,
    accepted: list[UserBrief] | None = None,
) -> EventDetail:
    base = build_list_item(
        event,
        organizer,
        viewer_id=viewer_id,
        my_status=my_status,
        participants_current=participants_current,
        distance_km=distance_km,
    )
    return EventDetail(
        **base.model_dump(),
        description=event.description,
        min_participants=event.min_participants,
        auto_accept=event.auto_accept,
        created_at=event.created_at,
        accepted_participants=accepted or [],
        my_participation=MyParticipation(status=my_status) if my_status else None,
        is_organizer=event.organizer_id == viewer_id,
        chat_available=conversation_id is not None,
        conversation_id=conversation_id,
    )
