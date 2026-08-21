import { and, desc, eq, gte } from "drizzle-orm";
import type { Database } from "../db/client.js";
import { providerSearchTracks } from "../db/schema.js";
import type { MusicSearchCache, MusicSourceSearchResult } from "./models.js";

export class DatabaseMusicSearchCache implements MusicSearchCache {
  constructor(private readonly db: Database) {}

  async save(query: string, result: MusicSourceSearchResult): Promise<void> {
    if (result.items.length === 0) return;
    const now = new Date();
    await this.db.transaction(async (tx) => {
      for (const item of result.items) {
        await tx.insert(providerSearchTracks).values({
          provider: item.metadataSource.provider, externalId: item.metadataSource.reference.externalID, entityType: item.entityType,
          title: item.title, artist: item.artist ?? "", album: item.release, duration: item.duration, artworkUrl: item.artworkURL,
          webpageUrl: item.metadataSource.reference.canonicalURL, canonicalUrl: item.metadataSource.reference.canonicalURL,
          streamPath: item.audioSource?.resolverPath, metadataProvider: item.metadataSource.provider,
          audioProvider: item.audioSource?.provider, acquisitionMethod: item.acquisition.method,
          capabilities: ["search", ...(item.audioSource ? ["stream"] : []), ...(item.acquisition.allowed ? ["acquire"] : [])],
          attribution: item.attribution, lastQuery: query.toLocaleLowerCase(), updatedAt: now,
        }).onConflictDoUpdate({
          target: [providerSearchTracks.provider, providerSearchTracks.entityType, providerSearchTracks.externalId],
          set: { entityType: item.entityType, title: item.title, artist: item.artist ?? "", album: item.release, duration: item.duration,
            artworkUrl: item.artworkURL, webpageUrl: item.metadataSource.reference.canonicalURL,
            canonicalUrl: item.metadataSource.reference.canonicalURL, streamPath: item.audioSource?.resolverPath,
            metadataProvider: item.metadataSource.provider, audioProvider: item.audioSource?.provider,
            acquisitionMethod: item.acquisition.method,
            capabilities: ["search", ...(item.audioSource ? ["stream"] : []), ...(item.acquisition.allowed ? ["acquire"] : [])], attribution: item.attribution,
            lastQuery: query.toLocaleLowerCase(), updatedAt: now },
        });
      }
    });
  }

  async load(query: string, provider: string) {
    const rows = await this.db.select().from(providerSearchTracks).where(and(eq(providerSearchTracks.provider, provider),
      eq(providerSearchTracks.lastQuery, query.toLocaleLowerCase()), gte(providerSearchTracks.updatedAt, new Date(Date.now() - 15 * 60_000))))
      .orderBy(desc(providerSearchTracks.updatedAt)).limit(100);
    return rows.map((row) => {
      const entityType = row.entityType as "track" | "artist" | "release";
      const reference = { provider: row.metadataProvider, entityType, externalID: row.externalId, canonicalURL: row.canonicalUrl };
      return { id: `${row.provider}:${row.entityType}:${row.externalId}`, entityType, title: row.title,
        artist: row.artist || null, release: row.album, duration: row.duration, artworkURL: row.artworkUrl,
        metadataSource: { provider: row.metadataProvider, reference },
        audioSource: row.audioProvider && row.streamPath ? { provider: row.audioProvider, reference: { ...reference, provider: row.audioProvider }, resolverPath: row.streamPath } : null,
        acquisition: { provider: row.provider, reference, method: row.acquisitionMethod as "direct" | "yt_dlp" | "spotdl" | "unavailable", allowed: row.acquisitionMethod !== "unavailable" },
        attribution: row.attribution ?? row.provider };
    });
  }
}
