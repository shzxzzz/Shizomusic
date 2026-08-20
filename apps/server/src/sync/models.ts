import type { AuthPrincipal } from "../auth/models.js";

export type SyncEntityType = "playlist" | "playlistItem";
export type SyncOperationType = "playlist.upsert" | "playlist.delete" | "playlistItem.insert" | "playlistItem.move" | "playlistItem.remove";

export interface ClientSyncOperation {
  id: string;
  entityType: SyncEntityType;
  entityId: string;
  operationType: SyncOperationType;
  payload: Record<string, unknown>;
  clientTimestamp: string;
}

export interface SyncChange extends Omit<ClientSyncOperation, "payload"> {
  cursor: string;
  actorDeviceId: string;
  payload: string;
}

export interface SyncConflict {
  id: string;
  operationId: string;
  entityType: SyncEntityType;
  entityId: string;
  reason: string;
  localPayload: string;
  serverPayload: string;
  createdAt: string;
}

export interface SyncPushResult {
  acceptedOperationIds: string[];
  cursor: string;
  conflicts: SyncConflict[];
}

export interface SyncPullResult {
  changes: SyncChange[];
  cursor: string;
  hasMore: boolean;
}

export interface SyncStore {
  push(principal: AuthPrincipal, operations: ClientSyncOperation[]): Promise<SyncPushResult>;
  pull(principal: AuthPrincipal, cursor: bigint, limit: number): Promise<SyncPullResult>;
}

export function validateOperation(value: unknown): ClientSyncOperation {
  if (!value || typeof value !== "object") throw new Error("invalid_sync_operation");
  const operation = value as Record<string, unknown>;
  const entityTypes = new Set(["playlist", "playlistItem"]);
  const operationTypes = new Set(["playlist.upsert", "playlist.delete", "playlistItem.insert", "playlistItem.move", "playlistItem.remove"]);
  if (typeof operation.id !== "string" || typeof operation.entityId !== "string" ||
      typeof operation.entityType !== "string" || !entityTypes.has(operation.entityType) ||
      typeof operation.operationType !== "string" || !operationTypes.has(operation.operationType) ||
      typeof operation.clientTimestamp !== "string" || !Number.isFinite(Date.parse(operation.clientTimestamp))) {
    throw new Error("invalid_sync_operation");
  }
  let payload: unknown = operation.payload;
  if (typeof payload === "string") {
    try { payload = JSON.parse(payload); } catch { throw new Error("invalid_sync_operation"); }
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("invalid_sync_operation");
  return { ...(operation as unknown as ClientSyncOperation), payload: payload as Record<string, unknown> };
}
