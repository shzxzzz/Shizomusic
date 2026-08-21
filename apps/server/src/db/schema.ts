import { bigint, bigserial, doublePrecision, index, integer, jsonb, pgEnum, pgTable, text, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

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
  version: bigint("version", { mode: "bigint" }).notNull().default(sql`0`),
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
  version: bigint("version", { mode: "bigint" }).notNull().default(sql`0`),
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

export const catalogFiles = pgTable("catalog_files", {
  id: uuid("id").primaryKey().defaultRandom(),
  contentHash: text("content_hash").notNull().unique(),
  byteSize: bigint("byte_size", { mode: "bigint" }).notNull(),
  mimeType: text("mime_type").notNull(),
  storageKey: text("storage_key").notNull().unique(),
  originalFilename: text("original_filename").notNull(),
  status: text("status").notNull().default("processing"),
  title: text("title"),
  artist: text("artist"),
  album: text("album"),
  albumArtist: text("album_artist"),
  duration: doublePrecision("duration"),
  format: text("format"),
  codec: text("codec"),
  artworkStorageKey: text("artwork_storage_key"),
  artworkMimeType: text("artwork_mime_type"),
  probeError: text("probe_error"),
  addedByUserId: uuid("added_by_user_id").notNull().references(() => users.id),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("catalog_files_status_created_idx").on(table.status, table.createdAt)]);

export const uploadSessions = pgTable("upload_sessions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  deviceId: uuid("device_id").notNull().references(() => devices.id, { onDelete: "cascade" }),
  expectedHash: text("expected_hash").notNull(),
  expectedSize: bigint("expected_size", { mode: "bigint" }).notNull(),
  mimeType: text("mime_type").notNull(),
  filename: text("filename").notNull(),
  partSize: integer("part_size").notNull(),
  totalParts: integer("total_parts").notNull(),
  state: text("state").notNull().default("uploading"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  completedAt: timestamp("completed_at", { withTimezone: true }),
}, (table) => [index("upload_sessions_user_state_idx").on(table.userId, table.state)]);

export const uploadParts = pgTable("upload_parts", {
  id: uuid("id").primaryKey().defaultRandom(),
  uploadId: uuid("upload_id").notNull().references(() => uploadSessions.id, { onDelete: "cascade" }),
  partNumber: integer("part_number").notNull(),
  byteSize: bigint("byte_size", { mode: "bigint" }).notNull(),
  sha256: text("sha256").notNull(),
  storagePath: text("storage_path").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [uniqueIndex("upload_parts_upload_number_unique").on(table.uploadId, table.partNumber)]);

export const mediaJobs = pgTable("media_jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  catalogFileId: uuid("catalog_file_id").notNull().references(() => catalogFiles.id, { onDelete: "cascade" }),
  state: text("state").notNull().default("pending"),
  attemptCount: integer("attempt_count").notNull().default(0),
  nextAttemptAt: timestamp("next_attempt_at", { withTimezone: true }).notNull().defaultNow(),
  lastError: text("last_error"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("media_jobs_ready_idx").on(table.state, table.nextAttemptAt)]);

export const providerSearchTracks = pgTable("provider_search_tracks", {
  id: uuid("id").primaryKey().defaultRandom(),
  provider: text("provider").notNull(),
  externalId: text("external_id").notNull(),
  entityType: text("entity_type").notNull().default("track"),
  title: text("title").notNull(),
  artist: text("artist").notNull(),
  album: text("album"),
  duration: doublePrecision("duration").notNull().default(0),
  artworkUrl: text("artwork_url"),
  webpageUrl: text("webpage_url"),
  streamPath: text("stream_path"),
  canonicalUrl: text("canonical_url"),
  metadataProvider: text("metadata_provider").notNull().default("catalog"),
  audioProvider: text("audio_provider"),
  acquisitionMethod: text("acquisition_method").notNull().default("unavailable"),
  capabilities: jsonb("capabilities").notNull(),
  attribution: text("attribution"),
  lastQuery: text("last_query").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("provider_search_tracks_provider_entity_external_unique").on(table.provider, table.entityType, table.externalId),
  index("provider_search_tracks_query_idx").on(table.lastQuery, table.updatedAt),
]);

export const acquisitionJobs = pgTable("acquisition_jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  deviceId: uuid("device_id").notNull().references(() => devices.id, { onDelete: "cascade" }),
  provider: text("provider").notNull(),
  entityType: text("entity_type").notNull(),
  externalId: text("external_id").notNull(),
  canonicalUrl: text("canonical_url"),
  method: text("method").notNull(),
  title: text("title").notNull(),
  artist: text("artist"),
  artworkUrl: text("artwork_url"),
  state: text("state").notNull().default("queued"),
  progress: doublePrecision("progress").notNull().default(0),
  attemptCount: integer("attempt_count").notNull().default(0),
  maxAttempts: integer("max_attempts").notNull().default(3),
  nextAttemptAt: timestamp("next_attempt_at", { withTimezone: true }).notNull().defaultNow(),
  errorCode: text("error_code"),
  errorDetail: text("error_detail"),
  temporaryDirectory: text("temporary_directory"),
  catalogFileId: uuid("catalog_file_id").references(() => catalogFiles.id, { onDelete: "set null" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  completedAt: timestamp("completed_at", { withTimezone: true }),
}, (table) => [
  index("acquisition_jobs_ready_idx").on(table.state, table.nextAttemptAt),
  index("acquisition_jobs_user_created_idx").on(table.userId, table.createdAt),
]);

export const acquisitionExternalReferences = pgTable("acquisition_external_references", {
  provider: text("provider").notNull(),
  entityType: text("entity_type").notNull(),
  externalId: text("external_id").notNull(),
  catalogFileId: uuid("catalog_file_id").notNull().references(() => catalogFiles.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [uniqueIndex("acquisition_external_reference_unique").on(table.provider, table.entityType, table.externalId)]);
