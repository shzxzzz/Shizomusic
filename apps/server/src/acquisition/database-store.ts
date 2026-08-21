import { and, desc, eq } from "drizzle-orm";
import type { AuthPrincipal } from "../auth/models.js";
import type { Database } from "../db/client.js";
import { acquisitionExternalReferences, acquisitionJobs } from "../db/schema.js";
import type { AcquisitionJobView, AcquisitionRequest, AcquisitionStore } from "./models.js";

export class DatabaseAcquisitionStore implements AcquisitionStore {
  constructor(private readonly db: Database) {}
  async create(principal: AuthPrincipal, request: AcquisitionRequest): Promise<AcquisitionJobView> {
    const [existingFile] = await this.db.select().from(acquisitionExternalReferences).where(and(eq(acquisitionExternalReferences.provider, request.reference.provider),
      eq(acquisitionExternalReferences.entityType, request.reference.entityType), eq(acquisitionExternalReferences.externalId, request.reference.externalID))).limit(1);
    const [row] = await this.db.insert(acquisitionJobs).values({ userId: principal.userId, deviceId: principal.deviceId,
      provider: request.reference.provider, entityType: request.reference.entityType, externalId: request.reference.externalID,
      canonicalUrl: request.reference.canonicalURL, method: request.method, title: request.title, artist: request.artist,
      artworkUrl: request.artworkURL, state: existingFile ? "completed" : "queued", progress: existingFile ? 1 : 0,
      catalogFileId: existingFile?.catalogFileId, completedAt: existingFile ? new Date() : null }).returning();
    if (!row) throw new Error("acquisition_create_failed"); return view(row);
  }
  async list(principal: AuthPrincipal): Promise<AcquisitionJobView[]> {
    return (await this.db.select().from(acquisitionJobs).where(eq(acquisitionJobs.userId, principal.userId)).orderBy(desc(acquisitionJobs.createdAt)).limit(100)).map(view);
  }
  async get(principal: AuthPrincipal, id: string): Promise<AcquisitionJobView | null> {
    const [row] = await this.db.select().from(acquisitionJobs).where(and(eq(acquisitionJobs.id, id), eq(acquisitionJobs.userId, principal.userId))).limit(1);
    return row ? view(row) : null;
  }
  async retry(principal: AuthPrincipal, id: string): Promise<AcquisitionJobView | null> {
    const [row] = await this.db.update(acquisitionJobs).set({ state: "queued", progress: 0, attemptCount: 0, errorCode: null, errorDetail: null,
      nextAttemptAt: new Date(), updatedAt: new Date() }).where(and(eq(acquisitionJobs.id, id), eq(acquisitionJobs.userId, principal.userId), eq(acquisitionJobs.state, "failed"))).returning();
    return row ? view(row) : null;
  }
}

function view(row: typeof acquisitionJobs.$inferSelect): AcquisitionJobView {
  return { id: row.id, reference: { provider: row.provider, entityType: row.entityType as "track" | "artist" | "release", externalID: row.externalId, canonicalURL: row.canonicalUrl },
    method: row.method as "direct" | "yt_dlp" | "spotdl" | "unavailable", title: row.title, artist: row.artist, artworkURL: row.artworkUrl,
    state: row.state as AcquisitionJobView["state"], progress: row.progress, attemptCount: row.attemptCount, maxAttempts: row.maxAttempts,
    errorCode: row.errorCode, errorDetail: row.errorDetail, catalogFileID: row.catalogFileId,
    createdAt: row.createdAt.toISOString(), updatedAt: row.updatedAt.toISOString() };
}
