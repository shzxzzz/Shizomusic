import { and, eq, gt, isNull } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import type { Database } from "../db/client.js";
import { devices, invitations, refreshTokens, users } from "../db/schema.js";
import { deviceRevoked, expiredInvitation, forbidden, invitationUsed, invalidInvitation, unauthorized } from "./errors.js";
import type { AuthPrincipal, AuthSession, AuthStore, OnboardingClaim, PublicDevice, PublicUser, UserRole } from "./models.js";
import { hashInvitationCode, hashToken, issueAccessToken, randomInvitationCode, randomRefreshToken, refreshLifetimeMs } from "./security.js";

export class DatabaseAuthStore implements AuthStore {
  constructor(private readonly db: Database) {}

  async ensureBootstrapInvitation(code: string): Promise<void> {
    const codeHash = hashInvitationCode(code);
    await this.db.insert(invitations).values({
      codeHash,
      role: "owner",
      expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1_000),
    }).onConflictDoNothing({ target: invitations.codeHash });
  }

  async inspectInvitation(code: string): Promise<{ invitationId: string; role: UserRole }> {
    const [invite] = await this.db.select().from(invitations).where(eq(invitations.codeHash, hashInvitationCode(code))).limit(1);
    if (!invite || invite.revokedAt) throw invalidInvitation();
    if (invite.consumedAt) throw invitationUsed();
    if (invite.expiresAt <= new Date()) throw expiredInvitation();
    return { invitationId: invite.id, role: invite.role };
  }

  async completeOnboarding(claim: OnboardingClaim, displayName: string, avatarData: string | null): Promise<AuthSession> {
    const result = await this.db.transaction(async (tx) => {
      const [invite] = await tx.select().from(invitations).where(eq(invitations.id, claim.invitationId)).for("update").limit(1);
      if (!invite || invite.revokedAt) throw invalidInvitation();
      if (invite.consumedAt) throw invitationUsed();
      if (invite.expiresAt <= new Date()) throw expiredInvitation();
      if (invite.role !== claim.role) throw invalidInvitation();

      const [user] = await tx.insert(users).values({ displayName, avatarData, role: claim.role }).returning();
      if (!user) throw unauthorized();
      const [device] = await tx.insert(devices).values({
        userId: user.id,
        deviceIdentifier: claim.deviceIdentifier,
        name: claim.deviceName,
      }).returning();
      if (!device) throw unauthorized();
      await tx.update(invitations).set({ consumedAt: new Date(), consumedByUserId: user.id }).where(eq(invitations.id, invite.id));
      return { user, device };
    });
    return this.issueSession(this.publicUser(result.user), this.publicDevice(result.device));
  }

  async rotateRefreshToken(refreshToken: string): Promise<AuthSession> {
    const tokenHash = hashToken(refreshToken);
    const result = await this.db.transaction(async (tx) => {
      const [stored] = await tx.select().from(refreshTokens).where(eq(refreshTokens.tokenHash, tokenHash)).for("update").limit(1);
      if (!stored || stored.revokedAt || stored.expiresAt <= new Date()) throw unauthorized();
      if (stored.rotatedAt) {
        return { kind: "replay" as const, familyId: stored.familyId };
      }
      const [device] = await tx.select().from(devices).where(eq(devices.id, stored.deviceId)).limit(1);
      if (!device || device.revokedAt) throw deviceRevoked();
      const [user] = await tx.select().from(users).where(eq(users.id, device.userId)).limit(1);
      if (!user || user.revokedAt) throw deviceRevoked();

      const nextToken = randomRefreshToken();
      const nextExpiresAt = new Date(Date.now() + refreshLifetimeMs);
      const [next] = await tx.insert(refreshTokens).values({
        deviceId: device.id,
        familyId: stored.familyId,
        tokenHash: hashToken(nextToken),
        expiresAt: nextExpiresAt,
      }).returning();
      if (!next) throw unauthorized();
      await tx.update(refreshTokens).set({ rotatedAt: new Date(), replacedById: next.id }).where(eq(refreshTokens.id, stored.id));
      await tx.update(devices).set({ lastSeenAt: new Date() }).where(eq(devices.id, device.id));
      return { kind: "session" as const, user: this.publicUser(user), device: this.publicDevice(device), refreshToken: nextToken, refreshExpiresAt: nextExpiresAt };
    });
    if (result.kind === "replay") {
      await this.db.update(refreshTokens).set({ revokedAt: new Date() }).where(eq(refreshTokens.familyId, result.familyId));
      throw unauthorized();
    }
    return this.completeSession(result.user, result.device, result.refreshToken, result.refreshExpiresAt);
  }

  async validatePrincipal(principal: AuthPrincipal): Promise<PublicUser> {
    const [device] = await this.db.select().from(devices).where(and(eq(devices.id, principal.deviceId), eq(devices.userId, principal.userId))).limit(1);
    if (!device || device.revokedAt) throw deviceRevoked();
    const [user] = await this.db.select().from(users).where(eq(users.id, principal.userId)).limit(1);
    if (!user || user.revokedAt) throw deviceRevoked();
    await this.db.update(devices).set({ lastSeenAt: new Date() }).where(eq(devices.id, device.id));
    return this.publicUser(user);
  }

  async listDevices(owner: AuthPrincipal): Promise<PublicDevice[]> {
    await this.requireOwner(owner);
    const rows = await this.db.select().from(devices);
    return rows.map((row) => this.publicDevice(row));
  }

  async createInvitation(owner: AuthPrincipal, expiresInHours: number): Promise<{ code: string; expiresAt: string }> {
    await this.requireOwner(owner);
    const code = randomInvitationCode();
    const expiresAt = new Date(Date.now() + Math.min(Math.max(expiresInHours, 1), 720) * 60 * 60 * 1_000);
    await this.db.insert(invitations).values({ codeHash: hashInvitationCode(code), role: "member", createdByUserId: owner.userId, expiresAt });
    return { code, expiresAt: expiresAt.toISOString() };
  }

  async revokeDevice(owner: AuthPrincipal, deviceId: string): Promise<void> {
    await this.requireOwner(owner);
    const now = new Date();
    await this.db.update(devices).set({ revokedAt: now }).where(eq(devices.id, deviceId));
    await this.db.update(refreshTokens).set({ revokedAt: now }).where(and(eq(refreshTokens.deviceId, deviceId), isNull(refreshTokens.revokedAt)));
  }

  async revokeUser(owner: AuthPrincipal, userId: string): Promise<void> {
    await this.requireOwner(owner);
    const now = new Date();
    await this.db.update(users).set({ revokedAt: now }).where(eq(users.id, userId));
    const userDevices = await this.db.select({ id: devices.id }).from(devices).where(eq(devices.userId, userId));
    for (const device of userDevices) await this.revokeDevice(owner, device.id);
  }

  async logout(refreshToken: string): Promise<void> {
    await this.db.update(refreshTokens).set({ revokedAt: new Date() }).where(eq(refreshTokens.tokenHash, hashToken(refreshToken)));
  }

  private async requireOwner(principal: AuthPrincipal): Promise<void> {
    const user = await this.validatePrincipal(principal);
    if (user.role !== "owner") throw forbidden();
  }

  private async issueSession(user: PublicUser, device: PublicDevice): Promise<AuthSession> {
    const refreshToken = randomRefreshToken();
    const refreshExpiresAt = new Date(Date.now() + refreshLifetimeMs);
    await this.db.insert(refreshTokens).values({
      deviceId: device.id,
      familyId: randomUUID(),
      tokenHash: hashToken(refreshToken),
      expiresAt: refreshExpiresAt,
    });
    return this.completeSession(user, device, refreshToken, refreshExpiresAt);
  }

  private completeSession(user: PublicUser, device: PublicDevice, refreshToken: string, refreshExpiresAt: Date): AuthSession {
    const access = issueAccessToken({ userId: user.id, deviceId: device.id, role: user.role });
    return {
      user,
      device,
      accessToken: access.token,
      refreshToken,
      accessExpiresAt: access.expiresAt.toISOString(),
      refreshExpiresAt: refreshExpiresAt.toISOString(),
    };
  }

  private publicUser(row: typeof users.$inferSelect): PublicUser {
    return { id: row.id, displayName: row.displayName, avatarData: row.avatarData, role: row.role };
  }

  private publicDevice(row: typeof devices.$inferSelect): PublicDevice {
    return {
      id: row.id,
      userId: row.userId,
      name: row.name,
      createdAt: row.createdAt.toISOString(),
      lastSeenAt: row.lastSeenAt.toISOString(),
      revokedAt: row.revokedAt?.toISOString() ?? null,
    };
  }
}
