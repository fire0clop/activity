# Frontend Roadmap — «Сходка» (iOS, Swift / SwiftUI)

> Этот файл — план реализации мобильного клиента под iOS с чекпоинтами.
> **Контракт API — в [`backend/ROADMAP.md`](../backend/ROADMAP.md), разделы 9–11.**
> Этот документ ссылается на него; не дублируй контракт здесь — если бэк изменится,
> правится один источник правды (файл бэкенда).

---

## 0. Как пользоваться

- Чекбоксы `- [ ]` → `- [x]` по мере готовности.
- Порядок этапов = порядок реализации; верхние этапы — фундамент для нижних.
- Перед каждым сетевым экраном открывай соответствующий эндпоинт в backend-роадмапе и сверяй поля.
- «Definition of Done» в конце этапа — критерий закрытия.

**Глобальный прогресс:**
- [x] Этап 1. Каркас проекта, архитектура, зависимости
- [x] Этап 2. Сетевой слой + модели (DTO под контракт бэка)
- [x] Этап 3. Аутентификация по телефону (OTP) + хранение токенов
- [x] Этап 4. Профиль (свой и чужой) + **обязательный онбординг: фото и «о себе»**
- [x] Этап 5. Лента событий: список + карта + фильтры (**в ленте — только день, точное время скрыто**)
- [x] Этап 6. Карточка события и создание события (точное время появляется после подтверждения)
- [x] Этап 7. Заявки и управление участниками (организатор решает, кого пускать)
- [x] Этап 8. Чат на «беседах» (WebSocket) + вкладка «Чаты»
- [x] Этап 9. Отзывы и рейтинг
- [x] Этап 10. Push-уведомления (APNs/FCM)
- [x] Этап 11. Жалобы/блокировки, полировка, релизная готовность
- [x] Этап 12 (V2). Самостоятельные групповые чаты (мессенджер для устоявшихся компаний)

---

## 1. Технологический стек

| Компонент | Выбор | Зачем |
|---|---|---|
| Язык | Swift 5.9+ | — |
| UI | SwiftUI (iOS 16+) | Декларативный UI, быстрый старт |
| Архитектура | MVVM + Coordinator (или `NavigationStack`-роутинг) | Тестируемость, разделение слоёв |
| Сеть | `URLSession` + `async/await` | Без лишних зависимостей |
| WebSocket | `URLSessionWebSocketTask` | Чат |
| DI | Простой контейнер / инициализация через init | Без тяжёлых фреймворков |
| Хранилище токенов | Keychain (обёртка) | Безопасно |
| Локальный кеш | `UserDefaults` (флаги) + опц. файловый кеш | — |
| Карта | MapKit (`Map` в SwiftUI) | Пины событий, нативно |
| Геолокация | CoreLocation | Точка пользователя для ленты |
| Изображения | `AsyncImage` (+ кеш) или Kingfisher | Обложки/аватары |
| Push | APNs через Firebase Cloud Messaging SDK | Совпадает с бэком (FCM) |
| Тесты | XCTest | Unit + ViewModel-тесты |

> Концепт допускал React Native/Flutter, но по требованию клиент **нативный iOS на Swift/SwiftUI**.

---

## 2. Структура проекта

