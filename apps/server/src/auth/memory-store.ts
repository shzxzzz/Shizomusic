import { randomUUID } from "node:crypto";
import { deviceRevoked, expiredInvitation, forbidden, invitationUsed, invalidInvitation, unauthorized } from "./errors.js";
import type { AuthPrincipal, AuthSession, AuthStore, OnboardingClaim, PublicDevice, PublicUser, UserRole } from "./models.js";
import { hashInvitationCode, hashToken, issueAccessToken, randomInvitationCode, randomRefreshToken, refreshLifetimeMs } from "./security.js";

interface MemoryInvitation {
  id: string;
  hash: string;
  role: UserRole;
  expiresAt: Date;
  used: boolean;
}

interface MemoryRefresh {
    hash: string;
    deviceId: string;
    familyId: string;
    expiresAt: Date;
    active: boolean;
}

export class MemoryAuthStore implements AuthStore {
  private readonly invitations = new Map<string, MemoryInvitation>();
  private readonly users = new Map<string, PublicUser & { revoked: boolean }>();
  private readonly devices = new Map<string, PublicDevice>();
  private readonly refresh = new Map<string, MemoryRefresh>();

  async ensureBootstrapInvitation(code: string): Promise<void> {
    const hash = hashInvitationCode(code);
    if (![...this.invitations.values()].some((invite) => invite.hash === hash)) {
      const invitation: MemoryInvitation = { id: randomUUID(), hash, role: "owner", expiresAt: new Date(Date.now() + 365 * 86_400_000), used: false };
      this.invitations.set(invitation.id, invitation);
    }
  }

  async inspectInvitation(code: string): Promise<{ invitationId: string; role: UserRole }> {
    const hash = hashInvitationCode(code);
    const invite = [...this.invitations.values()].find((value) => value.hash === hash);
    if (!invite) throw invalidInvitation();
    if (invite.used) throw invitationUsed();
    if (invite.expiresAt <= new Date()) throw expiredInvitation();
    return { invitationId: invite.id, role: invite.role };
  }

  async completeOnboarding(claim: OnboardingClaim, displayName: string, avatarData: string | null): Promise<AuthSession> {
    const invite = this.invitations.get(claim.invitationId);
    if (!invite) throw invalidInvitation();
    if (invite.used) throw invitationUsed();
    if (invite.expiresAt <= new Date()) throw expiredInvitation();
    invite.used = true;
    const user: PublicUser & { revoked: boolean } = { id: randomUUID(), displayName, avatarData, role: invite.role, revoked: false };
    const now = new Date().toISOString();
    const device: PublicDevice = {
      id: randomUUID(), userId: user.id, name: claim.deviceName, createdAt: now, lastSeenAt: now, revokedAt: null,
    };
    this.users.set(user.id, user);
    this.devices.set(device.id, device);
    return this.issueSession(user, device);
  }

  async rotateRefreshToken(refreshToken: string): Promise<AuthSession> {
    const hash = hashToken(refreshToken);
    const stored = this.refresh.get(hash);
    if (!stored || stored.expiresAt <= new Date()) throw unauthorized();
    if (!stored.active) {
      for (const token of this.refresh.values()) if (token.familyId === stored.familyId) token.active = false;
      throw unauthorized();
    }
    stored.active = false;
    const device = this.devices.get(stored.deviceId);
    if (!device || device.revokedAt) throw deviceRevoked();
    const user = this.users.get(device.userId);
    if (!user || user.revoked) throw deviceRevoked();
    return this.issueSession(user, device, stored.familyId);
  }

  async validatePrincipal(principal: AuthPrincipal): Promise<PublicUser> {
    const device = this.devices.get(principal.deviceId);
    const user = this.users.get(principal.userId);
    if (!device || device.revokedAt || !user || user.revoked || device.userId !== user.id) throw deviceRevoked();
    return user;
  }

  async listDevices(owner: AuthPrincipal): Promise<PublicDevice[]> {
    await this.requireOwner(owner);
    return [...this.devices.values()];
  }

  async createInvitation(owner: AuthPrincipal, expiresInHours: number): Promise<{ code: string; expiresAt: string }> {
    await this.requireOwner(owner);
    const code = randomInvitationCode();
    const expiresAt = new Date(Date.now() + Math.min(Math.max(expiresInHours, 1), 720) * 3_600_000);
    const invitation: MemoryInvitation = { id: randomUUID(), hash: hashInvitationCode(code), role: "member", expiresAt, used: false };
    this.invitations.set(invitation.id, invitation);
    return { code, expiresAt: expiresAt.toISOString() };
  }

  async revokeDevice(owner: AuthPrincipal, deviceId: string): Promise<void> {
    await this.requireOwner(owner);
    const device = this.devices.get(deviceId);
    if (device) this.devices.set(deviceId, { ...device, revokedAt: new Date().toISOString() });
    for (const token of this.refresh.values()) if (token.deviceId === deviceId) token.active = false;
  }

  async revokeUser(owner: AuthPrincipal, userId: string): Promise<void> {
    await this.requireOwner(owner);
    const user = this.users.get(userId);
    if (user) user.revoked = true;
    for (const device of this.devices.values()) if (device.userId === userId) await this.revokeDevice(owner, device.id);
  }

  async logout(refreshToken: string): Promise<void> {
    const stored = this.refresh.get(hashToken(refreshToken));
    if (stored) stored.active = false;
  }

  private async requireOwner(principal: AuthPrincipal): Promise<void> {
    const user = await this.validatePrincipal(principal);
    if (user.role !== "owner") throw forbidden();
  }

  private issueSession(user: PublicUser, device: PublicDevice, familyId: string = randomUUID()): AuthSession {
    const refreshToken = randomRefreshToken();
    const refreshExpiresAt = new Date(Date.now() + refreshLifetimeMs);
    this.refresh.set(hashToken(refreshToken), { hash: hashToken(refreshToken), deviceId: device.id, familyId, expiresAt: refreshExpiresAt, active: true });
    const access = issueAccessToken({ userId: user.id, deviceId: device.id, role: user.role });
    return {
      user, device, accessToken: access.token, refreshToken,
      accessExpiresAt: access.expiresAt.toISOString(), refreshExpiresAt: refreshExpiresAt.toISOString(),
    };
  }
}
