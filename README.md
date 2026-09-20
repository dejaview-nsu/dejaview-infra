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