```
frontend/
└── Skhodka/                          # Xcode project
    ├── Skhodka.xcodeproj
    ├── SkhodkaApp.swift              # @main, точка входа, выбор корневого экрана
    ├── Config/
    │   ├── AppConfig.swift           # baseURL, wsURL, среды (dev/prod)
    │   └── Secrets.xcconfig          # ключи (не в git)
    ├── Core/
    │   ├── Networking/
    │   │   ├── APIClient.swift       # generic-запросы, авто-Bearer, рефреш токена
    │   │   ├── Endpoint.swift        # описание путей/методов
    │   │   ├── APIError.swift        # маппинг error.code из бэка
    │   │   └── WebSocketClient.swift # чат
    │   ├── Auth/
    │   │   ├── TokenStore.swift      # Keychain: access/refresh
    │   │   └── AuthManager.swift     # состояние сессии (signedIn/out)
    │   ├── Location/LocationManager.swift
    │   └── Extensions/               # Date+ISO8601, View+ и т.п.
    ├── Models/                       # DTO под контракт бэка (Codable)
    │   ├── User.swift                # UserPublic / UserPrivate
    │   ├── Event.swift               # EventListItem / EventDetail
    │   ├── Participation.swift
    │   ├── Conversation.swift         # ConversationListItem / ConversationDetail
    │   ├── Message.swift
    │   └── Review.swift
    ├── Features/                     # по экранам: View + ViewModel
    │   ├── Auth/                      # PhoneInput, CodeInput
    │   ├── Onboarding/                # обязательное заполнение профиля (имя+фото+bio)
    │   ├── Profile/
    │   ├── Feed/                      # FeedList, FeedMap, Filters
    │   ├── EventDetail/
    │   ├── EventCreate/
    │   ├── Participants/
    │   ├── Chats/                     # ChatsList (вкладка), ChatView
    │   ├── Groups/                    # V2: создание/управление группами
    │   └── Reviews/
    ├── DesignSystem/                 # цвета, шрифты, переиспользуемые компоненты
    │   ├── Theme.swift
    │   └── Components/                # PrimaryButton, Avatar, RatingView, EventCard...
    └── Resources/
        ├── Assets.xcassets
        └── Localizable.strings        # ru (+ en при необходимости)
```

**Definition of Done (этап 1):**
- [ ] Проект собирается и запускается на симуляторе iOS 16+.
- [ ] `AppConfig` хранит `baseURL`/`wsURL` для dev и prod.
- [ ] Базовый `NavigationStack`-роутинг между заглушками экранов.
- [ ] DesignSystem: тема (цвета/шрифты) и `PrimaryButton`.

---

## 3. Этап 2 — Сетевой слой и модели

Реализуй DTO **строго по объектам из backend-роадмапа** (раздел 9): `UserPublic`, `UserPrivate`,
`EventListItem`, `EventDetail`, `Participation`, `Message`, `Review`. Все `Codable`.

### Требования к `APIClient`
- Async-методы: `get/post/patch/delete<T: Decodable>(...)`.
- Автоматически добавляет `Authorization: Bearer <access>`.
- При `401 unauthorized` — один раз дёргает `POST /auth/refresh`, повторяет запрос; при неудаче — `AuthManager.signOut()`.
- Декодит даты как ISO8601 UTC (кастомный `JSONDecoder.dateDecodingStrategy`).
- Ошибки маппит в `APIError` по полю `error.code` (раздел 11 бэка) → enum, чтобы UI показывал понятный текст.

### Чекпоинты
- [ ] `Endpoint` + `APIClient` (generic, async/await).
- [ ] `APIError` с разбором `{ error: { code, message, details } }`.
- [ ] Все Codable-модели заведены и покрыты unit-тестом декодинга (по примерам JSON из бэка).
- [ ] Cursor-пагинация: хелпер, хранящий `next_cursor`.

**Definition of Done:** декодинг примеров из backend-роадмапа проходит в тестах без ошибок.

---

## 4. Этап 3 — Аутентификация (OTP)

Эндпоинты: `POST /auth/request-code`, `POST /auth/verify-code`, `POST /auth/refresh`, `POST /auth/logout`
(см. backend §9.2). В dev-режиме код приходит в лог бэка — спроси у бэкендера тестовый номер.

