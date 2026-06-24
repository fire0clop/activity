import uuid

from fastapi import APIRouter, File, Query, UploadFile

from app.core.deps import CurrentUser, DbSession
from app.core.exceptions import AppError, not_found
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
    photos = [p for p in (current_user.photo_urls or []) if p != url]
    current_user.photo_urls = photos
    await db.commit()
    await get_storage().delete(url)
    return PhotosOut(photo_urls=photos)


@router.get("/{user_id}", response_model=UserPublic)
async def get_user(user_id: uuid.UUID, _: CurrentUser, db: DbSession) -> UserPublic:
    user = await db.get(User, user_id)
    if user is None:
        raise not_found("Пользователь не найден")
    return UserPublic.from_model(user)
