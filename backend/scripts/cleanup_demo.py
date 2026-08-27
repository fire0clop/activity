"""Уборка витринных данных после публикации в App Store.

Их заводили под скриншоты и проверку ревьюером: без них ревьюер увидит пустую
ленту. Поэтому запускать только после того, как приложение опубликовано.

Удаляет строго перечисленные аккаунты и всё, что к ним привязано (события,
отклики, сообщения, отзывы, желания уходят каскадом по внешним ключам).
Ничего чужого не трогает.

    docker exec -w /app -e PYTHONPATH=/app backend-api-1 \
        python scripts/cleanup_demo.py --yes
"""

import asyncio
import sys

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.user import User
from app.services.storage_service import get_storage

DEMO_PHONES = [
    "+79995551001",   # Аня Ковалёва
    "+79995551002",   # Марк Гринёв
    "+79995551003",   # Лена Соболь
    "+79995551004",   # Тимур Асланов
]
REVIEWER_NAME = "Apple Review"


async def main(confirmed: bool) -> None:
    async with SessionLocal() as db:
        users = (await db.execute(
            select(User).where(
                (User.phone.in_(DEMO_PHONES)) | (User.name == REVIEWER_NAME)
            )
        )).scalars().all()

        if not users:
            print("Витринных аккаунтов не найдено — уборка уже сделана.")
            return

        print("Будут удалены аккаунты и всё, что к ним привязано:")
        for u in users:
            print(f"  {u.phone or '—'}  {u.name}")

        if not confirmed:
            print("\nЗапуск без --yes: ничего не удалено.")
            return

        storage = get_storage()
        for u in users:
            for url in [u.avatar_url, *(u.photo_urls or [])]:
                if url:
                    await storage.delete(url)
            await db.delete(u)
        await db.commit()
        print(f"\nУдалено аккаунтов: {len(users)}. Связанные записи ушли каскадом.")


if __name__ == "__main__":
    asyncio.run(main("--yes" in sys.argv))
