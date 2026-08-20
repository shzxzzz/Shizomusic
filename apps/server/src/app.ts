import cors from "@fastify/cors";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { AuthError, unauthorized } from "./auth/errors.js";
import { MemoryAuthStore } from "./auth/memory-store.js";
import type { AuthPrincipal, AuthStore } from "./auth/models.js";
import { issueOnboardingToken, verifyAccessToken, verifyOnboardingToken } from "./auth/security.js";
import { MemorySyncStore } from "./sync/memory-store.js";
import { validateOperation, type SyncStore } from "./sync/models.js";
import { MemoryCatalogStore } from "./catalog/memory-store.js";
import { registerCatalogRoutes } from "./catalog/routes.js";
import type { CatalogStore } from "./catalog/models.js";

interface BuildAppOptions {
  authStore?: AuthStore;
  readiness?: () => Promise<void>;
  bootstrapInvitationCode?: string;
  syncStore?: SyncStore;
  catalogStore?: CatalogStore;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new AuthError("invalid_request", 400, `validation.${field}`);
  }
  return value.trim();
}

export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({ logger: true, requestIdHeader: "x-request-id", bodyLimit: 32_000_000 });
  const authStore = options.authStore ?? new MemoryAuthStore();
  const bootstrapCode = options.bootstrapInvitationCode ?? process.env.OWNER_INVITE_CODE ?? "OWNER-DEVELOPMENT";
  const syncStore = options.syncStore ?? new MemorySyncStore();
  const catalogStore = options.catalogStore ?? new MemoryCatalogStore();

  app.register(cors, { origin: false });
  app.addContentTypeParser("application/octet-stream", { parseAs: "buffer" }, (_request, body, done) => done(null, body));
  app.addHook("onReady", async () => { await authStore.ensureBootstrapInvitation(bootstrapCode); });
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);
    const statusCode = error instanceof AuthError
      ? error.statusCode
      : typeof error === "object" && error !== null && "statusCode" in error && typeof error.statusCode === "number"
        ? error.statusCode
        : 500;
    const structured = error as { code?: unknown; messageKey?: unknown };
    const code = error instanceof AuthError ? error.code : typeof structured.code === "string" ? structured.code : "internal_error";
    const messageKey = error instanceof AuthError ? error.messageKey : typeof structured.messageKey === "string" ? structured.messageKey : "error.internal";
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

  app.post("/sync/push", async (request) => {
    const actor = await principal(request);
    const body = request.body as { operations?: unknown[] } | undefined;
    if (!Array.isArray(body?.operations) || body.operations.length > 100) {
      throw new AuthError("invalid_sync_batch", 400, "sync.invalid_batch");
    }
    try {
      return await syncStore.push(actor, body.operations.map(validateOperation));
    } catch (error) {
      if (error instanceof AuthError) throw error;
      throw new AuthError("invalid_sync_operation", 400, "sync.invalid_operation");
    }
  });

  app.get("/sync/pull", async (request) => {
    const actor = await principal(request);
    const query = request.query as { cursor?: string; limit?: string };
    let cursor: bigint;
    try { cursor = BigInt(query.cursor ?? "0"); }
    catch { throw new AuthError("invalid_cursor", 400, "sync.invalid_cursor"); }
    if (cursor < 0n) throw new AuthError("invalid_cursor", 400, "sync.invalid_cursor");
    const requestedLimit = Number(query.limit ?? 200);
    const limit = Number.isInteger(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 500) : 200;
    return syncStore.pull(actor, cursor, limit);
  });

  registerCatalogRoutes(app, catalogStore, principal);

  return app;
}
