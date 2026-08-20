import { describe, expect, test } from "vitest";
import { buildApp } from "../src/app.js";

interface SessionResponse {
  accessToken: string;
  refreshToken: string;
  user: { id: string };
  device: { id: string };
}

describe("invitation authentication", () => {
  test("owner invites two users, refresh rotates, and device access can be revoked", async () => {
    const app = buildApp({ bootstrapInvitationCode: "OWNER-CODE" });
    await app.ready();

    const owner = await onboard(app, "OWNER-CODE", "owner-phone", "Owner");
    const firstInvitation = await createInvitation(app, owner.accessToken);
    const secondInvitation = await createInvitation(app, owner.accessToken);
    const first = await onboard(app, firstInvitation.code, "member-one-phone", "Member One");
    const second = await onboard(app, secondInvitation.code, "member-two-phone", "Member Two");

    const reused = await app.inject({
      method: "POST",
      url: "/auth/invitations/redeem",
      payload: { code: firstInvitation.code, deviceIdentifier: "another", deviceName: "Another" },
    });
    expect(reused.statusCode).toBe(409);

    const rotated = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: second.refreshToken } });
    expect(rotated.statusCode).toBe(200);
    const rotatedSession = rotated.json<SessionResponse>();
    expect(rotatedSession.refreshToken).not.toBe(second.refreshToken);
    const replay = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: second.refreshToken } });
    expect(replay.statusCode).toBe(401);
    const familyRevoked = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: rotatedSession.refreshToken } });
    expect(familyRevoked.statusCode).toBe(401);

    const devices = await app.inject({ method: "GET", url: "/admin/devices", headers: bearer(owner.accessToken) });
    expect(devices.statusCode).toBe(200);
    expect(devices.json<unknown[]>()).toHaveLength(3);

    const revoke = await app.inject({
      method: "POST",
      url: `/admin/devices/${first.device.id}/revoke`,
      headers: bearer(owner.accessToken),
    });
    expect(revoke.statusCode).toBe(204);
    const revokedMe = await app.inject({ method: "GET", url: "/me", headers: bearer(first.accessToken) });
    expect(revokedMe.statusCode).toBe(401);
    expect(revokedMe.json<{ code: string }>().code).toBe("device_revoked");

    await app.close();
  });
});

async function onboard(
  app: ReturnType<typeof buildApp>,
  code: string,
  deviceIdentifier: string,
  displayName: string,
): Promise<SessionResponse> {
  const redeem = await app.inject({
    method: "POST",
    url: "/auth/invitations/redeem",
    payload: { code, deviceIdentifier, deviceName: `${displayName}'s iPhone` },
  });
  expect(redeem.statusCode).toBe(200);
  const onboardingToken = redeem.json<{ onboardingToken: string }>().onboardingToken;
  const complete = await app.inject({
    method: "POST",
    url: "/auth/onboarding/complete",
    payload: { onboardingToken, displayName, avatarData: null },
  });
  expect(complete.statusCode).toBe(200);
  return complete.json<SessionResponse>();
}

async function createInvitation(app: ReturnType<typeof buildApp>, accessToken: string): Promise<{ code: string }> {
  const response = await app.inject({
    method: "POST",
    url: "/admin/invitations",
    headers: bearer(accessToken),
    payload: { expiresInHours: 24 },
  });
  expect(response.statusCode).toBe(200);
  return response.json<{ code: string }>();
}

function bearer(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}
