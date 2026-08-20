export class AuthError extends Error {
  constructor(
    readonly code: string,
    readonly statusCode: number,
    readonly messageKey: string,
  ) {
    super(code);
  }
}

export const invalidInvitation = () => new AuthError("invalid_invitation", 400, "auth.invitation_invalid");
export const expiredInvitation = () => new AuthError("expired_invitation", 410, "auth.invitation_expired");
export const invitationUsed = () => new AuthError("invitation_used", 409, "auth.invitation_used");
export const unauthorized = () => new AuthError("unauthorized", 401, "auth.unauthorized");
export const deviceRevoked = () => new AuthError("device_revoked", 401, "auth.device_revoked");
export const forbidden = () => new AuthError("forbidden", 403, "auth.forbidden");