### Экраны
1. **PhoneInputView** — ввод телефона (маска E.164), кнопка «Получить код».
2. **CodeInputView** — 6 цифр, авто-сабмит, таймер повторной отправки (`resend_after_sec`).
3. После `verify-code`: сохранить токены в Keychain; если `is_new_user == true` **или** `profile_completed == false`
   (из `GET /users/me`) → **обязательный онбординг профиля** (имя + фото + «о себе»), иначе → лента.
   Онбординг нельзя пропустить: пока бэк возвращает `profile_completed == false`, действия (создать/откликнуться/чат)
   будут отдавать `403 profile_incomplete`.

### Чекпоинты
- [ ] `TokenStore` (Keychain) — сохранение/чтение/очистка access+refresh.
- [ ] `AuthManager` с `@Published var state: .unknown/.signedOut/.signedIn`.
- [ ] Корневой свитч в `SkhodkaApp` по состоянию сессии.
- [ ] Обработка ошибок: `invalid_code`, `code_expired`, `too_many_attempts`, `rate_limited` (показ Retry-After).
- [ ] Логаут чистит Keychain и зовёт `/auth/logout`.

**Definition of Done:** полный цикл вход→лента→перезапуск приложения (сессия восстановлена)→логаут.

---

## 5. Этап 4 — Профиль

Эндпоинты: `GET /users/me`, `PATCH /users/me`, `POST /users/me/avatar`, `GET /users/{id}` (backend §9.3).

### Чекпоинты
- [ ] **OnboardingProfileView** (обязательный, после первого входа): имя + загрузка фото + «о себе».
      Кнопка «Готово» активна только когда все три поля заполнены; экран нельзя закрыть свайпом.
- [ ] **MyProfileView**: имя, аватар, bio, рейтинг (звёзды), счётчики `events_created/attended`, «в приложении с …».
- [ ] **EditProfileView**: имя, bio, дата рождения, пол; сохранение через `PATCH`.
- [ ] Загрузка аватара (`PHPicker` → multipart `POST /users/me/avatar`); показ загруженного по `avatar_url`.
- [ ] **PublicProfileView**: открывается из карточки события/чата/списка участников (`GET /users/{id}`) —
      организатор смотрит фото и «о себе» откликнувшегося, чтобы решить, пускать ли. Кнопки «Пожаловаться»/«Заблокировать».
- [ ] Глобальная обработка `403 profile_incomplete`: перехват в `APIClient` → показать онбординг профиля.
- [ ] `RatingView` (компонент звёзд) в DesignSystem.

---

## 6. Этап 5 — Лента: список, карта, фильтры

Эндпоинт: `GET /events` с гео-параметрами и фильтрами (backend §9.4). Перед запросом получи координаты
через `LocationManager` (запрос разрешения «When In Use»); при отказе — дефолтный город/ручной выбор точки.

### Экраны
- **FeedView** с переключателем **Список ↔ Карта**.
  - Список: `EventCard` (обложка, заголовок, **день** `day`, расстояние, X/Y участников, цена, рейтинг организатора).
    ⚠️ Точное время в ленте **не показываем**: бэк присылает `starts_at: null` и `time_disclosed: false`,
    рендерим только `day` («Сб, 21 июня») + место. Это намеренно — незваные не знают времени сбора.
  - Карта: `Map` (MapKit) с пинами по `latitude/longitude`; тап по пину → превью → карточка.
- **FiltersView / быстрые чипы**: «Сегодня», «Завтра», «На выходных» (`when=`), радиус (`radius_km`),
  категория (`category`), поиск по тексту (`query`).
- Пагинация по `next_cursor` (бесконечный скролл), pull-to-refresh.

### Чекпоинты
- [ ] `LocationManager` (CoreLocation, async-обёртка за разрешением).
- [ ] `FeedViewModel`: загрузка, фильтры, пагинация, состояние пустой ленты (важно для холодного старта — показать понятный empty-state и CTA «Создать событие»).
- [ ] Список + карта на одних данных, переключение без перезагрузки.
- [ ] Компонент `EventCard`.

**Definition of Done:** лента грузит реальные события рядом, фильтры и поиск меняют выдачу, карта и список синхронны.

