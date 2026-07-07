import uuid

from fastapi import APIRouter, File, Query, UploadFile
from sqlalchemy import select

from app.core.deps import CurrentUser, DbSession
from app.core.exceptions import AppError, not_found
from app.models.subscription import Subscription
from app.models.user import User
from app.schemas.event import PhotosOut
from app.schemas.user import UpdateProfileIn, UserPrivate, UserPublic
from app.services.storage_service import get_storage

router = APIRouter(prefix="/users", tags=["users"])

MAX_USER_PHOTOS = 5


@router.get("/me", response_model=UserPrivate)
async def get_me(current_user: CurrentUser) -> UserPrivate:
    return UserPrivate.from_model(current_user)


@router.patch("/me", response_model=UserPrivate)
async def update_me(body: UpdateProfileIn, current_user: CurrentUser, db: DbSession) -> UserPrivate:
    data = body.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(current_user, field, value)
    await db.commit()
    await db.refresh(current_user)
    return UserPrivate.from_model(current_user)


@router.post("/me/avatar")
async def upload_avatar(
    current_user: CurrentUser, db: DbSession, file: UploadFile = File(...)
) -> dict:
    storage = get_storage()
    url = await storage.save(file, subdir="avatars")
    current_user.avatar_url = url
    await db.commit()
    return {"avatar_url": url}


@router.post("/me/photos", response_model=PhotosOut)
async def upload_photo(current_user: CurrentUser, db: DbSession, file: UploadFile = File(...)) -> PhotosOut:
    photos = list(current_user.photo_urls or [])
    if len(photos) >= MAX_USER_PHOTOS:
        raise AppError("validation_error", f"Не больше {MAX_USER_PHOTOS} фото", 422)
    url = await get_storage().save(file, subdir="user_photos")
    photos.append(url)
    current_user.photo_urls = photos
    await db.commit()
    return PhotosOut(photo_urls=photos)


@router.delete("/me/photos", response_model=PhotosOut)
async def delete_photo(current_user: CurrentUser, db: DbSession, url: str = Query(...)) -> PhotosOut:
    existing = list(current_user.photo_urls or [])
    photos = [p for p in existing if p != url]
    # Удаляем файл из хранилища ТОЛЬКО если url реально принадлежал пользователю,
    # иначе можно было бы стереть чужой файл, зная его публичный URL.
    if len(photos) == len(existing):
        raise not_found("Фото не найдено")
    current_user.photo_urls = photos
    await db.commit()
    await get_storage().delete(url)
    return PhotosOut(photo_urls=photos)


@router.delete("/me", status_code=204)
async def delete_me(current_user: CurrentUser, db: DbSession) -> None:
    """Удаление аккаунта (App Store Guideline 5.1.1(v)).

    Медиа чистим из хранилища, затем физически удаляем пользователя: связанные события,
    участия, отзывы, устройства и refresh-токены уходят каскадом (FK ondelete=CASCADE),
    а отправленные сообщения обезличиваются (sender_id → NULL).
    """
    storage = get_storage()
    for url in [current_user.avatar_url, *(current_user.photo_urls or [])]:
        if url:
            await storage.delete(url)
    await db.delete(current_user)
    await db.commit()


@router.get("/{user_id}", response_model=UserPublic)
async def get_user(user_id: uuid.UUID, _: CurrentUser, db: DbSession) -> UserPublic:
    user = await db.get(User, user_id)
    if user is None:
        raise not_found("Пользователь не найден")
    return UserPublic.from_model(user)


async def _find_follow(db: DbSession, follower_id: uuid.UUID, organizer_id: uuid.UUID) -> Subscription | None:
    return (
        await db.execute(
            select(Subscription).where(
                Subscription.user_id == follower_id,
                Subscription.target_organizer_id == organizer_id,
            )
        )
    ).scalar_one_or_none()


@router.post("/{user_id}/follow", status_code=204)
async def follow_user(user_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> None:
    """Подписаться на организатора — пуш о любом его новом событии."""
    if user_id == current_user.id:
        raise AppError("validation_error", "Нельзя подписаться на себя", 422)
    if await db.get(User, user_id) is None:
        raise not_found("Пользователь не найден")
    if await _find_follow(db, current_user.id, user_id) is None:  # идемпотентно
        db.add(Subscription(user_id=current_user.id, target_organizer_id=user_id))
        await db.commit()


@router.delete("/{user_id}/follow", status_code=204)
async def unfollow_user(user_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> None:
    sub = await _find_follow(db, current_user.id, user_id)
    if sub is not None:
        await db.delete(sub)
        await db.commit()


@router.get("/{user_id}/follow-status")
async def follow_status(user_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> dict:
    return {"following": await _find_follow(db, current_user.id, user_id) is not None}
