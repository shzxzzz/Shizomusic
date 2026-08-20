import { randomUUID } from "node:crypto";
import type { AuthPrincipal } from "../auth/models.js";
import type { ClientSyncOperation, SyncChange, SyncConflict, SyncPullResult, SyncPushResult, SyncStore } from "./models.js";

interface Canonical { payload: Record<string, unknown>; operationType: ClientSyncOperation["operationType"]; updatedAt: string; operationId: string }

export class MemorySyncStore implements SyncStore {
  private readonly operations = new Set<string>();
  private readonly changes: SyncChange[] = [];
  private readonly entities = new Map<string, Canonical>();
  private readonly conflicts = new Map<string, SyncConflict>();

  async push(principal: AuthPrincipal, operations: ClientSyncOperation[]): Promise<SyncPushResult> {
    for (const operation of operations) {
      if (this.operations.has(operation.id)) continue;
      this.operations.add(operation.id);
      const key = `${operation.entityType}:${operation.entityId}`;
      const current = this.entities.get(key);
      const updatedAt = typeof operation.payload.updatedAt === "string" ? operation.payload.updatedAt : operation.clientTimestamp;
      const wins = !current || compare(updatedAt, operation.id, current.updatedAt, current.operationId) >= 0;
      let canonical: Canonical;
      if (wins) {
        canonical = { payload: { ...operation.payload }, operationType: operation.operationType, updatedAt, operationId: operation.id };
        this.entities.set(key, canonical);
      } else {
        canonical = current;
        this.conflicts.set(operation.id, {
          id: randomUUID(), operationId: operation.id, entityType: operation.entityType, entityId: operation.entityId,
          reason: "newer_server_version", localPayload: JSON.stringify(operation.payload), serverPayload: JSON.stringify(current.payload), createdAt: new Date().toISOString(),
        });
      }
      this.changes.push({ ...operation, cursor: String(this.changes.length + 1), actorDeviceId: principal.deviceId,
        operationType: canonical.operationType, payload: JSON.stringify(canonical.payload) });
    }
    return {
      acceptedOperationIds: operations.map((operation) => operation.id),
      cursor: String(this.changes.length),
      conflicts: operations.flatMap((operation) => this.conflicts.get(operation.id) ?? []),
    };
  }

  async pull(_principal: AuthPrincipal, cursor: bigint, limit: number): Promise<SyncPullResult> {
    const start = Number(cursor);
    const changes = this.changes.slice(start, start + limit);
    return { changes, cursor: changes.at(-1)?.cursor ?? cursor.toString(), hasMore: start + limit < this.changes.length };
  }
}

function compare(leftDate: string, leftId: string, rightDate: string, rightId: string): number {
  const time = Date.parse(leftDate) - Date.parse(rightDate);
  return time === 0 ? leftId.localeCompare(rightId) : time;
}
