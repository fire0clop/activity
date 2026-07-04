from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

_INSECURE_SECRETS = {"change-me", "dev-secret-change-me-0123456789abcdef", ""}


class Settings(BaseSettings):
    """Конфигурация приложения, читается из переменных окружения / .env."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App
    app_env: str = "development"
    app_secret_key: str = "change-me"
    api_v1_prefix: str = "/api/v1"
    cors_origins: str = "*"  # CSV-список доменов; "*" только для dev

    # Auto-create tables on startup (dev only). В проде — Alembic.
    # По умолчанию False; включается явно через AUTO_CREATE_TABLES=true в dev .env.
    auto_create_tables: bool = False

    # Database
    database_url: str = "postgresql+asyncpg://skhodka:skhodka@db:5432/skhodka"
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_nullpool: bool = False  # включается в тестах: свежее соединение на каждый запрос

    # Redis
    redis_url: str = "redis://redis:6379/0"

    # JWT
    jwt_alg: str = "HS256"
    access_token_ttl_min: int = 30
    refresh_token_ttl_days: int = 30

    # OTP
    otp_ttl_seconds: int = 300
    otp_length: int = 6
    otp_max_attempts: int = 5
    otp_resend_cooldown_sec: int = 60
    sms_provider: str = "stub"  # stub | smsc | twilio
    sms_sender: str = ""        # имя отправителя (опционально; согласуется в кабинете SMSC)
    smsc_login: str = ""
    smsc_password: str = ""
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_from: str = ""       # номер/alphanumeric sender id, купленный в Twilio

    # Rate limiting (общий лимит на IP по REST-эндпоинтам)
    rate_limit_enabled: bool = True
    rate_limit_per_min: int = 120

    # Per-user лимиты на спам-действия (не зависят от IP — не обходятся через VPN)
    user_rate_limit_enabled: bool = True
    user_rl_events_per_hour: int = 10       # создание событий
    user_rl_joins_per_hour: int = 30        # отклики на события
    user_rl_reports_per_hour: int = 10      # жалобы
    user_rl_messages_per_min: int = 60      # сообщения в чате (WS)

    # Storage
    storage_backend: str = "local"  # local | s3
    media_root: str = "/app/media"
    media_public_url: str = "http://localhost:8000/media"
    max_upload_mb: int = 10
    allowed_image_types: str = "image/jpeg,image/png,image/webp"
    image_max_dimension: int = 1600  # px, ресайз по большей стороне

    # S3 / MinIO (если storage_backend=s3)
    s3_endpoint: str = ""           # пусто = AWS; для MinIO http://minio:9000
    s3_region: str = "us-east-1"
    s3_bucket: str = "skhodka-media"
    s3_access_key: str = ""
    s3_secret_key: str = ""
    s3_public_url: str = ""         # базовый URL для отдачи объектов

    # Push (FCM — для Android; APNs — напрямую для iOS)
    fcm_project_id: str = ""
    fcm_credentials_json: str = ""

    apns_key_path: str = ""        # путь к .p8 (AuthKey_XXXX.p8)
    apns_key_id: str = ""          # Key ID ключа
    apns_team_id: str = ""         # Team ID разработчика
    apns_bundle_id: str = "com.skhodka.app"
    apns_use_sandbox: bool = True  # True для dev-сборок, False для App Store / TestFlight

    @property
    def allowed_image_types_set(self) -> set[str]:
        return {t.strip() for t in self.allowed_image_types.split(",") if t.strip()}

    @property
    def cors_origins_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_dev(self) -> bool:
        return self.app_env == "development"

    def validate_for_prod(self) -> None:
        """Fail-fast: в проде нельзя стартовать с дефолтными секретами/настройками."""
        if self.is_dev:
            return
        problems = []
        if self.app_secret_key in _INSECURE_SECRETS:
            problems.append("APP_SECRET_KEY не задан/дефолтный")
        if self.cors_origins.strip() == "*":
            problems.append("CORS_ORIGINS='*' недопустим в проде")
        if self.storage_backend == "s3" and not (self.s3_bucket and self.s3_public_url):
            problems.append("S3 включён, но S3_BUCKET/S3_PUBLIC_URL не заданы")
        if self.auto_create_tables:
            problems.append("AUTO_CREATE_TABLES=true недопустим в проде (используйте Alembic)")
        if self.sms_provider == "stub":
            problems.append("SMS_PROVIDER=stub недопустим в проде (smsc или twilio)")
        elif self.sms_provider == "smsc" and not (self.smsc_login and self.smsc_password):
            problems.append("SMS_PROVIDER=smsc, но SMSC_LOGIN/SMSC_PASSWORD не заданы")
        elif self.sms_provider == "twilio" and not (
            self.twilio_account_sid and self.twilio_auth_token and self.twilio_from
        ):
            problems.append("SMS_PROVIDER=twilio, но TWILIO_* не заданы")
        if problems:
            raise RuntimeError("Небезопасная прод-конфигурация: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
