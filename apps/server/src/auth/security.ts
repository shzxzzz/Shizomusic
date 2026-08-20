import { createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import type { AuthPrincipal, OnboardingClaim } from "./models.js";

const accessLifetimeSeconds = 15 * 60;
export const refreshLifetimeMs = 30 * 24 * 60 * 60 * 1_000;

function secret(): string {
  return process.env.AUTH_SECRET ?? "development-only-change-me";
}

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function sign(encoded: string): string {
  return createHmac("sha256", secret()).update(encoded).digest("base64url");
}

function makeToken(payload: Record<string, unknown>): string {
  const header = encode({ alg: "HS256", typ: "JWT" });
  const body = encode(payload);
  return `${header}.${body}.${sign(`${header}.${body}`)}`;
}

function verifyToken(token: string): Record<string, unknown> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("invalid_token");
  const [header, body, signature] = parts as [string, string, string];
  const expected = sign(`${header}.${body}`);
  const left = Buffer.from(signature);
  const right = Buffer.from(expected);
  if (left.length !== right.length || !timingSafeEqual(left, right)) throw new Error("invalid_token");
  const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as Record<string, unknown>;
  if (typeof payload.exp !== "number" || payload.exp <= Math.floor(Date.now() / 1_000)) throw new Error("expired_token");
  return payload;
}

export function issueAccessToken(principal: AuthPrincipal): { token: string; expiresAt: Date } {
  const now = Math.floor(Date.now() / 1_000);
  const expiresAt = new Date((now + accessLifetimeSeconds) * 1_000);
  return {
    token: makeToken({ typ: "access", sub: principal.userId, did: principal.deviceId, role: principal.role, iat: now, exp: now + accessLifetimeSeconds, jti: randomUUID() }),
    expiresAt,
  };
}

export function verifyAccessToken(token: string): AuthPrincipal {
  const payload = verifyToken(token);
  if (payload.typ !== "access" || typeof payload.sub !== "string" || typeof payload.did !== "string" || (payload.role !== "owner" && payload.role !== "member")) {
    throw new Error("invalid_token");
  }
  return { userId: payload.sub, deviceId: payload.did, role: payload.role };
}

export function issueOnboardingToken(claim: OnboardingClaim): string {
  const now = Math.floor(Date.now() / 1_000);
  return makeToken({ typ: "onboarding", ...claim, iat: now, exp: now + 15 * 60 });
}

export function verifyOnboardingToken(token: string): OnboardingClaim {
  const payload = verifyToken(token);
  if (payload.typ !== "onboarding" || typeof payload.invitationId !== "string" || typeof payload.deviceIdentifier !== "string" || typeof payload.deviceName !== "string" || (payload.role !== "owner" && payload.role !== "member")) {
    throw new Error("invalid_token");
  }
  return { invitationId: payload.invitationId, deviceIdentifier: payload.deviceIdentifier, deviceName: payload.deviceName, role: payload.role };
}

export function randomRefreshToken(): string { return randomBytes(48).toString("base64url"); }
export function randomInvitationCode(): string { return randomBytes(6).toString("hex").toUpperCase(); }
export function hashToken(value: string): string { return createHash("sha256").update(value.trim()).digest("hex"); }
export function hashInvitationCode(value: string): string { return hashToken(value.toUpperCase()); }
