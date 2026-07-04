#!/usr/bin/env bash
# Обновляет LAN-IP в приложении и бэкенде при смене Wi-Fi. Запуск: ./setip.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"

IP="$(ipconfig getifaddr en0 || true)"
[ -z "$IP" ] && IP="$(ipconfig getifaddr en1 || true)"
if [ -z "$IP" ]; then echo "Не удалось определить IP"; exit 1; fi
echo "Текущий IP: $IP"

# 1) Приложение — строка API_HOST для устройства в Dev.xcconfig
#    (строка API_HOST[sdk=iphonesimulator*] не трогается — симулятор остаётся на localhost)
sed -i '' "s#^API_HOST = .*#API_HOST = $IP:8080#" \
  "$ROOT/frontend/Skhodka/Configs/Dev.xcconfig"

# 2) Бэкенд (MEDIA_PUBLIC_URL в .env) + перезапуск
sed -i '' "s#^MEDIA_PUBLIC_URL=.*#MEDIA_PUBLIC_URL=http://$IP:8080/media#" "$ROOT/backend/.env"
( cd "$ROOT/backend" && docker compose up -d --force-recreate api >/dev/null 2>&1 )

echo "✅ IP обновлён в приложении и бэкенде, бэкенд перезапущен."
echo "➡️  Перезапусти приложение из Xcode на телефоне (Cmd+R), чтобы подхватить новый адрес."
