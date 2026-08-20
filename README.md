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

## Простые команды владельца

После запуска Docker Compose управление доступом не требует ручных HTTP-запросов:

```powershell
# Создать одноразовое приглашение на 72 часа
docker compose --env-file infra/.env -f infra/docker-compose.yml exec api npm run invite -- --hours 72

# Показать пользователей и устройства
docker compose --env-file infra/.env -f infra/docker-compose.yml exec api npm run devices

# Отозвать устройство или пользователя
docker compose --env-file infra/.env -f infra/docker-compose.yml exec api npm run revoke-device -- <device-uuid>
docker compose --env-file infra/.env -f infra/docker-compose.yml exec api npm run revoke-user -- <user-uuid>
```

Без Docker команды ещё короче: `npm run invite -- --hours 72`, `npm run devices`, `npm run revoke-device -- <uuid>` и `npm run revoke-user -- <uuid>`. Требуется `DATABASE_URL`.

## iOS

На Mac сгенерируйте Xcode-проект из `apps/ios/project.yml` через XcodeGen и добавьте GRDB 7.x в Swift Package Manager. Сборка и Ad Hoc-подпись выполняются на Mac.

UI читает локальные repositories: медиатека, очередь, плейлисты и статистика сохраняются в SQLite и остаются доступны без сети. Изменения плейлистов атомарно попадают в outbox и автоматически синхронизируются пакетами после восстановления сети. Refresh token хранится в Keychain.
