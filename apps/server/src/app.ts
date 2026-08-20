import cors from "@fastify/cors";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { AuthError, unauthorized } from "./auth/errors.js";
import { MemoryAuthStore } from "./auth/memory-store.js";
import type { AuthPrincipal, AuthStore } from "./auth/models.js";
import { issueOnboardingToken, verifyAccessToken, verifyOnboardingToken } from "./auth/security.js";

interface BuildAppOptions {
  authStore?: AuthStore;
  readiness?: () => Promise<void>;
  bootstrapInvitationCode?: string;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new AuthError("invalid_request", 400, `validation.${field}`);
  }
  return value.trim();
}

export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({ logger: true, requestIdHeader: "x-request-id" });
  const authStore = options.authStore ?? new MemoryAuthStore();
  const bootstrapCode = options.bootstrapInvitationCode ?? process.env.OWNER_INVITE_CODE ?? "OWNER-DEVELOPMENT";

  app.register(cors, { origin: false });
  app.addHook("onReady", async () => { await authStore.ensureBootstrapInvitation(bootstrapCode); });
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);
    const statusCode = error instanceof AuthError
      ? error.statusCode
      : typeof error === "object" && error !== null && "statusCode" in error && typeof error.statusCode === "number"
        ? error.statusCode
        : 500;
    const code = error instanceof AuthError ? error.code : "internal_error";
    const messageKey = error instanceof AuthError ? error.messageKey : "error.internal";
    return reply.status(statusCode).send({ code, messageKey, requestID: request.id });
  });

  async function principal(request: FastifyRequest): Promise<AuthPrincipal> {
    const authorization = request.headers.authorization;
    if (!authorization?.startsWith("Bearer ")) throw unauthorized();
    try {
      const value = verifyAccessToken(authorization.slice(7));
      await authStore.validatePrincipal(value);
      return value;
    } catch (error) {
      if (error instanceof AuthError) throw error;
      throw unauthorized();
    }
  }

  app.get("/health", async () => ({ status: "ok" }));
  app.get("/ready", async () => {
    await options.readiness?.();
    return { status: "ready" };
  });

  app.post("/auth/invitations/redeem", async (request) => {
    const body = request.body as Record<string, unknown>;
    const code = requiredString(body.code, "code");
    const deviceIdentifier = requiredString(body.deviceIdentifier, "deviceIdentifier");
    const deviceName = requiredString(body.deviceName, "deviceName");
    const invite = await authStore.inspectInvitation(code);
    return {
      onboardingToken: issueOnboardingToken({ invitationId: invite.invitationId, role: invite.role, deviceIdentifier, deviceName }),
      expiresInSeconds: 900,
    };
  });

  app.post("/auth/onboarding/complete", async (request) => {
    const body = request.body as Record<string, unknown>;
    const onboardingToken = requiredString(body.onboardingToken, "onboardingToken");
    const displayName = requiredString(body.displayName, "displayName").slice(0, 80);
    const avatarData = typeof body.avatarData === "string" && body.avatarData.length <= 2_800_000 ? body.avatarData : null;
    try {
      return await authStore.completeOnboarding(verifyOnboardingToken(onboardingToken), displayName, avatarData);
    } catch (error) {
      if (error instanceof AuthError) throw error;
      throw unauthorized();
    }
  });

  app.post("/auth/refresh", async (request) => {
    const body = request.body as Record<string, unknown>;
    return authStore.rotateRefreshToken(requiredString(body.refreshToken, "refreshToken"));
  });

  app.post("/auth/logout", async (request, reply) => {
    const body = request.body as Record<string, unknown>;
    await authStore.logout(requiredString(body.refreshToken, "refreshToken"));
    return reply.status(204).send();
  });

  app.get("/me", async (request) => authStore.validatePrincipal(await principal(request)));
  app.get("/admin/devices", async (request) => authStore.listDevices(await principal(request)));
  app.post("/admin/invitations", async (request) => {
    const body = request.body as Record<string, unknown>;
    const hours = typeof body.expiresInHours === "number" ? body.expiresInHours : 72;
    return authStore.createInvitation(await principal(request), hours);
  });
  app.post("/admin/devices/:deviceId/revoke", async (request, reply) => {
    const params = request.params as { deviceId: string };
    await authStore.revokeDevice(await principal(request), params.deviceId);
    return reply.status(204).send();
  });
  app.post("/admin/users/:userId/revoke", async (request, reply) => {
    const params = request.params as { userId: string };
    await authStore.revokeUser(await principal(request), params.userId);
    return reply.status(204).send();
  });

  return app;
}