---

## 7. Этап 6 — Карточка и создание события

Эндпоинты: `GET /events/{id}`, `POST /events`, `PATCH/DELETE /events/{id}`, `POST /events/{id}/cover` (backend §9.4).

### EventDetailView
- [ ] Полная карточка: обложка, описание, **день**, место (мини-карта + адрес), цена/сплит, участники, организатор.
- [ ] **Время:** если `time_disclosed == true` (ты организатор/accepted) — показать точное `starts_at`/`ends_at`;
      иначе — только `day` и подпись «Точное время станет известно после подтверждения участия».
- [ ] Кнопка действия зависит от `my_participation.status` и `is_organizer`:
      «Откликнуться» / «Заявка отправлена» / «Вы участвуете» / «Управлять» (организатор).
- [ ] Переход в чат по `conversation_id`, если `chat_available == true`.

### EventCreateView
- [ ] Форма по телам `POST /events`: заголовок, описание, категория, дата/время (DatePicker),
      выбор точки на карте + адрес, min/max участников, цена + способ деления, авто-приём, обложка.
- [ ] Клиентская валидация (время в будущем, max≥min) — но полагаться на серверный `422 validation_error`.
- [ ] Загрузка обложки после создания (`POST /events/{id}/cover`).
- [ ] Редактирование/отмена для организатора.

---

## 8. Этап 7 — Заявки и участники

Эндпоинты: `POST/DELETE /events/{id}/join`, `GET /events/{id}/participants`,
`POST /participations/{id}/accept|reject` (backend §9.5).

### Чекпоинты
- [ ] Кнопка «Откликнуться» → обработка статусов `pending|accepted|waitlisted` и конфликтов
      `already_joined|event_full|event_closed`.
- [ ] «Выйти/отозвать заявку» (`DELETE …/join`).
- [ ] **ParticipantsView** (для организатора): список `pending` с профилем+рейтингом, кнопки Принять/Отклонить.
- [ ] Для участника — список `accepted` (кто идёт).
- [ ] Обновление UI после решений (и/или через push).

---

## 9. Этап 8 — Чат на «беседах» (WebSocket) + вкладка «Чаты»

Протокол — backend §10. Один WS обслуживает любую беседу (event-чат и группу) по `conversation_id`:
`WS /api/v1/ws/chat/{conversation_id}?token=<access>`. Для события `conversation_id` берётся из
`EventDetail.conversation_id`. Список бесед и история — backend §9.9.

### Чекпоинты
- [ ] **ChatsListView** (отдельная вкладка таб-бара): `GET /conversations` — список бесед (event + group)
      с превью последнего сообщения и счётчиком непрочитанных; pull-to-refresh, пагинация.
- [ ] `WebSocketClient` на `URLSessionWebSocketTask`: connect/receive-loop/send/reconnect (по `conversation_id`).
- [ ] Обработка входящих `type`: `history`, `message`, `system`, `presence`, `error`.
- [ ] Отправка `{ "type":"message", "text":... }`; опц. `typing`/`read`.
- [ ] **ChatView**: лента сообщений (свои/чужие/системные), закреп с деталями события (системное сообщение);
      для accepted-участника здесь же отображается раскрытое точное время.
- [ ] REST-фолбэк истории при открытии: `GET /conversations/{id}/messages` (пагинация вверх).
- [ ] Реконнект при обрыве и при возврате приложения из фона; обновление access-токена перед reconnect.
- [ ] Read-only режим, если беседа `is_archived` (событие `finished`).

**Definition of Done:** два устройства/симулятора обмениваются сообщениями в реальном времени; список чатов
и история подгружаются; чат события открывается из карточки и из вкладки «Чаты».

---

## 10. Этап 9 — Отзывы и рейтинг

Эндпоинты: `POST /events/{id}/reviews`, `GET /users/{id}/reviews` (backend §9.6).

