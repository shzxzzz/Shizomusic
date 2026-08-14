# ShizoMusic

Закрытый offline-first музыкальный плеер для iPhone. Архитектурные решения определены в `CONCEPT.md`.

## Состав

- `apps/ios` — SwiftUI-клиент iOS 17+.
- `apps/server` — Fastify API и worker.
- `contracts` — OpenAPI 3.1 и realtime-схемы.
- `infra` — Docker Compose и окружение.

## Запуск сервера

Требуются Node.js 24 LTS и Docker Desktop.

```powershell
Copy-Item infra/.env.example infra/.env
docker compose --env-file infra/.env -f infra/docker-compose.yml up --build
```

Доступны `GET /health` и `GET /ready` на порту 3000. Для тестов: `cd apps/server; npm install; npm test`.

## iOS

На Mac сгенерируйте Xcode-проект из `apps/ios/project.yml` через XcodeGen и добавьте GRDB 7.x в Swift Package Manager. Сборка и Ad Hoc-подпись выполняются на Mac.

UI читает локальные repositories: любое синхронизируемое изменение фиксирует доменные данные и outbox-операцию в одной SQLite-транзакции.
