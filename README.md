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

Кроме health-checks сервер предоставляет приглашения, onboarding, access/refresh tokens и отзыв устройств. PostgreSQL-схема и миграции управляются Drizzle. После первого запуска код владельца берётся из `OWNER_INVITE_CODE`.

Для тестов: `cd apps/server; npm install; npm test`. OpenAPI-контракт находится в `contracts/openapi.yaml`, соответствующий Swift-клиент — в `apps/ios/Sources/Domain/GeneratedAPIClient.swift`.

## iOS

На Mac сгенерируйте Xcode-проект из `apps/ios/project.yml` через XcodeGen и добавьте GRDB 7.x в Swift Package Manager. Сборка и Ad Hoc-подпись выполняются на Mac.

UI читает локальные repositories: медиатека, очередь, плейлисты и статистика сохраняются в SQLite и остаются доступны без сети. Refresh token хранится в Keychain.
