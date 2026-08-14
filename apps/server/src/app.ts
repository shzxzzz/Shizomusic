import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";

export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: true, requestIdHeader: "x-request-id" });
  app.register(cors, { origin: false });
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);
    const statusCode = typeof error === "object" && error !== null && "statusCode" in error && typeof error.statusCode === "number"
      ? error.statusCode
      : 500;
    return reply.status(statusCode).send({ code: "internal_error", messageKey: "error.internal", requestID: request.id });
  });
  app.get("/health", async () => ({ status: "ok" }));
  app.get("/ready", async () => ({ status: "ready" }));
  return app;
}
