import { asc, eq, gt } from "drizzle-orm";
import type { Database } from "../db/client.js";
import { syncChanges, syncConflicts, syncOperations, syncedPlaylistItems, syncedPlaylists } from "../db/schema.js";
import type { AuthPrincipal } from "../auth/models.js";
import type { ClientSyncOperation, SyncChange, SyncConflict, SyncPullResult, SyncPushResult, SyncStore } from "./models.js";

type Json = Record<string, unknown>;

export class DatabaseSyncStore implements SyncStore {
  constructor(private readonly db: Database) {}

  async push(principal: AuthPrincipal, operations: ClientSyncOperation[]): Promise<SyncPushResult> {
    const acceptedOperationIds: string[] = [];
    const conflicts: SyncConflict[] = [];
    let cursor = 0n;
    for (const operation of operations) {
      const result = await this.apply(principal, operation);
      acceptedOperationIds.push(operation.id);
      cursor = result.cursor > cursor ? result.cursor : cursor;
      if (result.conflict) conflicts.push(result.conflict);
    }
    if (cursor === 0n) cursor = await this.latestCursor();
    return { acceptedOperationIds, cursor: cursor.toString(), conflicts };
  }

  async pull(_principal: AuthPrincipal, cursor: bigint, limit: number): Promise<SyncPullResult> {
    const rows = await this.db.select().from(syncChanges)
      .where(gt(syncChanges.cursor, cursor)).orderBy(asc(syncChanges.cursor)).limit(limit + 1);
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    const changes: SyncChange[] = page.map((row) => ({
      id: row.operationId,
      cursor: row.cursor.toString(),
      actorDeviceId: row.actorDeviceId,
      entityType: row.entityType as SyncChange["entityType"],
      entityId: row.entityId,
      operationType: row.operationType as SyncChange["operationType"],
      payload: JSON.stringify(row.payload),
      clientTimestamp: row.createdAt.toISOString(),
    }));
    return { changes, cursor: (page.at(-1)?.cursor ?? cursor).toString(), hasMore };
  }

  private async apply(principal: AuthPrincipal, operation: ClientSyncOperation): Promise<{ cursor: bigint; conflict?: SyncConflict }> {
    return this.db.transaction(async (tx) => {
      const [existing] = await tx.select({ id: syncOperations.id }).from(syncOperations).where(eq(syncOperations.id, operation.id)).limit(1);
      if (existing) {
        const [change] = await tx.select().from(syncChanges).where(eq(syncChanges.operationId, operation.id)).limit(1);
        const [conflict] = await tx.select().from(syncConflicts).where(eq(syncConflicts.operationId, operation.id)).limit(1);
        return conflict
          ? { cursor: change?.cursor ?? 0n, conflict: mapConflict(conflict) }
          : { cursor: change?.cursor ?? 0n };
      }

      await tx.insert(syncOperations).values({
        id: operation.id,
        actorUserId: principal.userId,
        actorDeviceId: principal.deviceId,
        entityType: operation.entityType,
        entityId: operation.entityId,
        operationType: operation.operationType,
        payload: operation.payload,
        clientTimestamp: new Date(operation.clientTimestamp),
      });

      const outcome = operation.entityType === "playlist"
        ? await applyPlaylist(tx as unknown as Database, operation)
        : await applyPlaylistItem(tx as unknown as Database, operation);
      const [change] = await tx.insert(syncChanges).values({
        operationId: operation.id,
        actorDeviceId: principal.deviceId,
        entityType: operation.entityType,
        entityId: operation.entityId,
        operationType: outcome.operationType,
        payload: outcome.payload,
      }).returning({ cursor: syncChanges.cursor });
      const changeCursor = change?.cursor ?? 0n;

      if (operation.entityType === "playlist") {
        await tx.update(syncedPlaylists).set({ version: changeCursor }).where(eq(syncedPlaylists.id, operation.entityId));
      } else {
        await tx.update(syncedPlaylistItems).set({ version: changeCursor }).where(eq(syncedPlaylistItems.id, operation.entityId));
      }

      let conflict: SyncConflict | undefined;
      if (outcome.conflictReason) {
        const [record] = await tx.insert(syncConflicts).values({
          operationId: operation.id,
          entityType: operation.entityType,
          entityId: operation.entityId,
          reason: outcome.conflictReason,
          localPayload: operation.payload,
          serverPayload: outcome.payload,
        }).returning();
        if (record) conflict = mapConflict(record);
      }
      return conflict ? { cursor: changeCursor, conflict } : { cursor: changeCursor };
    });
  }

  private async latestCursor(): Promise<bigint> {
    const rows = await this.db.select({ cursor: syncChanges.cursor }).from(syncChanges).orderBy(asc(syncChanges.cursor));
    return rows.at(-1)?.cursor ?? 0n;
  }
}

interface ApplyOutcome { operationType: ClientSyncOperation["operationType"]; payload: Json; conflictReason?: string }

