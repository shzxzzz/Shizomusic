import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { createReadStream } from "node:fs";
import type { AuthPrincipal } from "../auth/models.js";
import type { CatalogStore, StoredObject, UploadRequest } from "./models.js";

export function registerCatalogRoutes(
  app: FastifyInstance,
  store: CatalogStore,
  principal: (request: FastifyRequest) => Promise<AuthPrincipal>,
): void {
  app.post("/catalog/uploads", async (request) => {
    const actor = await principal(request);
    return catalogCall(() => store.createUpload(actor, request.body as UploadRequest));
  });
  app.put("/catalog/uploads/:id/parts/:partNumber", async (request, reply) => {
    const actor = await principal(request);
    const { id, partNumber } = request.params as { id: string; partNumber: string };
    const hash = request.headers["x-part-sha256"];
    if (typeof hash !== "string" || !Buffer.isBuffer(request.body)) return reply.status(400).send({ code: "invalid_upload_part" });
    await catalogCall(() => store.putPart(actor, id, Number(partNumber), request.body as Buffer, hash));
    return reply.status(204).send();
  });
  app.post("/catalog/uploads/:id/complete", async (request) => {
    const actor = await principal(request);
    return catalogCall(() => store.completeUpload(actor, (request.params as { id: string }).id));
  });
  app.delete("/catalog/uploads/:id", async (request, reply) => {
    const actor = await principal(request);
    await catalogCall(() => store.cancelUpload(actor, (request.params as { id: string }).id));
    return reply.status(204).send();
  });
  app.get("/catalog", async (request) => { await principal(request); return { tracks: await store.listCatalog() }; });
  app.get("/catalog/files/:hash", async (request, reply) => sendObject(request, reply, store, false));
  app.get("/catalog/files/:hash/artwork", async (request, reply) => sendObject(request, reply, store, true));
}

async function catalogCall<T>(operation: () => Promise<T>): Promise<T> {
  try { return await operation(); }
  catch (error) {
    const code = error instanceof Error ? error.message : "catalog_error";
    if (code.startsWith("upload_") || code === "invalid_upload" || code === "invalid_upload_part") {
      throw Object.assign(new Error(code), { statusCode: code === "upload_not_found" ? 404 : 400, code, messageKey: `catalog.${code}` });
    }
    throw error;
  }
}

async function sendObject(request: FastifyRequest, reply: FastifyReply, store: CatalogStore, artwork: boolean) {
  const hash = (request.params as { hash: string }).hash;
  const object = await store.object(hash, artwork);
  if (!object) return reply.status(404).send({ code: "file_not_found" });
  if (request.headers["if-none-match"] === object.etag) return reply.status(304).send();
  const range = parseRange(request.headers.range, object);
  reply.header("Accept-Ranges", "bytes").header("ETag", object.etag).type(object.mimeType);
  if (request.headers.range && !range) return reply.status(416).header("Content-Range", `bytes */${object.size}`).send();
  if (!range) {
    reply.header("Content-Length", object.size.toString());
    return reply.send(object.bytes ?? createReadStream(object.path!));
  }
  reply.status(206).header("Content-Range", `bytes ${range.start}-${range.end}/${object.size}`)
    .header("Content-Length", String(range.end - range.start + 1));
  return reply.send(object.bytes?.subarray(range.start, range.end + 1) ?? createReadStream(object.path!, { start: range.start, end: range.end }));
}

function parseRange(value: string | undefined, object: StoredObject): { start: number; end: number } | null {
  if (!value) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(value);
  if (!match) return null;
  const size = Number(object.size);
  if (!Number.isSafeInteger(size) || size <= 0 || (!match[1] && !match[2])) return null;
  let start: number;
  let end: number;
  if (!match[1]) {
    const suffixLength = Number(match[2]);
    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) return null;
    start = Math.max(size - suffixLength, 0);
    end = size - 1;
  } else {
    start = Number(match[1]);
    end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  }
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= size || end < start) return null;
  return { start, end };
}
