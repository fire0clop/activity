# Сходка — Backend (FastAPI)

Бэкенд приложения «Сходка». Полный план и контракт API — в [ROADMAP.md](ROADMAP.md).

## Быстрый старт (dev)

```bash
cp .env.example .env        # уже есть готовый .env с dev-значениями
docker compose up --build
```

- API: http://localhost:8000  ·  Swagger: http://localhost:8000/docs
- Health (deep, проверяет БД+Redis): http://localhost:8000/api/v1/health
- Если порт 8000/6379 занят: `API_PORT=8080 docker compose up`

В dev таблицы создаются автоматически (`AUTO_CREATE_TABLES=true`). В **проде** — Alembic-миграции.

## OTP в dev

SMS не отправляются — код пишется в (структурный JSON) лог сервиса `api`:

```bash
docker compose logs -f api | grep OTP
```

## Тесты

Изолированная БД `skhodka_test` + Redis db1, чистое состояние перед каждым тестом:

```bash
make test          # создаёт тестовую БД и гоняет pytest
make lint          # ruff + mypy
```

CI (`.github/workflows/ci.yml`) поднимает postgis+redis, проверяет, что **миграция строит схему с нуля**, и гоняет тесты.

## Миграции (прод-путь)

```bash
make makemigration m="что изменили"   # alembic revision --autogenerate
make migrate                          # alembic upgrade head
```

Начальная миграция (`migrations/versions/*_init_schema.py`) проверена на чистой БД: создаёт все таблицы,
PostGIS-расширение и GIST-индекс по геоточке.

## Прод-запуск

```bash
# .env.prod с реальными секретами (APP_SECRET_KEY, CORS_ORIGINS, POSTGRES_*, при S3 — S3_*)
docker compose -f docker-compose.prod.yml run --rm migrate   # миграции
docker compose -f docker-compose.prod.yml up -d              # gunicorn + uvicorn workers
```

`APP_ENV=production` включает fail-fast: приложение не стартует с дефолтным секретом, `CORS_ORIGINS=*`
или незаполненной S3-конфигурацией (см. `app/core/config.validate_for_prod`).

## Хранилище медиа: local ↔ S3

- `STORAGE_BACKEND=local` (по умолчанию) — файлы на volume `media_data`, раздаются по `MEDIA_PUBLIC_URL`.
- `STORAGE_BACKEND=s3` — AWS S3 или MinIO. Локально: `make s3-up` поднимает MinIO, затем выставить
  `STORAGE_BACKEND=s3` и `S3_*` в окружении. Картинки валидируются и перекодируются через Pillow
  (ресайз, снятие EXIF). Проверено end-to-end на MinIO (upload → head → delete).

## Что сделано / границы

| Возможность | Статус |
|---|---|
| Auth по телефону (OTP→JWT, ротация refresh) | ✅ |
| Профиль + обязательное фото/«о себе» (гейтинг 403) | ✅ |
| События CRUD + геолента (PostGIS, без N+1) + сокрытие времени | ✅ |
| Заявки: accept/reject, авто-приём, **waitlist-продвижение**, блокировки | ✅ |
| Беседы + чат (WebSocket) + **Redis pub/sub fan-out (мульти-инстанс)** + read-receipts | ✅ |
| Завершение события (ручное + авто-sweeper) → отзывы и рейтинг | ✅ |
| Жалобы/блокировки (применяются в ленте и заявках) | ✅ |
| Подписки на категорию/район → пуш о новых событиях | ✅ |
| Групповые чаты V2 (создание/состав/роли) | ✅ + клиент iOS |
| S3/MinIO хранилище + Pillow-обработка картинок | ✅ |
| Rate-limit (Redis: per-IP + per-user на спам-действия), structured JSON-логи + request_id, deep-health, CORS из env, fail-fast | ✅ |
| Alembic-миграции + прод-compose (gunicorn) + CI | ✅ |
| Тесты (auth/гео/waitlist/чат WS/пуши/подписки/лимиты/констрейнты/SMS) | ✅ 44 шт. |
| Push (FCM HTTP v1) | ✅ подключён (project `activity-fbdeb`), авторизация и путь отправки проверены; невалидные токены авто-удаляются |
| Реальные SMS | ✅ Twilio и SMSC.ru реализованы; креды подключаются в .env (в проде stub запрещён fail-fast'ом) |
| Нагрузочное тестирование, APM/мониторинг, алёрты | ⛔ требует вашей инфраструктуры |

> Граница «боевой под нагрузкой»: код production-grade и проверен функционально/интеграционно,
> но load-тест, метрики/трейсинг и боевые креды SMS+FCM подключаются на вашей инфраструктуре.

## Структура

См. раздел 2 в [ROADMAP.md](ROADMAP.md). Логика — `app/services`, роутеры — `app/api/v1`,
модели — `app/models`, схемы — `app/schemas`, WS — `app/ws`.
