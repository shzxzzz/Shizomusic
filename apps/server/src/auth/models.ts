export type UserRole = "owner" | "member";

export interface PublicUser {
  id: string;
  displayName: string;
  avatarData: string | null;
  role: UserRole;
}

export interface PublicDevice {
  id: string;
  userId: string;
  name: string;
  createdAt: string;
  lastSeenAt: string;
  revokedAt: string | null;
}

export interface AuthPrincipal {
  userId: string;
  deviceId: string;
  role: UserRole;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: string;
  refreshExpiresAt: string;
}

export interface AuthSession extends AuthTokens {
  user: PublicUser;
  device: PublicDevice;
}

export interface OnboardingClaim {
  invitationId: string;
  deviceIdentifier: string;
  deviceName: string;
  role: UserRole;
}

export interface AuthStore {
  ensureBootstrapInvitation(code: string): Promise<void>;
  inspectInvitation(code: string): Promise<{ invitationId: string; role: UserRole }>;
  completeOnboarding(claim: OnboardingClaim, displayName: string, avatarData: string | null): Promise<AuthSession>;
  rotateRefreshToken(refreshToken: string): Promise<AuthSession>;
  validatePrincipal(principal: AuthPrincipal): Promise<PublicUser>;
  listDevices(owner: AuthPrincipal): Promise<PublicDevice[]>;
  createInvitation(owner: AuthPrincipal, expiresInHours: number): Promise<{ code: string; expiresAt: string }>;
  revokeDevice(owner: AuthPrincipal, deviceId: string): Promise<void>;
  revokeUser(owner: AuthPrincipal, userId: string): Promise<void>;
  logout(refreshToken: string): Promise<void>;
}
