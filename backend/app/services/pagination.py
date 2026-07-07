import base64
import json
import uuid
from datetime import datetime


def encode_cursor(offset: int) -> str:
    """Offset-курсор — для списков, не чувствительных к вставкам (беседы, сообщения)."""
    return base64.urlsafe_b64encode(str(offset).encode()).decode()


def decode_cursor(cursor: str | None) -> int:
    if not cursor:
        return 0
    try:
        return int(base64.urlsafe_b64decode(cursor.encode()).decode())
    except (ValueError, TypeError):
        return 0


def encode_keyset(sort_value: datetime, row_id: uuid.UUID) -> str:
    """Keyset-курсор по (sort_value, id): устойчив к вставкам — без дублей/пропусков."""
    payload = json.dumps({"s": sort_value.isoformat(), "i": str(row_id)})
    return base64.urlsafe_b64encode(payload.encode()).decode()


def decode_keyset(cursor: str | None) -> tuple[datetime, uuid.UUID] | None:
    if not cursor:
        return None
    try:
        data = json.loads(base64.urlsafe_b64decode(cursor.encode()).decode())
        return datetime.fromisoformat(data["s"]), uuid.UUID(data["i"])
    except (ValueError, TypeError, KeyError):
        return None
