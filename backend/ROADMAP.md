# Backend Roadmap — «Сходка» (FastAPI + Docker)

> Этот файл — одновременно **план реализации бэкенда** (с чекпоинтами) и **документация API**.
> Когда бэкенд-разработчик закрывает все чекпоинты, он отдаёт этот файл фронтендеру —
> в разделах [9. API-справочник](#9-api-справочник), [10. WebSocket-чат](#10-websocket-чат)
> и [11. Модель ошибок](#11-модель-ошибок) описан полный контракт, по которому работает iOS-клиент.

---

## 0. Как пользоваться этим документом

- Каждый блок реализации содержит чекбоксы `- [ ]`. Отмечай `- [x]` по мере готовности.
- Порядок этапов = порядок реализации. Не прыгай вперёд: следующий этап опирается на предыдущий.
- Раздел «Definition of Done» в конце каждого этапа — критерий, что этап действительно закрыт.
- Контракт API (пути, тела запросов, коды ответов) — это **источник правды**. Если меняешь его в коде,
  обнови этот файл в том же PR, иначе фронт сломается.

**Глобальный прогресс по этапам:**

- [ ] Этап 1. Каркас проекта и Docker
- [ ] Этап 2. БД, модели, миграции (PostgreSQL + PostGIS)
- [ ] Этап 3. Аутентификация по телефону (OTP) + JWT
- [ ] Этап 4. Профиль пользователя (**фото и «о себе» — обязательны**, гейтинг действий)
- [ ] Этап 5. События (CRUD) + геопоиск ленты (**точное время скрыто до подтверждения**)
- [ ] Этап 6. Заявки на участие и подбор группы (организатор фильтрует, кого пускать)
- [ ] Этап 7. Беседы и групповой чат (WebSocket) — event-чат на обобщённой модели «бесед»
- [ ] Этап 8. Отзывы и рейтинг
- [ ] Этап 9. Жалобы, блокировки, модерация
- [ ] Этап 10. Push-уведомления (FCM)
- [ ] Этап 11. Тесты, документация, продакшен-готовность
- [ ] Этап 12 (V2). Самостоятельные групповые чаты (мессенджер-режим для устоявшихся компаний)

---

## 1. Технологический стек

| Компонент | Выбор | Зачем |
|---|---|---|
| Язык / фреймворк | Python 3.12 + FastAPI | Быстрый старт, авто-OpenAPI, async |
| ASGI-сервер | Uvicorn (за Gunicorn в проде) | Стандарт для FastAPI |
| БД | PostgreSQL 16 + PostGIS 3.4 | Геопоиск событий «рядом» |
| ORM | SQLAlchemy 2.0 (async) + GeoAlchemy2 | Async-модели + гео-типы |
| Миграции | Alembic | Версионирование схемы |
| Валидация | Pydantic v2 | Схемы запросов/ответов |
| Кеш / очереди / pub-sub чата | Redis 7 | OTP-коды, rate-limit, fan-out WS |
| Аутентификация | JWT (access + refresh), `python-jose` | Stateless-токены |
| Хеши паролей/секретов | `passlib[bcrypt]` (для refresh-токенов) | — |
| Хранилище медиа | Локальный диск (Docker volume) за `StorageService` | Обложки/аватары. S3 — опционально позже, без смены вызовов |
| Push | Firebase Cloud Messaging (HTTP v1) | Уведомления |
| SMS / OTP | Провайдер SMS (заглушка в dev) | Верификация телефона |
| Тесты | pytest + httpx + pytest-asyncio | — |
| Контейнеризация | Docker + docker-compose | Локальный и прод-запуск |
| Линт / формат | ruff + black + mypy | Качество кода |

---

## 2. Структура проекта

```
backend/
├── docker-compose.yml          # api + db(postgis) + redis  (медиа — на volume, без отдельного сервиса)
├── Dockerfile
├── .dockerignore
├── .env.example                # шаблон переменных окружения
├── pyproject.toml              # зависимости (или requirements.txt)
├── alembic.ini
├── migrations/                 # Alembic
│   └── versions/
├── tests/
│   ├── conftest.py
│   └── test_*.py
└── app/
    ├── main.py                 # создание FastAPI, подключение роутеров, middleware
    ├── core/
    │   ├── config.py           # Settings (pydantic-settings), читает .env
    │   ├── security.py         # JWT create/verify, хеши
    │   ├── deps.py             # зависимости FastAPI (get_db, get_current_user)
    │   └── exceptions.py       # кастомные исключения + handlers
    ├── db/
    │   ├── session.py          # async engine, sessionmaker
    │   └── base.py             # Base = DeclarativeBase
    ├── models/                 # SQLAlchemy ORM-модели
    │   ├── user.py
    │   ├── event.py
    │   ├── participation.py
    │   ├── conversation.py      # беседы (event-чат и групповые) + участники беседы
    │   ├── message.py
    │   ├── review.py
    │   └── report.py
    ├── schemas/                # Pydantic-схемы (request/response)
    │   ├── auth.py
    │   ├── user.py
    │   ├── event.py
    │   ├── participation.py
    │   ├── message.py
    │   └── review.py
    ├── api/
    │   └── v1/
    │       ├── router.py       # агрегатор всех роутеров под /api/v1
    │       ├── auth.py
    │       ├── users.py
    │       ├── events.py
    │       ├── participations.py
    │       ├── conversations.py # беседы и групповые чаты (REST: список, создание группы, участники)
    │       ├── chat.py          # история сообщений беседы (REST-фолбэк)
    │       ├── reviews.py
    │       └── reports.py
    ├── services/               # бизнес-логика (отделена от роутеров)
    │   ├── otp_service.py
    │   ├── event_service.py
    │   ├── matching_service.py
    │   ├── chat_service.py
    │   ├── storage_service.py  # сохранение/раздача медиа: LocalStorage (диск) | S3Storage (позже)
    │   └── push_service.py
    └── ws/
        └── manager.py          # ConnectionManager для WebSocket-чата
```

**Definition of Done (этап 1):**
- [ ] Структура каталогов создана.
- [ ] `docker-compose up` поднимает api + postgis + redis без ошибок; каталог медиа примонтирован как volume.
- [ ] `GET /api/v1/health` отвечает `200 {"status":"ok"}`.
- [ ] OpenAPI доступен на `/docs`.

### Чекпоинты этапа 1
- [ ] `pyproject.toml`/`requirements.txt` с зафиксированными версиями.
- [ ] `Dockerfile` (multi-stage: builder + slim runtime).
- [ ] `docker-compose.yml` с сервисами `api`, `db`, `redis` и healthcheck'ами; named volume для медиа (`media_data:/app/media`).
- [ ] `.env.example` со всеми переменными (см. раздел 3).
- [ ] `app/main.py` с CORS-middleware, подключением `api/v1/router.py`, обработчиками исключений.
- [ ] `app/core/config.py` через `pydantic-settings`.
- [ ] Эндпоинт `/api/v1/health`.

---

## 3. Переменные окружения (`.env.example`)

```env
# App
APP_ENV=development
APP_SECRET_KEY=change-me-32-bytes-min
API_V1_PREFIX=/api/v1

# Database
POSTGRES_HOST=db
POSTGRES_PORT=5432
POSTGRES_USER=skhodka
POSTGRES_PASSWORD=skhodka
POSTGRES_DB=skhodka
DATABASE_URL=postgresql+asyncpg://skhodka:skhodka@db:5432/skhodka

# Redis
REDIS_URL=redis://redis:6379/0

# JWT
JWT_ALG=HS256
ACCESS_TOKEN_TTL_MIN=30
REFRESH_TOKEN_TTL_DAYS=30

# OTP
OTP_TTL_SECONDS=300
OTP_LENGTH=6
OTP_MAX_ATTEMPTS=5
OTP_RESEND_COOLDOWN_SEC=60
SMS_PROVIDER=stub          # stub | twilio | smsc — в dev пишет код в лог

# Storage (медиа на локальном диске за StorageService)
STORAGE_BACKEND=local            # local | s3 — переключатель реализации
MEDIA_ROOT=/app/media            # путь внутри контейнера, монтируется как volume
MEDIA_PUBLIC_URL=http://localhost:8000/media   # как файлы раздаются клиенту
MAX_UPLOAD_MB=10                 # лимит размера загружаемого файла
ALLOWED_IMAGE_TYPES=image/jpeg,image/png,image/webp
# --- если позже STORAGE_BACKEND=s3, добавить: S3_ENDPOINT/S3_BUCKET/S3_ACCESS_KEY/S3_SECRET_KEY/S3_PUBLIC_URL ---

# Push (FCM)
FCM_PROJECT_ID=
FCM_CREDENTIALS_JSON=        # путь к service-account.json
```

> ⚠️ Для фронтендера важны только базовый URL API и схема ответов — все секреты остаются на бэке.

---

## 4. Соглашения API

- Базовый префикс: **`/api/v1`**. Все примеры ниже относительны к нему (`/auth/...` = `/api/v1/auth/...`).
- Формат тела — **JSON**, кодировка UTF-8. Загрузка медиа — `multipart/form-data`.
- Аутентификация — заголовок **`Authorization: Bearer <access_token>`**.
- Даты/время — **ISO 8601 в UTC** (`2026-06-20T14:30:00Z`). Клиент сам конвертирует в локаль.
- Координаты — `latitude` / `longitude` в десятичных градусах (WGS84).
- Пагинация — **cursor-based**: query `?limit=20&cursor=<opaque>`; ответ содержит `next_cursor` (или `null`).
- Идентификаторы — **UUID v4** (строки).
- Версионирование — путь (`/api/v1`). Несовместимые изменения → `/api/v2`.
- **Медиа** (аватары, обложки) раздаются по абсолютным URL вида `{MEDIA_PUBLIC_URL}/<path>`.
  В dev — статикой FastAPI (`app.mount("/media", StaticFiles(...))`), в проде — отдаёт Nginx с того же volume.
  Клиенту всегда приходит готовый URL, а не путь к файлу.
- **Сокрытие точного времени** (требование безопасности): в карточке и ленте поле `starts_at` (точное
  время) видно только организатору и **подтверждённым** участникам. Всем остальным возвращается только
  `day` (дата) и `time_disclosed: false`. Точное время участник узнаёт после `accept` (в карточке, чате и push).
- **Обязательный профиль:** создавать события, откликаться и писать в чат может только пользователь с
  заполненным профилем (имя + аватар + «о себе»). Иначе — `403 profile_incomplete` (см. раздел 11).

---

## 5. Этап 2 — БД, модели, миграции

### Чекпоинты
- [ ] Включить расширение PostGIS в init-скрипте БД (`CREATE EXTENSION IF NOT EXISTS postgis;`).
- [ ] Настроить Alembic (async) + автогенерация миграций.
- [ ] Реализовать модели (ниже) и первую миграцию.
- [ ] Индексы: GIST по `events.location`, btree по `events.starts_at`, FK-индексы.

### Схема БД (минимум для MVP)

**users**
| Поле | Тип | Заметки |
|---|---|---|
| id | UUID PK | |
| phone | varchar unique | E.164, напр. `+79991234567` |
| name | varchar | |
| bio | text null | «о себе» |
| avatar_url | varchar null | |
| birth_date | date null | для опц. фильтров по возрасту |
| gender | enum(`male`,`female`,`other`,`unspecified`) | |
| rating_avg | numeric(3,2) default 0 | агрегат из reviews |
| rating_count | int default 0 | |
| events_created | int default 0 | счётчик для «истории» |
| events_attended | int default 0 | |
| is_phone_verified | bool default false | |
| created_at | timestamptz | «давно ли в приложении» |
| updated_at | timestamptz | |

> **Обязательный профиль.** `name`, `avatar_url` и `bio` технически nullable (на момент первого входа их нет),
> но действия (создать/откликнуться/писать) разрешены только когда все три заполнены.
> Вводим вычисляемое `profile_completed = name != null AND avatar_url != null AND bio != null`
> (свойство модели или generated column) — отдаётся в `UserPrivate` и проверяется в зависимостях.

**refresh_tokens** (для ротации refresh)
| id UUID PK | user_id FK | token_hash | expires_at | revoked bool | created_at |

**events**
| Поле | Тип | Заметки |
|---|---|---|
| id | UUID PK | |
| organizer_id | UUID FK → users | |
| title | varchar | «Гидроциклы» — свободный текст |
| description | text null | формат, что взять, бюджет |
| category | varchar null | тег/категория для поиска |
| starts_at | timestamptz | точное начало. **Видно только организатору и accepted-участникам** (см. §4) |
| ends_at | timestamptz null | конец диапазона / «после обеда» (та же видимость, что и `starts_at`) |
| location | geography(Point,4326) | точка на карте |
| address | varchar null | текстовое описание места |
| min_participants | int default 2 | |
| max_participants | int | сколько нужно всего (вкл. организатора) |
| price | numeric null | общая стоимость, если есть |
| price_split | enum(`per_person`,`shared`,`free`) | как делится |
| cover_url | varchar null | обложка |
| auto_accept | bool default false | авто-приём первых N |
| status | enum(`open`,`full`,`closed`,`cancelled`,`finished`) | |
| created_at / updated_at | timestamptz | |

**participations** (заявки/участники)
| Поле | Тип | Заметки |
|---|---|---|
| id | UUID PK | |
| event_id | UUID FK | |
| user_id | UUID FK | |
| status | enum(`pending`,`accepted`,`rejected`,`waitlisted`,`cancelled`) | |
| created_at | timestamptz | порядок в очереди ожидания |
| decided_at | timestamptz null | |
| — | unique(event_id, user_id) | один отклик на событие |

**conversations** (беседа — единая модель для event-чата и групповых чатов)
| Поле | Тип | Заметки |
|---|---|---|
| id | UUID PK | |
| type | enum(`event`,`group`) | `event` — чат события; `group` — самостоятельный чат (V2) |
| title | varchar null | имя группы; для event берётся из события |
| event_id | UUID FK → events null | заполнено только для `type=event`, unique |
| created_by | UUID FK → users | |
| is_archived | bool default false | event-чат архивируется при `finished` |
| created_at | timestamptz | |

**conversation_members** (кто в беседе)
| id UUID PK | conversation_id FK | user_id FK | role enum(`owner`,`member`) | joined_at | last_read_message_id UUID null | unique(conversation_id, user_id) |
- Для event-чата участники = организатор + `accepted`. Для группы — добавленные владельцем.

**messages** (сообщения любой беседы)
| id UUID PK | conversation_id FK | sender_id FK null | text | created_at | is_system bool |
- `is_system=true` — служебные (закреп с деталями события, «X присоединился»), `sender_id=null`.

> **Почему так.** Чат события и «обычный» групповой чат — одна сущность (беседа со списком участников).
> Делая обобщённую модель сразу, в V2 групповые чаты добавляются почти бесплатно: меняется только то,
> как беседа создаётся и кто в ней состоит. WebSocket и хранение сообщений — общие.

**reviews** (двусторонние отзывы)
| Поле | Тип | Заметки |
|---|---|---|
| id UUID PK | | |
| event_id | UUID FK | |
| author_id | UUID FK | кто оставил |
| target_id | UUID FK | про кого (участник или организатор) |
| rating | smallint (1–5) | |
| comment | text null | |
| created_at | timestamptz | |
| — | unique(event_id, author_id, target_id) | один отзыв на пару за событие |

**reports** (жалобы)
| id UUID PK | reporter_id FK | target_user_id FK null | target_event_id FK null | reason enum | comment text | status enum(`new`,`reviewed`,`actioned`) | created_at |

**blocks** (блокировки между пользователями)
| id UUID PK | blocker_id FK | blocked_id FK | created_at | unique(blocker_id, blocked_id) |

**device_tokens** (FCM)
| id UUID PK | user_id FK | token varchar | platform enum(`ios`,`android`) | created_at | unique(token) |

**Definition of Done (этап 2):**
- [ ] `alembic upgrade head` создаёт все таблицы с нуля.
- [ ] PostGIS работает: тест-запрос `ST_DWithin` возвращает результат.
- [ ] Сидер (опц.) наполняет 5 тестовых событий для разработки фронта.

---

## 6. Этап 3 — Аутентификация по телефону (OTP) + JWT

### Логика
1. Клиент шлёт телефон → бэк генерирует 6-значный код, кладёт в Redis (`otp:<phone>`), шлёт SMS (в dev — в лог).
2. Клиент шлёт телефон + код → бэк проверяет, создаёт/находит пользователя, выдаёт `access` + `refresh`.
3. `access` живёт 30 мин, `refresh` — 30 дней (хранится хешем в `refresh_tokens`, ротация при обновлении).
4. Rate-limit: не чаще 1 SMS в 60 сек на номер; не более 5 попыток ввода кода.

### Чекпоинты
- [ ] `otp_service`: генерация, хранение, проверка, cooldown, лимит попыток.
- [ ] JWT create/verify в `core/security.py`.
- [ ] Ротация refresh-токенов + отзыв при logout.
- [ ] Зависимость `get_current_user` (парсит Bearer, грузит пользователя, проверяет блокировку).
- [ ] Заглушка SMS-провайдера + интерфейс под реальный.

**Definition of Done (этап 3):**
- [ ] Полный цикл: запрос кода → подтверждение → получение токенов → доступ к защищённому эндпоинту.
- [ ] Протухший/неверный код и превышение лимитов отдают корректные ошибки (см. раздел 11).

---

## 6.5 Этап 4 — Профиль (фото и «о себе» обязательны)

Требование: у каждого пользователя должны быть **фото** и **информация о себе**. Без этого нельзя
создавать события, откликаться и писать в чат — чтобы в ленте/заявках не было «пустых» анонимов.

### Логика
- После первого входа (`is_new_user`) клиент обязан провести онбординг: имя + аватар + bio.
- `StorageService` (этап 1) сохраняет аватар на диск/volume, возвращает публичный URL.
- Вычисляемое `profile_completed` (см. схему users) отдаётся в `GET /users/me`.
- Зависимость `require_complete_profile` оборачивает «действия» и кидает `403 profile_incomplete`,
  если профиль не заполнен.

### Чекпоинты
- [ ] `storage_service`: `LocalStorage` (save/url/delete) + интерфейс под будущий `S3Storage`.
- [ ] Валидация загрузки: тип (`ALLOWED_IMAGE_TYPES`), размер (`MAX_UPLOAD_MB`), ресайз/нормализация (опц.).
- [ ] `GET /users/me`, `PATCH /users/me`, `POST /users/me/avatar`, `GET /users/{id}`.
- [ ] `profile_completed` корректно вычисляется и возвращается.
- [ ] `require_complete_profile` подключена к `POST /events`, `POST /events/{id}/join`, отправке сообщений.
- [ ] Раздача медиа: `app.mount("/media", StaticFiles(directory=MEDIA_ROOT))` (dev).

**Definition of Done (этап 4):** новый пользователь не может создать событие/откликнуться, пока не загрузил
фото и не заполнил «о себе»; аватар доступен по URL из ответа.

---

## 7. Этап 5 — События и геопоиск (ключевая механика)

### Геопоиск ленты
Лента «рядом» = события в радиусе `radius_km` от точки пользователя, отсортированные по времени начала
и/или расстоянию. Используем `ST_DWithin(location, ST_MakePoint(lng,lat)::geography, radius_m)`.

Быстрые фильтры: `today` / `tomorrow` / `weekend` (вычисляются по `starts_at` в таймзоне клиента —
клиент передаёт `tz` или диапазон `from`/`to`), `category`, `query` (полнотекстовый по title/description).

### Сокрытие точного времени
Точное `starts_at`/`ends_at` отдаётся **только организатору и `accepted`-участникам**. Остальные видят
лишь `day` (дату) и `time_disclosed: false`. Реализуется в слое сериализации: сервис формирует ответ,
зная, кто запрашивает (организатор / accepted / прочие). Это закрывает требование «чтобы не приходили те,
кого организатор не хочет видеть»: незваный человек знает только день и место, но не точное время сбора —
а после `accept` время раскрывается в карточке, чате и push.

### Чекпоинты
- [ ] `POST /events` — создание (с валидацией координат, времени в будущем, max≥min). Требует полного профиля.
- [ ] `GET /events` — лента с гео-радиусом, фильтрами, пагинацией. В выдаче время скрыто (только `day`).
- [ ] `GET /events/{id}` — карточка с агрегатами; `starts_at` присутствует только для организатора/accepted.
- [ ] `PATCH /events/{id}` / `DELETE /events/{id}` — только организатор.
- [ ] Загрузка обложки на диск через `storage_service` (`POST /events/{id}/cover`).
- [ ] Пересчёт `status` (`open`→`full` при заполнении).
- [ ] Хелпер сериализации `serialize_event(event, viewer)` — единая точка контроля видимости времени.

---

## 8. Этапы 6–10 — кратко (чекпоинты)

### Этап 6. Заявки и подбор группы (`matching_service`)
- [ ] `POST /events/{id}/join` — подать заявку (или авто-accept при `auto_accept` и наличии места). Требует полного профиля.
- [ ] `GET /events/{id}/participants` — список откликнувшихся (для организатора: профиль + фото + рейтинг, чтобы решить, кого пускать).
- [ ] `POST /participations/{id}/accept` / `reject` — решение организатора (фильтрация нежелательных).
- [ ] `DELETE /events/{id}/join` — отозвать заявку/выйти.
- [ ] Логика waitlist: при освобождении места — следующий по очереди + push.
- [ ] При `accept` участника: добавить его в беседу события (создать беседу при первом accepted),
      раскрыть ему точное время (системное сообщение в чат + push).

### Этап 7. Беседы и чат — см. раздел 10. Event-чат = `conversation` с `type=event`, привязанная к событию.
### Этап 8. Отзывы и рейтинг
- [ ] `POST /events/{id}/reviews` — после `finished`, двусторонние.
- [ ] Пересчёт `rating_avg`/`rating_count` у target.
- [ ] `GET /users/{id}/reviews`.
### Этап 9. Жалобы и блокировки
- [ ] `POST /reports`, `POST /users/{id}/block`, `DELETE /users/{id}/block`.
- [ ] Заблокированные не видят события друг друга в ленте.
### Этап 10. Push (FCM, `push_service`)
- [ ] `POST /devices` / `DELETE /devices/{token}` — регистрация токена.
- [ ] Триггеры push: новая заявка (организатору), решение по заявке (участнику),
      новое сообщение в чате, освобождение места из waitlist, напоминание о событии,
      раскрытие точного времени при `accept`.

### Этап 12 (V2). Самостоятельные групповые чаты — мессенджер-режим
Цель: устоявшаяся компания может писать друг другу напрямую, не привязываясь к конкретному событию.
Реализуется поверх той же модели `conversations` (`type=group`).
- [ ] `POST /conversations` — создать группу (title + список `member_ids`; создатель = `owner`).
      Можно создать «из события» (предзаполнить участниками `accepted`).
- [ ] `GET /conversations` — список моих бесед (и event, и group) с превью последнего сообщения и кол-вом непрочитанных.
- [ ] `POST /conversations/{id}/members` / `DELETE /conversations/{id}/members/{user_id}` — управление составом (owner).
- [ ] `PATCH /conversations/{id}` — переименование/смена обложки группы.
- [ ] `POST /conversations/{id}/leave` — выйти из группы.
- [ ] WebSocket и история сообщений — общие с event-чатом (см. раздел 10), отличается только создание и состав.

> Так как event-чат и групповой чат — одна сущность, V2 не ломает контракт: добавляются только новые
> эндпоинты `/conversations/*`, а `/ws/chat/{conversation_id}` уже универсален.

---

## 9. API-справочник

> Полный контракт. **Для фронтендера это основной раздел.** Все пути — относительно `/api/v1`.
> `🔒` = требует `Authorization: Bearer`.

### 9.1 Health
```
GET /health → 200 { "status": "ok" }
```

### 9.2 Auth

**Запросить код**
```
POST /auth/request-code
Body: { "phone": "+79991234567" }
200: { "sent": true, "resend_after_sec": 60 }
429: cooldown (см. ошибки)
```

**Подтвердить код / войти**
```
POST /auth/verify-code
Body: { "phone": "+79991234567", "code": "123456" }
200: {
  "access_token": "<jwt>",
  "refresh_token": "<jwt>",
  "token_type": "bearer",
  "expires_in": 1800,
  "is_new_user": true            // фронт показывает онбординг/заполнение профиля
}
400: invalid_code | 410: code_expired | 429: too_many_attempts
```

**Обновить токен**
```
POST /auth/refresh
Body: { "refresh_token": "<jwt>" }
200: { "access_token": "...", "refresh_token": "...", "token_type":"bearer", "expires_in":1800 }
401: invalid/revoked
```

**Выход** 🔒
```
POST /auth/logout
Body: { "refresh_token": "<jwt>" }
204
```

### 9.3 Users

**Мой профиль** 🔒
```
GET /users/me → 200 UserPrivate
```

**Обновить профиль** 🔒
```
PATCH /users/me
Body (любые поля): { "name": "Егор", "bio": "...", "birth_date":"1996-05-01", "gender":"male" }
200: UserPrivate
```

**Загрузить аватар** 🔒
```
POST /users/me/avatar   (multipart/form-data, field "file")
200: { "avatar_url": "https://..." }
```

**Публичный профиль другого пользователя** 🔒
```
GET /users/{id} → 200 UserPublic
```

**Объекты:**
```jsonc
// UserPublic
{
  "id": "uuid", "name": "Егор", "bio": "...", "avatar_url": "https://...|null",
  "gender": "male", "age": 30,                 // возраст вычислен из birth_date, либо null
  "rating_avg": 4.7, "rating_count": 12,
  "events_created": 5, "events_attended": 8,
  "member_since": "2026-01-10T00:00:00Z"
}
// UserPrivate = UserPublic + {
//   "phone": "+7...", "is_phone_verified": true, "birth_date": "1996-05-01|null",
//   "profile_completed": true        // false → клиент обязан догнать онбординг (имя+фото+bio)
// }
// Примечание: avatar_url и bio обязательны для действий. Если profile_completed=false,
// эндпоинты создания/отклика/чата вернут 403 profile_incomplete.
```

### 9.4 Events

**Лента (список/карта)** 🔒
```
GET /events?lat=55.75&lng=37.62&radius_km=10
            &when=today|tomorrow|weekend            // опц. быстрый фильтр
            &from=2026-06-20T00:00:00Z&to=...        // опц. произвольный диапазон
            &category=tennis&query=концерт           // опц.
            &limit=20&cursor=<opaque>
200: {
  "items": [ EventListItem, ... ],
  "next_cursor": "<opaque>|null"
}
```
```jsonc
// EventListItem (компактно для ленты/пинов на карте)
{
  "id": "uuid",
  "title": "Гидроциклы на Клязьме",
  "category": "watersport|null",
  "day": "2026-06-21",                  // дата сбора — видна всегда
  "starts_at": null,                    // точное время: null, если ты не организатор и не accepted
  "ends_at": null,                      // то же правило, что и starts_at
  "time_disclosed": false,              // true → starts_at/ends_at заполнены (ты организатор/accepted)
  "latitude": 55.91, "longitude": 37.81,
  "address": "Пирс №3, прокат «Волна»|null",
  "cover_url": "https://...|null",
  "participants_current": 2,     // accepted, включая организатора
  "participants_max": 5,
  "price": 4000, "price_split": "shared",
  "status": "open",
  "distance_km": 8.4,            // от переданной точки
  "organizer": { "id":"uuid", "name":"Егор", "avatar_url":"...|null", "rating_avg":4.7 }
}
```

**Создать событие** 🔒
```
POST /events
Body: {
  "title": "Гидроциклы на Клязьме",
  "description": "Берём 2 гидроцикла на компанию, делим стоимость...",
  "category": "watersport",
  "starts_at": "2026-06-21T11:00:00Z",
  "ends_at": "2026-06-21T14:00:00Z",          // null допустимо
  "latitude": 55.91, "longitude": 37.81,
  "address": "Пирс №3, прокат «Волна»",
  "min_participants": 2,
  "max_participants": 5,
  "price": 4000, "price_split": "shared",     // free|per_person|shared
  "auto_accept": false
}
201: EventDetail
422: ошибки валидации (время в прошлом, max<min, координаты вне диапазона)
```

**Карточка события** 🔒
```
GET /events/{id} → 200 EventDetail
```
```jsonc
// EventDetail = EventListItem + {
  "description": "...",
  "min_participants": 2,
  "auto_accept": false,
  "created_at": "...",
  "my_participation": { "status": "pending|accepted|rejected|waitlisted|cancelled" } | null,
  "is_organizer": false,
  "chat_available": true,       // true когда есть беседа события (≥1 accepted)
  "conversation_id": "uuid|null" // id беседы для WS/истории; null пока чат не создан
  // Напоминание: starts_at/ends_at здесь тоже null, пока time_disclosed=false.
  // Точное время появляется после accept (и дублируется в чат + push).
}
```

**Изменить / удалить (только организатор)** 🔒
```
PATCH  /events/{id}   Body: любые редактируемые поля → 200 EventDetail
DELETE /events/{id}   → 204            // переводит в cancelled, уведомляет участников
```

**Обложка** 🔒
```
POST /events/{id}/cover   (multipart, field "file")  → 200 { "cover_url": "https://..." }
```

### 9.5 Participations (заявки)

**Подать заявку / присоединиться** 🔒
```
POST /events/{id}/join
200: { "status": "pending" }            // обычное событие
200: { "status": "accepted" }           // если auto_accept и есть место
200: { "status": "waitlisted" }         // мест нет, встал в очередь
409: already_joined | 409: event_full (если waitlist отключён) | 409: event_closed
```

**Отозвать заявку / выйти** 🔒
```
DELETE /events/{id}/join → 204
```

**Список участников/откликов** 🔒 (организатор видит pending; участники — только accepted)
```
GET /events/{id}/participants?status=pending|accepted|waitlisted
200: { "items": [ {
  "participation_id":"uuid",
  "user": UserPublic,
  "status":"pending",
  "created_at":"..."
} ] }
```

**Решение организатора** 🔒
```
POST /participations/{participation_id}/accept → 200 { "status":"accepted" }
POST /participations/{participation_id}/reject → 200 { "status":"rejected" }
403: не организатор | 409: нет мест (для accept)
```

### 9.6 Reviews
```
🔒 POST /events/{id}/reviews
   Body: { "target_id":"uuid", "rating":5, "comment":"..." }
   201: Review | 409: already_reviewed | 422: событие не finished
🔒 GET /users/{id}/reviews?limit=20&cursor=... → { "items":[Review], "next_cursor":... }
// Review: { id, event_id, author: UserPublic, target_id, rating, comment, created_at }
```

### 9.7 Reports / Blocks
```
🔒 POST /reports
   Body: { "target_user_id":"uuid"|null, "target_event_id":"uuid"|null,
           "reason":"spam|inappropriate|safety|other", "comment":"..." }
   201: { "id":"uuid", "status":"new" }
🔒 POST   /users/{id}/block  → 204
🔒 DELETE /users/{id}/block  → 204
```

### 9.8 Devices (push-токены)
```
🔒 POST /devices    Body: { "token":"<fcm>", "platform":"ios" } → 204
🔒 DELETE /devices/{token} → 204
```

### 9.9 Conversations (беседы: event-чаты и группы)
Беседа — единая сущность. У event-чата `type="event"` и есть `event_id`; у группы `type="group"`.
Эндпоинты `/conversations/*` для **создания группы** — это V2 (этап 12), но список/история работают
для event-чатов уже в MVP.
```
🔒 GET /conversations?limit=20&cursor=...        // мои беседы (event + group)
   200: { "items":[ ConversationListItem ], "next_cursor":... }

🔒 GET /conversations/{id} → 200 ConversationDetail
🔒 GET /conversations/{id}/messages?limit=50&cursor=...   // история (REST-фолбэк к WS)
   200: { "items":[ Message ], "next_cursor":... }

// --- V2 (этап 12), мессенджер-режим: ---
🔒 POST   /conversations            Body: { "title":"Наша компания", "member_ids":["uuid",...],
                                            "from_event_id":"uuid|null" } → 201 ConversationDetail
🔒 PATCH  /conversations/{id}        Body: { "title":"..." } → 200 ConversationDetail
🔒 POST   /conversations/{id}/members        Body: { "user_ids":["uuid",...] } → 200 ConversationDetail
🔒 DELETE /conversations/{id}/members/{user_id} → 204
🔒 POST   /conversations/{id}/leave  → 204
```
```jsonc
// ConversationListItem
{
  "id":"uuid", "type":"event|group",
  "title":"Гидроциклы на Клязьме",
  "avatar_url":"https://...|null",        // обложка события или группы
  "event_id":"uuid|null",
  "members_count":4,
  "last_message": { "text":"Во сколько?", "created_at":"...", "sender_name":"Аня" } | null,
  "unread_count":3,
  "is_archived":false
}
// ConversationDetail = ConversationListItem + { "members":[ UserPublic ], "my_role":"owner|member" }
```

---

## 10. WebSocket-чат

Один WS-эндпоинт обслуживает любую беседу (и event-чат, и группу) — через `conversation_id`.
Доступ — только членам беседы (для event: организатор + `accepted`).

**Подключение**
```
WS  /api/v1/ws/chat/{conversation_id}?token=<access_token>
```
- Токен — в query (заголовки в WS на iOS неудобны). Сервер валидирует JWT и членство в беседе.
- `conversation_id` для события берётся из `EventDetail.conversation_id`.
- При успехе сервер сразу шлёт последние N сообщений (`history`).

**Сообщения сервер→клиент** (JSON, поле `type`):
```jsonc
{ "type":"history", "messages":[ Message, ... ] }
{ "type":"message", "message": Message }
{ "type":"system",  "message": Message }      // «X присоединился», закреп с деталями события
{ "type":"presence","online_user_ids":["uuid", ...] }
{ "type":"error",   "code":"forbidden|not_a_member", "detail":"..." }
```

**Сообщения клиент→сервер:**
```jsonc
{ "type":"message", "text":"Во сколько у пирса?" }
{ "type":"typing" }                            // опц. индикатор набора
{ "type":"read", "last_message_id":"uuid" }    // опц. отметка прочтения
```

**Message:**
```jsonc
{ "id":"uuid", "conversation_id":"uuid", "sender": UserPublic|null,  // null для системных
  "text":"...", "is_system":false, "created_at":"2026-06-20T12:00:00Z" }
```

> История доступна и по REST: `GET /conversations/{id}/messages` (см. §9.9) — на случай открытия экрана без WS.

### Чекпоинты этапа 7
- [ ] `ws/manager.py` — пул соединений по `conversation_id`, fan-out через Redis pub/sub (масштабирование на N инстансов).
- [ ] Авторизация при подключении (JWT + членство в беседе через `conversation_members`).
- [ ] Персист сообщений в БД + рассылка online-участникам + обновление `last_read_message_id`.
- [ ] Push тем, кто оффлайн.
- [ ] Архивация event-чата при `status=finished` (read-only, история доступна).

---

## 11. Модель ошибок

Единый формат ошибки во всех REST-ответах:
```jsonc
{
  "error": {
    "code": "invalid_code",            // машиночитаемый
    "message": "Код неверный или устарел",  // человекочитаемый (можно показать пользователю)
    "details": { }                     // опц., напр. поля валидации
  }
}
```

| HTTP | code | Когда |
|---|---|---|
| 400 | `invalid_code` | Неверный OTP |
| 401 | `unauthorized` | Нет/протух access-токен |
| 401 | `invalid_refresh` | Refresh невалиден/отозван |
| 403 | `forbidden` | Нет прав (не организатор и т.п.) |
| 403 | `profile_incomplete` | Профиль не заполнен (нет имени/фото/«о себе») — действие запрещено |
| 404 | `not_found` | Объект не найден |
| 409 | `already_joined` / `event_full` / `event_closed` / `already_reviewed` | Конфликт состояния |
| 410 | `code_expired` | OTP протух |
| 422 | `validation_error` | Ошибки валидации тела (`details` — по полям) |
| 429 | `rate_limited` / `too_many_attempts` | Лимиты (есть `Retry-After`) |
| 500 | `internal_error` | Непредвиденная ошибка |

**Definition of Done (этап 11 / релиз):**
- [ ] Покрытие тестами: auth-цикл, CRUD событий, гео-лента, join/accept/waitlist, WS-чат, reviews.
- [ ] `/docs` (OpenAPI) соответствует этому файлу.
- [ ] `docker-compose -f docker-compose.prod.yml up` запускает прод-конфигурацию (Gunicorn+Uvicorn workers).
- [ ] Логи структурированы (JSON), есть `request_id`.
- [ ] README с командами запуска (см. ниже).

---

## 12. Команды (шпаргалка)

```bash
# Локальный запуск всего стека
docker-compose up --build

# Миграции
docker-compose exec api alembic revision --autogenerate -m "init"
docker-compose exec api alembic upgrade head

# Тесты
docker-compose exec api pytest -q

# Линт/типы
docker-compose exec api ruff check . && docker-compose exec api mypy app
```

---

## 13. Передача фронтендеру — чек-лист

Перед тем как отдать этот файл iOS-разработчику, убедись:
- [ ] Все пути из раздела 9 реально работают (проверено через `/docs` или Postman-коллекцию).
- [ ] Объекты ответов (`EventListItem`, `EventDetail`, `UserPublic` …) совпадают с кодом 1:1.
- [ ] WS-протокол (раздел 10) проверен реальным подключением.
- [ ] Коды ошибок (раздел 11) стабильны — фронт завязывается на `error.code`.
- [ ] Дан `base_url` дев-окружения и тестовый телефон/код (в dev OTP виден в логе).
- [ ] Приложена Postman/Insomnia-коллекция или ссылка на `/docs`.

> После этого фронтендер открывает [`frontend/ROADMAP.md`](../frontend/ROADMAP.md) и реализует клиент,
> сверяясь с разделами 9–11 этого документа как с контрактом.
