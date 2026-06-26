import base64


def encode_cursor(offset: int) -> str:
    """Простой offset-курсор (для скелета). При росте заменить на keyset-пагинацию."""
    return base64.urlsafe_b64encode(str(offset).encode()).decode()


def decode_cursor(cursor: str | None) -> int:
    if not cursor:
        return 0
    try:
        return int(base64.urlsafe_b64decode(cursor.encode()).decode())
    except (ValueError, TypeError):
        return 0
