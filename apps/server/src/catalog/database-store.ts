import { and, asc, eq, gt } from "drizzle-orm";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdir, open, rename, rm, stat } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { AuthPrincipal } from "../auth/models.js";
import type { Database } from "../db/client.js";
import { catalogFiles, mediaJobs, uploadParts, uploadSessions, users } from "../db/schema.js";
import type { CatalogStore, CatalogTrackView, StoredObject, UploadRequest, UploadSessionView } from "./models.js";

const shaPattern = /^[a-f0-9]{64}$/;

export class DatabaseCatalogStore implements CatalogStore {
  constructor(private readonly db: Database, private readonly storageRoot: string) {}

  async createUpload(principal: AuthPrincipal, request: UploadRequest): Promise<UploadSessionView> {
    let byteSize: bigint;
    try { byteSize = BigInt(request.byteSize); } catch { throw new Error("invalid_upload"); }
    const mimeTypes = new Set(["audio/mpeg", "audio/flac", "audio/mp4", "audio/aac", "audio/wav"]);
    if (typeof request.filename !== "string" || typeof request.sha256 !== "string" || typeof request.mimeType !== "string"
      || !shaPattern.test(request.sha256) || byteSize <= 0n || byteSize > 4_294_967_296n || !mimeTypes.has(request.mimeType)) {
      throw new Error("invalid_upload");
    }
    const partSize = request.partSize ?? 8 * 1024 * 1024;
    if (!Number.isInteger(partSize) || partSize < 1024 * 1024 || partSize > 16 * 1024 * 1024) throw new Error("invalid_upload");
    const totalParts = Number((byteSize + BigInt(partSize) - 1n) / BigInt(partSize));
    const [available] = await this.db.select({ id: catalogFiles.id }).from(catalogFiles)
      .where(and(eq(catalogFiles.contentHash, request.sha256), eq(catalogFiles.status, "ready"))).limit(1);
    if (available) return { id: crypto.randomUUID(), partSize, totalParts, uploadedParts: [], expiresAt: new Date().toISOString(), alreadyAvailableFileId: available.id };
    const [existing] = await this.db.select().from(uploadSessions).where(and(
      eq(uploadSessions.deviceId, principal.deviceId), eq(uploadSessions.expectedHash, request.sha256),
      eq(uploadSessions.state, "uploading"), gt(uploadSessions.expiresAt, new Date())
    )).limit(1);
    const session = existing ?? (await this.db.insert(uploadSessions).values({
      userId: principal.userId, deviceId: principal.deviceId, expectedHash: request.sha256,
      expectedSize: byteSize, mimeType: request.mimeType, filename: safeFilename(request.filename),
      partSize, totalParts, expiresAt: new Date(Date.now() + 7 * 86_400_000),
    }).returning())[0];
    if (!session) throw new Error("upload_create_failed");
    const parts = await this.db.select({ number: uploadParts.partNumber }).from(uploadParts)
      .where(eq(uploadParts.uploadId, session.id)).orderBy(asc(uploadParts.partNumber));
    return { id: session.id, partSize: session.partSize, totalParts: session.totalParts,
      uploadedParts: parts.map((part) => part.number), expiresAt: session.expiresAt.toISOString() };
  }

  async putPart(principal: AuthPrincipal, uploadId: string, partNumber: number, bytes: Buffer, sha256: string): Promise<void> {
    const session = await this.ownedSession(principal, uploadId);
    if (session.state !== "uploading" || partNumber < 1 || partNumber > session.totalParts) throw new Error("invalid_upload_part");
    const expectedBytes = partNumber === session.totalParts
      ? Number(session.expectedSize - BigInt(session.partSize) * BigInt(session.totalParts - 1)) : session.partSize;
    if (bytes.length !== expectedBytes || digest(bytes) !== sha256 || !shaPattern.test(sha256)) throw new Error("upload_part_mismatch");
    const path = join(this.storageRoot, "uploads", uploadId, `${partNumber}.part`);
    await mkdir(dirname(path), { recursive: true });
    const temporary = `${path}.${crypto.randomUUID()}.tmp`;
    const handle = await open(temporary, "wx");
    try { await handle.writeFile(bytes); } finally { await handle.close(); }
    await rename(temporary, path);
    await this.db.insert(uploadParts).values({ uploadId, partNumber, byteSize: BigInt(bytes.length), sha256, storagePath: path })
      .onConflictDoUpdate({ target: [uploadParts.uploadId, uploadParts.partNumber], set: { byteSize: BigInt(bytes.length), sha256, storagePath: path } });
  }