### Чекпоинты
- [ ] После события (`status=finished`) — экран «Оцените участников/организатора» (двусторонние отзывы).
- [ ] Отправка `rating (1–5) + comment` на каждого target; обработка `already_reviewed`.
- [ ] Список отзывов на публичном профиле.

---

## 11. Этап 10 — Push-уведомления

Бэк шлёт через FCM (backend §9.8, этап 10). Клиент регистрирует токен: `POST /devices { token, platform:"ios" }`.

### Чекпоинты
- [ ] Подключить Firebase Messaging SDK, настроить APNs-ключ в Apple Developer.
- [ ] Запрос разрешения на уведомления, получение FCM-токена, отправка на `POST /devices`.
- [ ] Удаление токена при логауте (`DELETE /devices/{token}`).
- [ ] Обработка типов пушей и deep-link: новая заявка → ParticipantsView; решение по заявке → EventDetail;
      сообщение в чате → ChatView; освобождение места из waitlist → EventDetail; напоминание о событии.
- [ ] Бейджи/баннеры в foreground.

---

## 12. Этап 11 — Жалобы, блокировки, полировка, релиз

Эндпоинты жалоб/блокировок — backend §9.7.

### Чекпоинты
- [ ] Жалоба на пользователя/событие (`POST /reports`) — экран с выбором `reason`.
- [ ] Блокировка/разблокировка (`POST/DELETE /users/{id}/block`).
- [ ] Состояния загрузки/ошибки/пустоты на всех экранах (единый компонент).
- [ ] Доступность: Dynamic Type, VoiceProver-лейблы на ключевых элементах, контраст.
- [ ] Локализация строк (ru как минимум).
- [ ] App Icon, Launch Screen, онбординг (1–3 экрана про идею приложения).
- [ ] Privacy: описания использования геолокации, фото, уведомлений в `Info.plist`.
- [ ] Сборка Release-конфигурации, прогон на реальном устройстве.

---

## 12.1 Этап 12 (V2) — Самостоятельные групповые чаты

Мессенджер-режим: устоявшаяся компания пишет напрямую, без привязки к событию. Использует те же
`ChatsListView`/`ChatView`/`WebSocketClient`, что и event-чат — добавляются только создание и управление
составом (backend §9.9, эндпоинты `/conversations/*`).

### Чекпоинты
- [ ] **CreateGroupView**: имя группы + выбор участников (из контактов приложения/прошлых со-участников) →
      `POST /conversations`. Опция «создать из события» (предзаполнить `accepted`-участниками, `from_event_id`).
- [ ] **GroupInfoView**: список участников, добавить (`POST …/members`) / удалить (`DELETE …/members/{user_id}`),
      переименовать (`PATCH /conversations/{id}`), «Выйти из группы» (`POST …/leave`).
- [ ] Различать в `ChatsListView` беседы `type=event` и `type=group` (иконка/бейдж).
- [ ] Роли: действия управления составом доступны только при `my_role == "owner"`.

**Definition of Done:** можно создать группу из произвольных пользователей и переписываться в ней так же,
как в чате события.

---

## 13. Зависимость от бэкенда — чек-лист интеграции

Перед началом сетевых этапов получи от бэкендера (см. их §13 «Передача фронтендеру»):
- [ ] `base_url` и `ws_url` дев-окружения → внести в `AppConfig`.
- [ ] Тестовый телефон и где смотреть OTP-код в dev.
- [ ] Подтверждение, что объекты ответов в коде совпадают с разделом 9 backend-роадмапа.
- [ ] Postman/Insomnia-коллекция или доступ к `/docs` (Swagger).
- [ ] Перечень `error.code` (backend §11) — на них завязана обработка ошибок в `APIError`.

> Единый источник правды по API — **`backend/ROADMAP.md` §9–11**. При расхождении кода и документа —
> сначала сверься с бэкендером, не «угадывай» поля.
