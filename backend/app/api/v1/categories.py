"""Категории: канонический список плюс то, что люди вписали руками.

Отдаём популярные пользовательские категории вместе с каноническими, чтобы человек,
которому нужен «настольный теннис», выбрал уже существующую, а не завёл двадцатую
вариацию написания.
"""

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.core.categories import CANONICAL, is_canonical, title_of
from app.core.deps import CurrentUser, DbSession
from app.models.event import Event
from app.schemas.poster import CategoriesOut, CategoryItem

router = APIRouter(tags=["categories"])


@router.get("/categories", response_model=CategoriesOut)
async def list_categories(
    _: CurrentUser,
    db: DbSession,
    custom_limit: int = Query(20, ge=0, le=100),
) -> CategoriesOut:
    used = dict(
        (
            await db.execute(
                select(Event.category, func.count())
                .where(Event.category.is_not(None))
                .group_by(Event.category)
            )
        ).all()
    )

    items = [
        CategoryItem(key=key, title=title, is_canonical=True, usage=int(used.get(key, 0)))
        for key, title in CANONICAL.items()
    ]
    custom = sorted(
        ((k, n) for k, n in used.items() if not is_canonical(k)),
        key=lambda kv: -kv[1],
    )[:custom_limit]
    items += [
        CategoryItem(key=key, title=title_of(key), is_canonical=False, usage=int(n))
        for key, n in custom
    ]
    return CategoriesOut(items=items)
