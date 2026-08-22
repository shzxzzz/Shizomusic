import { eq } from "drizzle-orm";
import type { Database } from "../db/client.js";
import { externalMetadataCache } from "../db/schema.js";
import type { ExternalMetadataCache, ExternalMetadataCacheEntry } from "./spotdl-metadata.js";

export class DatabaseExternalMetadataCache implements ExternalMetadataCache {
  constructor(private readonly db: Database) {}
  async load(key: string): Promise<ExternalMetadataCacheEntry | null> {
    const [row] = await this.db.select().from(externalMetadataCache).where(eq(externalMetadataCache.key, key)).limit(1);
    return row ? { value: row.payload, expiresAt: row.expiresAt } : null;
  }
  async save(key: string, value: unknown, expiresAt: Date): Promise<void> {
    await this.db.insert(externalMetadataCache).values({ key, payload: value, expiresAt, updatedAt: new Date() })
      .onConflictDoUpdate({ target: externalMetadataCache.key, set: { payload: value, expiresAt, updatedAt: new Date() } });
  }
}