  async completeUpload(principal: AuthPrincipal, uploadId: string): Promise<{ fileId: string; contentHash: string; status: string }> {
    const session = await this.ownedSession(principal, uploadId);
    const parts = await this.db.select().from(uploadParts).where(eq(uploadParts.uploadId, uploadId)).orderBy(asc(uploadParts.partNumber));
    if (parts.length !== session.totalParts || parts.some((part, index) => part.partNumber !== index + 1)) throw new Error("upload_incomplete");
    const storageKey = join("objects", session.expectedHash.slice(0, 2), session.expectedHash);
    const destination = join(this.storageRoot, storageKey);
    await mkdir(dirname(destination), { recursive: true });
    const temporary = `${destination}.${uploadId}.tmp`;
    const output = await open(temporary, "wx");
    try {
      for (const part of parts) for await (const chunk of createReadStream(part.storagePath)) await output.write(chunk as Buffer);
    } finally { await output.close(); }
    const actualSize = BigInt((await stat(temporary)).size);
    const actualHash = await digestFile(temporary);
    if (actualSize !== session.expectedSize || actualHash !== session.expectedHash) {
      await rm(temporary, { force: true });
      throw new Error("upload_checksum_mismatch");
    }
    try { await rename(temporary, destination); } catch { await rm(temporary, { force: true }); }
    const result = await this.db.transaction(async (tx) => {
      const [existing] = await tx.select().from(catalogFiles).where(eq(catalogFiles.contentHash, session.expectedHash)).limit(1);
      const file = existing ?? (await tx.insert(catalogFiles).values({
        contentHash: session.expectedHash, byteSize: session.expectedSize, mimeType: session.mimeType,
        storageKey, originalFilename: session.filename, title: session.filename.replace(/\.[^.]+$/, ""),
        artist: "Unknown Artist", duration: 0, addedByUserId: principal.userId,
      }).returning())[0];
      if (!file) throw new Error("catalog_insert_failed");
      if (!existing) await tx.insert(mediaJobs).values({ catalogFileId: file.id });
      await tx.update(uploadSessions).set({ state: "complete", completedAt: new Date() }).where(eq(uploadSessions.id, uploadId));
      return file;
    });
    await rm(join(this.storageRoot, "uploads", uploadId), { recursive: true, force: true });
    return { fileId: result.id, contentHash: result.contentHash, status: result.status };
  }

  async cancelUpload(principal: AuthPrincipal, uploadId: string): Promise<void> {
    await this.ownedSession(principal, uploadId);
    await this.db.update(uploadSessions).set({ state: "cancelled" }).where(eq(uploadSessions.id, uploadId));
    await rm(join(this.storageRoot, "uploads", uploadId), { recursive: true, force: true });
  }

  async listCatalog(): Promise<CatalogTrackView[]> {
    const rows = await this.db.select({ file: catalogFiles, userId: users.id, displayName: users.displayName })
      .from(catalogFiles).innerJoin(users, eq(users.id, catalogFiles.addedByUserId)).orderBy(asc(catalogFiles.createdAt));
    return rows.map(({ file, userId, displayName }) => ({
      id: file.id, contentHash: file.contentHash, byteSize: file.byteSize.toString(), mimeType: file.mimeType,
      filename: file.originalFilename, status: file.status, title: file.title ?? file.originalFilename,
      artist: file.artist ?? "Unknown Artist", album: file.album, albumArtist: file.albumArtist,
      duration: file.duration ?? 0, format: file.format, codec: file.codec,
      addedBy: { id: userId, displayName }, streamPath: `/catalog/files/${file.contentHash}`,
      artworkPath: file.artworkStorageKey ? `/catalog/files/${file.contentHash}/artwork` : null,
      createdAt: file.createdAt.toISOString(),
    }));
  }

  async object(contentHash: string, artwork: boolean): Promise<StoredObject | null> {
    const [file] = await this.db.select().from(catalogFiles).where(eq(catalogFiles.contentHash, contentHash)).limit(1);
    if (!file || file.status !== "ready") return null;
    const key = artwork ? file.artworkStorageKey : file.storageKey;
    if (!key) return null;
    return { path: join(this.storageRoot, key), size: BigInt((await stat(join(this.storageRoot, key))).size),
      mimeType: artwork ? file.artworkMimeType ?? "image/jpeg" : file.mimeType, etag: `"sha256-${artwork ? `${contentHash}-artwork` : contentHash}"` };
  }

  private async ownedSession(principal: AuthPrincipal, uploadId: string) {
    const [session] = await this.db.select().from(uploadSessions).where(and(eq(uploadSessions.id, uploadId), eq(uploadSessions.deviceId, principal.deviceId))).limit(1);
    if (!session || session.expiresAt < new Date()) throw new Error("upload_not_found");
    return session;
  }
}

function digest(bytes: Buffer): string { return createHash("sha256").update(bytes).digest("hex"); }
async function digestFile(path: string): Promise<string> {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk as Buffer);
  return hash.digest("hex");
}
function safeFilename(value: string): string { return value.replace(/[\\/\0]/g, "_").slice(0, 240) || "track"; }
