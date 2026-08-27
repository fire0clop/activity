# Страницы на event-serv.ru

Две страницы, без которых приложение не опубликовать: адрес поддержки и политика
конфиденциальности — обязательные поля в App Store Connect.

Веб-версии продукта на домене нет и не планируется: наружу отдаются только эти
страницы, файл связки с приложением и переход на событие по ссылке.

| Файл | Адрес |
|---|---|
| `support.html` | https://event-serv.ru/support |
| `privacy.html` | https://event-serv.ru/privacy |

Форма поддержки шлёт `POST /api/v1/support` на тот же домен — так обходимся без
CORS. Обращения складываются в таблицу `support_tickets` и дублируются в лог.

Посмотреть необработанные обращения:

```
docker exec -e PGPASSWORD=$POSTGRES_PASSWORD backend-db-1 \
  psql -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT created_at, contact, message FROM support_tickets WHERE NOT is_handled ORDER BY created_at DESC;"
```

Разложены в `/opt/activity/web`, отдаёт Caddy — рабочий конфиг лежит рядом
в `Caddyfile`.
