import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AuthPrincipal } from "../auth/models.js";
import { AuthError } from "../auth/errors.js";
import { MusicProviderError } from "./models.js";
import type { MusicSearchService } from "./service.js";

export function registerSearchRoutes(
  app: FastifyInstance,
  service: MusicSearchService,
  principal: (request: FastifyRequest) => Promise<AuthPrincipal>,
): void {
  app.get("/search", async (request) => {
    await principal(request);
    const query = request.query as { q?: string; limit?: string; provider?: string };
    const q = query.q?.trim() ?? "";
    if (q.length < 1 || q.length > 200) throw new AuthError("invalid_search_query", 400, "search.invalid_query");
    const parsed = Number(query.limit ?? 30);
    const limit = Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), 50) : 30;
    return service.search(q, limit, query.provider);
  });

  app.post("/search/providers/:provider/retry", async (request) => {
    await principal(request);
    const params = request.params as { provider: string };
    const body = request.body as { query?: unknown; limit?: unknown };
    if (typeof body.query !== "string" || body.query.trim().length === 0) throw new AuthError("invalid_search_query", 400, "search.invalid_query");
    const limit = typeof body.limit === "number" ? Math.min(Math.max(Math.trunc(body.limit), 1), 50) : 30;
    return service.search(body.query.trim(), limit, params.provider);
  });

  app.get("/external/artists/:provider/:externalId", async (request) => {
    await principal(request);
    const query = request.query as { name?: string };
    const name = query.name?.trim() ?? "";
    if (!name || name.length > 200) throw new AuthError("invalid_artist_name", 400, "search.invalid_artist_name");
    try { return await service.artistLibrary(name); }
    catch (error) {
      if (error instanceof MusicProviderError) {
        const status = error.kind === "authentication" ? 502 : error.kind === "rate_limit" ? 429
          : error.kind === "temporary" ? 503 : 404;
        throw new AuthError(`provider_${error.kind}`, status, error.message);
      }
      throw error;
    }
  });

  // Like catalog streaming, this route is intentionally usable by AVPlayer without
  // custom bearer headers. It only resolves an opaque public-provider identifier.
  app.get("/external/audio/:provider/:entityType/:externalId", async (request, reply) => {
    const params = request.params as { provider: string; entityType: "track" | "artist" | "release"; externalId: string };
    try {
      return reply.redirect(await service.resolveAudio(params.provider, params.entityType, params.externalId));
    } catch (error) {
      if (error instanceof MusicProviderError) {
        const status = error.kind === "authentication" ? 502 : error.kind === "rate_limit" ? 429
          : error.kind === "geo_restricted" ? 451 : error.kind === "temporary" ? 503 : 404;
        throw new AuthError(`provider_${error.kind}`, status, error.message);
      }
      throw error;
    }
  });
}
