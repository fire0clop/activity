from typing import Annotated

from pydantic import BaseModel, Field

# Единый формат телефона: E.164 РФ (+7 и 10 цифр). Ограничивает вход, который иначе
# идёт напрямую в ключи Redis и в тело запроса к SMS-провайдеру (защита от мусора/abuse).
PhoneStr = Annotated[str, Field(pattern=r"^\+7\d{10}$", max_length=12, examples=["+79991234567"])]


class RequestCodeIn(BaseModel):
    phone: PhoneStr


class RequestCodeOut(BaseModel):
    sent: bool = True
    resend_after_sec: int


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


# --- Подтверждение телефона (шаг 2 регистрации) ---------------------------

class VerifyCodeIn(BaseModel):
    phone: PhoneStr
    code: str


class VerifyCodeOut(BaseModel):
    verification_token: str
    is_new_user: bool
    expires_in: int


# --- Регистрация: тикет подтверждённого телефона + пароль (шаг 3) ----------

class RegisterIn(BaseModel):
    verification_token: str
    password: str = Field(..., min_length=6, max_length=128)


class RegisterOut(TokenPair):
    is_new_user: bool


# --- Вход по паролю (без SMS) ---------------------------------------------

class LoginIn(BaseModel):
    phone: PhoneStr
    password: str


# --- Смена/сброс пароля (подтверждение по SMS) ----------------------------

class ResetPasswordIn(BaseModel):
    phone: PhoneStr
    code: str
    new_password: str = Field(..., min_length=6, max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str


class LogoutIn(BaseModel):
    refresh_token: str
