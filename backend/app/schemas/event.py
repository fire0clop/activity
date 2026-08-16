import uuid
from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.categories import normalize
from app.schemas.user import UserBrief


class EventCreateIn(BaseModel):
    title: str = Field(..., max_length=200)
    description: str | None = None
    category: str | None = None
    starts_at: datetime
    ends_at: datetime | None = None
    # Координаты можно задать напрямую ИЛИ через ссылку на точку Яндекс.Карт (map_url).
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    map_url: str | None = None
    address: str | None = None
    min_participants: int = Field(default=2, ge=1)
    # None = без ограничения по числу участников
    max_participants: int | None = Field(default=None, ge=2)
    price: float | None = None
    price_split: str = Field(default="free", pattern="^(free|per_person|shared)$")
    auto_accept: bool = False
    recurrence: str = Field(default="none", pattern="^(none|weekly)$")
    # Событие собрано по чужому «хочу»: закрываем запрос и зовём тех, кто его ждал.
    from_request_id: uuid.UUID | None = None
    # Событие собрано по карточке афиши: «идём вместе на этот концерт».
    poster_id: uuid.UUID | None = None

    @field_validator("category")
    @classmethod
    def _norm_category(cls, v: str | None) -> str | None:
        return normalize(v)

    @model_validator(mode="after")
    def _check(self) -> "EventCreateIn":
        if self.max_participants is not None and self.max_participants < self.min_participants:
            raise ValueError("max_participants must be >= min_participants")
        if self.ends_at and self.ends_at < self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        has_coords = self.latitude is not None and self.longitude is not None
        if not has_coords and not self.map_url:
            raise ValueError("provide latitude+longitude or map_url")
        check_price(self.price_split, self.price)
        return self


def check_price(split: str | None, price: float | None) -> None:
    """Сумма и способ оплаты обязаны сходиться.

    «Бесплатно» с ценой и «с каждого» без цены — обещания, которые нечем выполнить:
    участник увидит одно, а на месте окажется другое.
    """
    if split is None:
        return
    if split == "free":
        if price:
            raise ValueError("для бесплатного события цена не указывается")
    elif not price or price <= 0:
        raise ValueError("укажите сумму — она нужна для выбранного способа оплаты")


class EventUpdateIn(BaseModel):
    title: str | None = Field(default=None, max_length=200)
    description: str | None = None
    category: str | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    address: str | None = None
    map_url: str | None = None
    min_participants: int | None = Field(default=None, ge=1)
    max_participants: int | None = Field(default=None, ge=2)
    price: float | None = None
    price_split: str | None = Field(default=None, pattern="^(free|per_person|shared)$")
    auto_accept: bool | None = None

    @field_validator("category")
    @classmethod
    def _norm_category(cls, v: str | None) -> str | None:
        return normalize(v)

    @model_validator(mode="after")
    def _check(self) -> "EventUpdateIn":
        # Проверяем только когда способ оплаты меняют: частичное обновление не обязано
        # присылать оба поля разом.
        if self.price_split is not None:
            check_price(self.price_split, self.price)
        return self


class MyParticipation(BaseModel):
    status: str


class EventListItem(BaseModel):
    id: uuid.UUID
    title: str
    category: str | None
    day: date
    starts_at: datetime | None        # null, если время скрыто (не организатор/не accepted)
    ends_at: datetime | None
    time_disclosed: bool
    latitude: float
    longitude: float
    address: str | None
    map_url: str | None
    cover_url: str | None
    photo_urls: list[str]               # галерея — основа карточки в ленте
    participants_current: int
    participants_max: int | None        # null = без ограничения
    price: float | None
    price_split: str
    status: str
    distance_km: float | None
    poster_id: uuid.UUID | None = None
    organizer: UserBrief


class EventDetail(EventListItem):
    description: str | None
    min_participants: int
    auto_accept: bool
    created_at: datetime
    accepted_participants: list[UserBrief] = []   # превью принятых (видно всем)
    my_participation: MyParticipation | None
    is_organizer: bool
    chat_available: bool
    conversation_id: uuid.UUID | None


class PhotosOut(BaseModel):
    photo_urls: list[str]


class EventListOut(BaseModel):
    items: list[EventListItem]
    next_cursor: str | None
    # Холодный старт: если в запрошенном радиусе пусто — ближайший радиус с событиями.
    suggested_radius_km: float | None = None
    suggested_count: int | None = None
