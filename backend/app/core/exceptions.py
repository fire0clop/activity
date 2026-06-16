from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class AppError(Exception):
    """Базовая ошибка приложения с машиночитаемым кодом (см. ROADMAP §11)."""

    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = 400,
        details: dict | None = None,
        headers: dict | None = None,
    ) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}
        self.headers = headers or {}
        super().__init__(message)


# --- Готовые помощники под частые ошибки из ROADMAP §11 -------------------

def unauthorized(message: str = "Требуется авторизация") -> AppError:
    return AppError("unauthorized", message, 401)


def forbidden(message: str = "Недостаточно прав") -> AppError:
    return AppError("forbidden", message, 403)


def profile_incomplete() -> AppError:
    return AppError(
        "profile_incomplete",
        "Заполните профиль (имя, фото и «о себе»), чтобы продолжить",
        403,
    )


def not_found(message: str = "Не найдено") -> AppError:
    return AppError("not_found", message, 404)


def conflict(code: str, message: str) -> AppError:
    return AppError(code, message, 409)


def _error_body(code: str, message: str, details: dict | None = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error_handler(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=_error_body(exc.code, exc.message, exc.details),
            headers=exc.headers,
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        # exc.errors() может содержать несериализуемые объекты в ctx (например, ValueError
        # из model_validator). Берём только JSON-безопасные поля.
        errors = [
            {"loc": list(e.get("loc", [])), "msg": e.get("msg", ""), "type": e.get("type", "")}
            for e in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=_error_body("validation_error", "Ошибка валидации запроса", {"errors": errors}),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code_map = {401: "unauthorized", 403: "forbidden", 404: "not_found"}
        code = code_map.get(exc.status_code, "http_error")
        message = exc.detail if isinstance(exc.detail, str) else "Ошибка запроса"
        return JSONResponse(status_code=exc.status_code, content=_error_body(code, message))
