import { bigint, bigserial, doublePrecision, index, jsonb, pgEnum, pgTable, text, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";

export const userRole = pgEnum("user_role", ["owner", "member"]);

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  displayName: text("display_name").notNull(),
  avatarData: text("avatar_data"),
  role: userRole("role").notNull().default("member"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
});

export const devices = pgTable("devices", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  deviceIdentifier: text("device_identifier").notNull(),
  name: text("name").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).notNull().defaultNow(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
}, (table) => [
  uniqueIndex("devices_user_identifier_unique").on(table.userId, table.deviceIdentifier),
  index("devices_user_idx").on(table.userId),
]);

export const invitations = pgTable("invitations", {
  id: uuid("id").primaryKey().defaultRandom(),
  codeHash: text("code_hash").notNull(),
  role: userRole("role").notNull().default("member"),
  createdByUserId: uuid("created_by_user_id").references(() => users.id, { onDelete: "set null" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  consumedAt: timestamp("consumed_at", { withTimezone: true }),
  consumedByUserId: uuid("consumed_by_user_id").references(() => users.id, { onDelete: "set null" }),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
}, (table) => [uniqueIndex("invitations_code_hash_unique").on(table.codeHash)]);

export const refreshTokens = pgTable("refresh_tokens", {
  id: uuid("id").primaryKey().defaultRandom(),
  deviceId: uuid("device_id").notNull().references(() => devices.id, { onDelete: "cascade" }),
  familyId: uuid("family_id").notNull(),
  tokenHash: text("token_hash").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  rotatedAt: timestamp("rotated_at", { withTimezone: true }),
  replacedById: uuid("replaced_by_id"),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
}, (table) => [
  uniqueIndex("refresh_tokens_hash_unique").on(table.tokenHash),
  index("refresh_tokens_device_idx").on(table.deviceId),
  index("refresh_tokens_family_idx").on(table.familyId),
]);

export const syncedPlaylists = pgTable("synced_playlists", {
  id: uuid("id").primaryKey(),
  title: text("title").notNull(),
  coverStyle: text("cover_style").notNull(),
  customCoverData: text("custom_cover_data"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
  version: bigint("version", { mode: "bigint" }).notNull().default(0n),
  lastOperationId: uuid("last_operation_id").notNull(),
});

export const syncedPlaylistItems = pgTable("synced_playlist_items", {
  id: uuid("id").primaryKey(),
  playlistId: uuid("playlist_id").notNull(),
  trackId: text("track_id").notNull(),
  rank: doublePrecision("rank").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
  version: bigint("version", { mode: "bigint" }).notNull().default(0n),
  lastOperationId: uuid("last_operation_id").notNull(),
}, (table) => [index("synced_playlist_items_playlist_rank").on(table.playlistId, table.rank)]);

export const syncOperations = pgTable("sync_operations", {
  id: uuid("id").primaryKey(),
  actorUserId: uuid("actor_user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  actorDeviceId: uuid("actor_device_id").notNull().references(() => devices.id, { onDelete: "cascade" }),
  entityType: text("entity_type").notNull(),
  entityId: text("entity_id").notNull(),
  operationType: text("operation_type").notNull(),
  payload: jsonb("payload").notNull(),
  clientTimestamp: timestamp("client_timestamp", { withTimezone: true }).notNull(),
  receivedAt: timestamp("received_at", { withTimezone: true }).notNull().defaultNow(),
});

export const syncChanges = pgTable("sync_changes", {
  cursor: bigserial("cursor", { mode: "bigint" }).primaryKey(),
  operationId: uuid("operation_id").notNull().references(() => syncOperations.id, { onDelete: "cascade" }),
  actorDeviceId: uuid("actor_device_id").notNull(),
  entityType: text("entity_type").notNull(),
  entityId: text("entity_id").notNull(),
  operationType: text("operation_type").notNull(),
  payload: jsonb("payload").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("sync_changes_cursor_idx").on(table.cursor)]);

export const syncConflicts = pgTable("sync_conflicts", {
  id: uuid("id").primaryKey().defaultRandom(),
  operationId: uuid("operation_id").notNull().references(() => syncOperations.id, { onDelete: "cascade" }),
  entityType: text("entity_type").notNull(),
  entityId: text("entity_id").notNull(),
  reason: text("reason").notNull(),
  localPayload: jsonb("local_payload").notNull(),
  serverPayload: jsonb("server_payload").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("sync_conflicts_operation_idx").on(table.operationId)]);
