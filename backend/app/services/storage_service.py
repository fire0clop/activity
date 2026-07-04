import asyncio
import io
import uuid

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError
from fastapi import UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.config import settings
from app.core.exceptions import AppError

_EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}
_PIL_FORMAT = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}


def _process_image(file: UploadFile, data: bytes) -> tuple[bytes, str]:
    """Валидирует и нормализует изображение: проверка типа/размера, декодирование,
    ресайз по большей стороне, перекодирование (убирает EXIF/потенциальные полезные нагрузки).

    Возвращает (bytes, ext). Бросает AppError при невалидном файле.
    """
    if file.content_type not in settings.allowed_image_types_set:
        raise AppError("validation_error", f"Недопустимый тип файла: {file.content_type}", 422)
    if len(data) > settings.max_upload_mb * 1024 * 1024:
        raise AppError("validation_error", "Файл слишком большой", 422)

    try:
        img = Image.open(io.BytesIO(data))
        img.verify()  # проверка целостности
        img = Image.open(io.BytesIO(data))  # повторно, т.к. verify «расходует» объект
    except (UnidentifiedImageError, OSError):
        raise AppError("validation_error", "Файл не является корректным изображением", 422) from None

    # Применяем поворот из EXIF к самим пикселям и убираем метку, чтобы фото
    # отображалось одинаково везде (иначе вертикальные снимки «переворачивались»).
    img = ImageOps.exif_transpose(img)

    fmt = _PIL_FORMAT.get(file.content_type, "JPEG")
    if fmt == "JPEG" and img.mode in ("RGBA", "P"):
        img = img.convert("RGB")

    max_dim = settings.image_max_dimension
    if max(img.size) > max_dim:
        img.thumbnail((max_dim, max_dim))

    out = io.BytesIO()
    save_kwargs = {"format": fmt}
    if fmt in ("JPEG", "WEBP"):
        save_kwargs["quality"] = 85
    img.save(out, **save_kwargs)
    return out.getvalue(), _EXT.get(file.content_type or "", ".bin")


class StorageService:
    """Абстракция хранилища медиа. Реализации: LocalStorage и S3Storage.

    Переключение через STORAGE_BACKEND — вызовы save()/delete() не меняются.
    """

    async def save(self, file: UploadFile, subdir: str) -> str:
        raise NotImplementedError

    async def delete(self, public_url: str) -> None:
        raise NotImplementedError


class LocalStorage(StorageService):
    async def save(self, file: UploadFile, subdir: str) -> str:
        from pathlib import Path

        data = await file.read()
        processed, ext = _process_image(file, data)

        name = f"{uuid.uuid4().hex}{ext}"
        rel_path = f"{subdir}/{name}"
        dest_dir = Path(settings.media_root) / subdir
        dest_dir.mkdir(parents=True, exist_ok=True)
        (dest_dir / name).write_bytes(processed)
        return f"{settings.media_public_url.rstrip('/')}/{rel_path}"

    async def delete(self, public_url: str) -> None:
        from pathlib import Path

        prefix = settings.media_public_url.rstrip("/") + "/"
        if not public_url.startswith(prefix):
            return
        target = Path(settings.media_root) / public_url[len(prefix):]
        if target.is_file():
            target.unlink(missing_ok=True)


class S3Storage(StorageService):
    """S3-совместимое хранилище (AWS S3 или MinIO). Используется при масштабировании,
    когда инстансов несколько и локальный диск не подходит."""

    def __init__(self) -> None:
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint or None,
            region_name=settings.s3_region,
            aws_access_key_id=settings.s3_access_key or None,
            aws_secret_access_key=settings.s3_secret_key or None,
            config=BotoConfig(signature_version="s3v4"),
        )

    async def ensure_bucket(self) -> None:
        try:
            await asyncio.to_thread(self._client.head_bucket, Bucket=settings.s3_bucket)
        except ClientError:
            # бакета нет (404) или нет прав HEAD — пробуем создать; иные ошибки всплывут
            await asyncio.to_thread(self._client.create_bucket, Bucket=settings.s3_bucket)

    async def save(self, file: UploadFile, subdir: str) -> str:
        data = await file.read()
        processed, ext = _process_image(file, data)
        key = f"{subdir}/{uuid.uuid4().hex}{ext}"
        await asyncio.to_thread(
            self._client.put_object,
            Bucket=settings.s3_bucket,
            Key=key,
            Body=processed,
            ContentType=file.content_type,
            CacheControl="public, max-age=31536000",
        )
        return f"{settings.s3_public_url.rstrip('/')}/{key}"

    async def delete(self, public_url: str) -> None:
        prefix = settings.s3_public_url.rstrip("/") + "/"
        if not public_url.startswith(prefix):
            return
        key = public_url[len(prefix):]
        await asyncio.to_thread(self._client.delete_object, Bucket=settings.s3_bucket, Key=key)


_instance: StorageService | None = None


def get_storage() -> StorageService:
    global _instance
    if _instance is not None:
        return _instance
    if settings.storage_backend == "local":
        _instance = LocalStorage()
    elif settings.storage_backend == "s3":
        s3 = S3Storage()
        _instance = s3
    else:
        raise NotImplementedError(f"Storage backend '{settings.storage_backend}' not implemented")
    return _instance
