# dejaview-infra

Локальное окружение, CI и развёртывание.

## Зона ответственности

- `docker-compose`: PostgreSQL, Qdrant, backend, ML-сервис, frontend одной командой
- Отдельный профиль запуска только инфраструктуры, без приложений
- CI: сборка, тесты и проверки стиля на каждый Pull Request
- Валидация `dejaview-docs/api/openapi.yaml` в CI
- Окружения dev и prod, управление секретами
- Развёртывание на рабочем сервере, мониторинг и логирование

## Стек

- Docker, docker-compose
- GitHub Actions
- clang-format для C++, ESLint с Prettier для frontend, ruff или black для Python

## Ссылки

- Задачи и требования: https://ai.nsu.ru/projects/dejaview
- Архитектура, контракты, соглашения: https://github.com/dejaview-nsu/dejaview-docs
- Организация: https://github.com/dejaview-nsu

## Как работаем

- Ветка от `main`: `feat/<номер задачи>-<кратко>`, нейминг в `conventions.md`
- Изменения через Pull Request с ревью, прямой push в `main` закрыт
- Ревьюер назначается автоматически по CODEOWNERS
- Время трекается в Redmine, в задачу, а не в требование

## Docker Compose

Основная конфигурация локального окружения находится в `compose.yaml`.
Все основные параметры имеют значения по умолчанию; при необходимости их можно
переопределить через `.env` на основе `.env.example`.

Для запуска только инфраструктуры:

```bash
docker compose --profile infra up -d
```

Для запуска инфраструктуры и приложения:

```bash
docker compose --profile infra --profile app up -d
```

Перед запуском backend миграции PostgreSQL автоматически применяются через
`dbmate`. Для этого репозитории `dejaview-infra` и `dejaview-backend` должны
находиться рядом в одной директории.

Для запуска полного стека вместе с ML-сервисом:

```bash
docker compose --profile infra --profile app --profile ml up -d
```

ML-сервис требует NVIDIA GPU с настроенной поддержкой GPU в Docker.

Остановить окружение:

```bash
docker compose down
```

Посмотреть логи всех сервисов:

```bash
docker compose logs -f
```

Посмотреть логи отдельного сервиса:

```bash
docker compose logs -f backend
```

Данные PostgreSQL, Qdrant и MinIO хранятся в Docker volumes и сохраняются после
обычного `docker compose down`.