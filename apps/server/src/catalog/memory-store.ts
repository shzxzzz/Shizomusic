import { createHash, randomUUID } from "node:crypto";
import type { AuthPrincipal } from "../auth/models.js";
import type { CatalogStore, CatalogTrackView, StoredObject, UploadRequest, UploadSessionView } from "./models.js";

interface Session { owner: string; request: UploadRequest; partSize: number; totalParts: number; parts: Map<number, Buffer> }

export class MemoryCatalogStore implements CatalogStore {
  private readonly sessions = new Map<string, Session>();
  private readonly files = new Map<string, { id: string; bytes: Buffer; view: CatalogTrackView }>();

  async createUpload(principal: AuthPrincipal, request: UploadRequest): Promise<UploadSessionView> {
    const available = this.files.get(request.sha256);
    const partSize = request.partSize ?? 1024 * 1024;
    const totalParts = Math.ceil(Number(request.byteSize) / partSize);
    if (available) return { id: randomUUID(), partSize, totalParts, uploadedParts: [], expiresAt: new Date().toISOString(), alreadyAvailableFileId: available.id };
    const existing = [...this.sessions].find(([, value]) => value.owner === principal.deviceId && value.request.sha256 === request.sha256);
    if (existing) return { id: existing[0], partSize: existing[1].partSize, totalParts: existing[1].totalParts,
      uploadedParts: [...existing[1].parts.keys()], expiresAt: new Date(Date.now() + 86_400_000).toISOString() };
    const id = randomUUID();
    this.sessions.set(id, { owner: principal.deviceId, request, partSize, totalParts, parts: new Map() });
    return { id, partSize, totalParts, uploadedParts: [], expiresAt: new Date(Date.now() + 86_400_000).toISOString() };
  }
  async putPart(principal: AuthPrincipal, uploadId: string, partNumber: number, bytes: Buffer, sha256: string): Promise<void> {
    const session = this.session(principal, uploadId);
    if (createHash("sha256").update(bytes).digest("hex") !== sha256) throw new Error("upload_part_mismatch");
    session.parts.set(partNumber, bytes);
  }
  async completeUpload(principal: AuthPrincipal, uploadId: string) {
    const session = this.session(principal, uploadId);
    const bytes = Buffer.concat([...session.parts.entries()].sort(([a], [b]) => a - b).map(([, value]) => value));
    const hash = createHash("sha256").update(bytes).digest("hex");
    if (hash !== session.request.sha256 || String(bytes.length) !== session.request.byteSize) throw new Error("upload_checksum_mismatch");
    const id = randomUUID();
    const view: CatalogTrackView = { id, contentHash: hash, byteSize: String(bytes.length), mimeType: session.request.mimeType,
      filename: session.request.filename, status: "ready", title: session.request.filename.replace(/\.[^.]+$/, ""), artist: "Unknown Artist",
      album: null, albumArtist: null, duration: 0, format: null, codec: null,
      addedBy: { id: principal.userId, displayName: "Test User" }, streamPath: `/catalog/files/${hash}`, artworkPath: null, createdAt: new Date().toISOString() };
    this.files.set(hash, { id, bytes, view }); this.sessions.delete(uploadId);
    return { fileId: id, contentHash: hash, status: "ready" };
  }
  async cancelUpload(principal: AuthPrincipal, uploadId: string): Promise<void> { this.session(principal, uploadId); this.sessions.delete(uploadId); }
  async listCatalog(): Promise<CatalogTrackView[]> { return [...this.files.values()].map((value) => value.view); }
  async object(contentHash: string, artwork: boolean): Promise<StoredObject | null> {
    if (artwork) return null;
    const file = this.files.get(contentHash);
    if (!file) return null;
    return { bytes: file.bytes, size: BigInt(file.bytes.length), mimeType: file.view.mimeType, etag: `"sha256-${contentHash}"` };
  }
  bytes(contentHash: string): Buffer | undefined { return this.files.get(contentHash)?.bytes; }
  private session(principal: AuthPrincipal, id: string): Session {
    const value = this.sessions.get(id); if (!value || value.owner !== principal.deviceId) throw new Error("upload_not_found"); return value;
  }
}
