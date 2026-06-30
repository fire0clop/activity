PGUSER ?= skhodka
TEST_DB ?= skhodka_test
TEST_DATABASE_URL = postgresql+asyncpg://$(PGUSER):skhodka@db:5432/$(TEST_DB)

.PHONY: up down logs build rebuild migrate makemigration test lint fmt seed shell s3-up

up:            ## Поднять dev-стек
	docker compose up -d

down:          ## Остановить стек
	docker compose down

logs:          ## Логи api
	docker compose logs -f api

build:
	docker compose build

rebuild:
	docker compose up -d --build

migrate:       ## Применить миграции
	docker compose exec api alembic upgrade head

makemigration: ## Создать миграцию: make makemigration m="описание"
	docker compose exec api alembic revision --autogenerate -m "$(m)"

seed:          ## Тестовые данные
	docker compose exec api python -m app.seed

test:          ## Прогнать тесты на изолированной БД skhodka_test + Redis db1
	@docker compose exec -T db psql -U $(PGUSER) -d skhodka -tc \
		"SELECT 1 FROM pg_database WHERE datname='$(TEST_DB)'" | grep -q 1 || \
		docker compose exec -T db psql -U $(PGUSER) -d skhodka -c "CREATE DATABASE $(TEST_DB)"
	docker compose exec -T \
		-e DATABASE_URL="$(TEST_DATABASE_URL)" \
		-e DB_NULLPOOL=true \
		-e RATE_LIMIT_ENABLED=false \
		-e REDIS_URL="redis://redis:6379/1" \
		-e SMS_PROVIDER=stub \
		api pytest -q

lint:
	docker compose exec api ruff check . && docker compose exec api mypy app

fmt:
	docker compose exec api ruff check --fix . && docker compose exec api black .

s3-up:         ## Поднять MinIO (S3-режим): затем STORAGE_BACKEND=s3
	MINIO_PORT=9100 MINIO_CONSOLE_PORT=9101 docker compose --profile s3 up -d minio

shell:
	docker compose exec api bash
