import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AuthPrincipal } from "../auth/models.js";
import { AuthError } from "../auth/errors.js";
import type { AcquisitionStore } from "./models.js";
import { validateAcquisitionRequest } from "./models.js";

export function registerAcquisitionRoutes(app: FastifyInstance, store: AcquisitionStore,
  principal: (request: FastifyRequest) => Promise<AuthPrincipal>): void {
  app.post("/acquisitions", async (request) => {
    try { return await store.create(await principal(request), validateAcquisitionRequest(request.body)); }
    catch (error) { if (error instanceof AuthError) throw error; throw new AuthError("invalid_acquisition", 400, error instanceof Error ? error.message : "acquisition.invalid"); }
  });
  app.get("/acquisitions", async (request) => ({ jobs: await store.list(await principal(request)) }));
  app.get("/acquisitions/:id", async (request) => {
    const job = await store.get(await principal(request), (request.params as { id: string }).id);
    if (!job) throw new AuthError("acquisition_not_found", 404, "acquisition.not_found"); return job;
  });
  app.post("/acquisitions/:id/retry", async (request) => {
    const job = await store.retry(await principal(request), (request.params as { id: string }).id);
    if (!job) throw new AuthError("acquisition_not_retryable", 409, "acquisition.not_retryable"); return job;
  });
}
