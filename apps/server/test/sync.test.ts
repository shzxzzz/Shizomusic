import { randomUUID } from "node:crypto";
import { describe, expect, test } from "vitest";
import { buildApp } from "../src/app.js";

interface Session { accessToken: string; user: { id: string }; device: { id: string } }

describe("offline synchronization", () => {
  test("two devices converge, operations are idempotent, and stale writes are diagnosable", async () => {
    const app = buildApp({ bootstrapInvitationCode: "OWNER-SYNC" });
    await app.ready();
    const first = await onboard(app, "OWNER-SYNC", "sync-owner", "Owner");
    const invitation = await app.inject({ method: "POST", url: "/admin/invitations", headers: bearer(first.accessToken), payload: { expiresInHours: 24 } });
    const second = await onboard(app, invitation.json<{ code: string }>().code, "sync-member", "Member");

    const playlistId = randomUUID();
    const itemId = randomUUID();
    const create = operation("playlist", playlistId, "playlist.upsert", {
      id: playlistId, title: "Shared", coverStyle: "violet", customCoverData: null,
      createdAt: "2026-08-20T10:00:00.000Z", updatedAt: "2026-08-20T10:00:00.000Z", deletedAt: null,
    }, "2026-08-20T10:00:00.000Z");
    const insert = operation("playlistItem", itemId, "playlistItem.insert", {
      id: itemId, playlistId, trackId: "same-content-hash", rank: 1024,
      createdAt: "2026-08-20T10:01:00.000Z", updatedAt: "2026-08-20T10:01:00.000Z", deletedAt: null,
    }, "2026-08-20T10:01:00.000Z");
    const initial = await push(app, first.accessToken, [create, insert]);
    expect(initial.acceptedOperationIds).toEqual([create.id, insert.id]);

    const newerRename = operation("playlist", playlistId, "playlist.upsert", {
      ...JSON.parse(create.payload), title: "Winner", updatedAt: "2026-08-20T12:00:00.000Z",
    }, "2026-08-20T12:00:00.000Z");
    const staleRename = operation("playlist", playlistId, "playlist.upsert", {
      ...JSON.parse(create.payload), title: "Stale", updatedAt: "2026-08-20T11:00:00.000Z",
    }, "2026-08-20T11:00:00.000Z");
    await push(app, first.accessToken, [newerRename]);
    const stale = await push(app, second.accessToken, [staleRename]);
    expect(stale.conflicts).toHaveLength(1);
    expect(JSON.parse(stale.conflicts[0]!.serverPayload).title).toBe("Winner");

    const remove = operation("playlistItem", itemId, "playlistItem.remove", {
      ...JSON.parse(insert.payload), updatedAt: "2026-08-20T13:00:00.000Z", deletedAt: "2026-08-20T13:00:00.000Z",
    }, "2026-08-20T13:00:00.000Z");
    const removed = await push(app, second.accessToken, [remove]);
    const duplicate = await push(app, second.accessToken, [remove]);
    expect(duplicate.cursor).toBe(removed.cursor);

    const firstPull = await pull(app, first.accessToken, "0");
    const secondPull = await pull(app, second.accessToken, "0");
    expect(canonical(firstPull.changes)).toEqual(canonical(secondPull.changes));
    expect(canonical(firstPull.changes).get(`playlist:${playlistId}`)?.title).toBe("Winner");
    expect(canonical(firstPull.changes).get(`playlistItem:${itemId}`)?.deletedAt).not.toBeNull();
    await app.close();
  });
});

function operation(entityType: string, entityId: string, operationType: string, payload: Record<string, unknown>, clientTimestamp: string) {
  return { id: randomUUID(), entityType, entityId, operationType, payload: JSON.stringify(payload), clientTimestamp };
}
async function push(app: ReturnType<typeof buildApp>, token: string, operations: unknown[]) {
  const response = await app.inject({ method: "POST", url: "/sync/push", headers: bearer(token), payload: { operations } });
  expect(response.statusCode).toBe(200);
  return response.json<{ acceptedOperationIds: string[]; cursor: string; conflicts: Array<{ serverPayload: string }> }>();
}
async function pull(app: ReturnType<typeof buildApp>, token: string, cursor: string) {
  const response = await app.inject({ method: "GET", url: `/sync/pull?cursor=${cursor}`, headers: bearer(token) });
  expect(response.statusCode).toBe(200);
  return response.json<{ changes: Array<{ entityType: string; entityId: string; payload: string }> }>();
}
function canonical(changes: Array<{ entityType: string; entityId: string; payload: string }>): Map<string, Record<string, unknown>> {
  return new Map(changes.map((change) => [`${change.entityType}:${change.entityId}`, JSON.parse(change.payload) as Record<string, unknown>]));
}
async function onboard(app: ReturnType<typeof buildApp>, code: string, identifier: string, name: string): Promise<Session> {
  const redeem = await app.inject({ method: "POST", url: "/auth/invitations/redeem", payload: { code, deviceIdentifier: identifier, deviceName: `${name} iPhone` } });
  const onboardingToken = redeem.json<{ onboardingToken: string }>().onboardingToken;
  const response = await app.inject({ method: "POST", url: "/auth/onboarding/complete", payload: { onboardingToken, displayName: name } });
  expect(response.statusCode).toBe(200);
  return response.json<Session>();
}
function bearer(token: string) { return { authorization: `Bearer ${token}` }; }
