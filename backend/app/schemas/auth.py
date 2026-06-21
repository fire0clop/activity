from pydantic import BaseModel, Field


class RequestCodeIn(BaseModel):
    phone: str = Field(..., examples=["+79991234567"])


class RequestCodeOut(BaseModel):
    sent: bool = True
    resend_after_sec: int


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


# --- Регистрация по телефону (SMS) + пароль -------------------------------

class RegisterIn(BaseModel):
    phone: str
    code: str
    password: str = Field(..., min_length=6, max_length=128)


class RegisterOut(TokenPair):
    is_new_user: bool


# --- Вход по паролю (без SMS) ---------------------------------------------

class LoginIn(BaseModel):
    phone: str
    password: str


# --- Смена/сброс пароля (подтверждение по SMS) ----------------------------

class ResetPasswordIn(BaseModel):
    phone: str
    code: str
    new_password: str = Field(..., min_length=6, max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str


class LogoutIn(BaseModel):
    refresh_token: str
