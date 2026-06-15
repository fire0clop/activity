# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Системные зависимости для сборки asyncpg/shapely/psycopg при необходимости
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-dev.txt ./
# Dev-образ: ставим и dev-зависимости (pytest, ruff). Для прод-образа — только requirements.txt.
RUN pip install -r requirements-dev.txt

COPY . .

# Каталог для медиа (монтируется volume'ом в compose)
RUN mkdir -p /app/media

EXPOSE 8000

# Для dev команда переопределяется в docker-compose (reload). Это дефолт для прода.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