async function applyPlaylist(db: Database, operation: ClientSyncOperation): Promise<ApplyOutcome> {
  const [current] = await db.select().from(syncedPlaylists).where(eq(syncedPlaylists.id, operation.entityId)).limit(1);
  const incomingDate = dateValue(operation.payload.updatedAt, new Date(operation.clientTimestamp));
  const wins = !current || compareVersion(incomingDate, operation.id, current.updatedAt, current.lastOperationId) >= 0;
  if (wins) {
    const deletedAt = operation.operationType === "playlist.delete" ? incomingDate : null;
    const values = {
      id: operation.entityId,
      title: stringValue(operation.payload.title, current?.title ?? "Untitled"),
      coverStyle: stringValue(operation.payload.coverStyle, current?.coverStyle ?? "violet"),
      customCoverData: nullableString(operation.payload.customCoverData),
      createdAt: dateValue(operation.payload.createdAt, current?.createdAt ?? incomingDate),
      updatedAt: incomingDate,
      deletedAt,
      lastOperationId: operation.id,
    };
    await db.insert(syncedPlaylists).values(values).onConflictDoUpdate({ target: syncedPlaylists.id, set: values });
    return { operationType: operation.operationType, payload: playlistPayload(values) };
  }
  return {
    operationType: current.deletedAt ? "playlist.delete" : "playlist.upsert",
    payload: playlistPayload(current),
    conflictReason: "newer_server_playlist_version",
  };
}

async function applyPlaylistItem(db: Database, operation: ClientSyncOperation): Promise<ApplyOutcome> {
  const [current] = await db.select().from(syncedPlaylistItems).where(eq(syncedPlaylistItems.id, operation.entityId)).limit(1);
  const playlistId = stringValue(operation.payload.playlistId, current?.playlistId ?? "");
  const [parent] = playlistId ? await db.select().from(syncedPlaylists).where(eq(syncedPlaylists.id, playlistId)).limit(1) : [];
  const incomingDate = dateValue(operation.payload.updatedAt, new Date(operation.clientTimestamp));
  const wins = !current || compareVersion(incomingDate, operation.id, current.updatedAt, current.lastOperationId) >= 0;
  const parentDeleted = !parent || parent.deletedAt !== null;
  if (wins && !parentDeleted) {
    const deletedAt = operation.operationType === "playlistItem.remove" ? incomingDate : null;
    const values = {
      id: operation.entityId,
      playlistId,
      trackId: stringValue(operation.payload.trackId, current?.trackId ?? ""),
      rank: numberValue(operation.payload.rank, current?.rank ?? 1_024),
      createdAt: dateValue(operation.payload.createdAt, current?.createdAt ?? incomingDate),
      updatedAt: incomingDate,
      deletedAt,
      lastOperationId: operation.id,
    };
    await db.insert(syncedPlaylistItems).values(values).onConflictDoUpdate({ target: syncedPlaylistItems.id, set: values });
    return { operationType: operation.operationType, payload: playlistItemPayload(values) };
  }
  if (!current) {
    const tombstone = {
      id: operation.entityId, playlistId, trackId: stringValue(operation.payload.trackId, ""),
      rank: numberValue(operation.payload.rank, 1_024), createdAt: incomingDate, updatedAt: incomingDate,
      deletedAt: incomingDate, lastOperationId: operation.id,
    };
    await db.insert(syncedPlaylistItems).values(tombstone);
    return { operationType: "playlistItem.remove", payload: playlistItemPayload(tombstone), conflictReason: "parent_playlist_deleted" };
  }
  return {
    operationType: current.deletedAt ? "playlistItem.remove" : "playlistItem.move",
    payload: playlistItemPayload(current),
    conflictReason: parentDeleted ? "parent_playlist_deleted" : "newer_server_playlist_item_version",
  };
}

function compareVersion(leftDate: Date, leftId: string, rightDate: Date, rightId: string): number {
  const time = leftDate.getTime() - rightDate.getTime();
  return time === 0 ? leftId.localeCompare(rightId) : time;
}
function stringValue(value: unknown, fallback: string): string { return typeof value === "string" ? value : fallback; }
function nullableString(value: unknown): string | null { return typeof value === "string" ? value : null; }
function numberValue(value: unknown, fallback: number): number { return typeof value === "number" && Number.isFinite(value) ? value : fallback; }
function dateValue(value: unknown, fallback: Date): Date { return typeof value === "string" && Number.isFinite(Date.parse(value)) ? new Date(value) : fallback; }
function playlistPayload(value: typeof syncedPlaylists.$inferSelect | Omit<typeof syncedPlaylists.$inferInsert, "version">): Json {
  return { id: value.id, title: value.title, coverStyle: value.coverStyle, customCoverData: value.customCoverData ?? null,
    createdAt: value.createdAt.toISOString(), updatedAt: value.updatedAt.toISOString(), deletedAt: value.deletedAt?.toISOString() ?? null };
}
function playlistItemPayload(value: typeof syncedPlaylistItems.$inferSelect | Omit<typeof syncedPlaylistItems.$inferInsert, "version">): Json {
  return { id: value.id, playlistId: value.playlistId, trackId: value.trackId, rank: value.rank,
    createdAt: value.createdAt.toISOString(), updatedAt: value.updatedAt.toISOString(), deletedAt: value.deletedAt?.toISOString() ?? null };
}
function mapConflict(row: typeof syncConflicts.$inferSelect): SyncConflict {
  return { id: row.id, operationId: row.operationId, entityType: row.entityType as SyncConflict["entityType"], entityId: row.entityId,
    reason: row.reason, localPayload: JSON.stringify(row.localPayload), serverPayload: JSON.stringify(row.serverPayload), createdAt: row.createdAt.toISOString() };
}
