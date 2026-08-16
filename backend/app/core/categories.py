"""Категории занятий.

Ключи из канонического списка получают на клиенте иконку и цвет; всё остальное —
это своя категория, которую человек вписал руками. Она хранится как обычный текст
и показывается как есть, поэтому список ниже можно расширять, не ломая старые данные.

Нормализация нужна против расщепления: «Йога», «йога » и «ЙОГА» обязаны быть одним
и тем же, иначе фильтр по категории перестанет что-либо значить.
"""

CANONICAL: dict[str, str] = {
    "walk": "Прогулка",
    "sport": "Спорт",
    "watersport": "Вода",
    "bike": "Велосипед",
    "gym": "Зал",
    "yoga": "Йога",
    "ski": "Лыжи и сноуборд",
    "fishing": "Рыбалка",
    "music": "Музыка",
    "concert": "Концерт",
    "party": "Вечеринка",
    "dance": "Танцы",
    "boardgames": "Настолки",
    "videogames": "Видеоигры",
    "quiz": "Квиз",
    "food": "Еда",
    "bar": "Бар",
    "coffee": "Кофе",
    "cinema": "Кино",
    "theatre": "Театр",
    "museum": "Музей",
    "exhibition": "Выставка",
    "festival": "Фестиваль",
    "photo": "Фотопрогулка",
    "travel": "Поездка",
    "roadtrip": "Автопутешествие",
    "pets": "С питомцами",
    "volunteer": "Волонтёрство",
    "study": "Учёба",
    "other": "Другое",
}

MAX_CATEGORY_LEN = 40

# Обратный индекс: русское название → канонический ключ. Без него человек, вписавший
# «Йога» руками, создавал бы свою категорию рядом с существующей `yoga`.
_BY_TITLE: dict[str, str] = {title.lower(): key for key, title in CANONICAL.items()}


def normalize(value: str | None) -> str | None:
    """Привести категорию к каноничному виду.

    Известный ключ остаётся ключом. Своя категория схлопывается в нижний регистр
    с одиночными пробелами — так «Настольный   теннис» и «настольный теннис»
    попадут в одну корзину.
    """
    if value is None:
        return None
    cleaned = " ".join(value.split()).strip()
    if not cleaned:
        return None
    lowered = cleaned.lower()
    if lowered in CANONICAL:
        return lowered
    if lowered in _BY_TITLE:  # вписали название существующей категории словами
        return _BY_TITLE[lowered]
    return lowered[:MAX_CATEGORY_LEN]


def title_of(key: str | None) -> str:
    """Человекочитаемое имя: для своих категорий — с заглавной буквы."""
    if not key:
        return "Событие"
    if key in CANONICAL:
        return CANONICAL[key]
    return key[:1].upper() + key[1:]


def is_canonical(key: str | None) -> bool:
    return bool(key) and key in CANONICAL
