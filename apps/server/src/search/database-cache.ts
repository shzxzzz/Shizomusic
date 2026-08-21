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
          provider: item.provider, externalId: item.id, title: item.title, artist: item.artist,
          album: item.album, duration: item.duration, artworkUrl: item.artworkURL,
          webpageUrl: item.webpageURL, streamPath: item.streamPath, capabilities: item.capabilities,
          attribution: item.attribution, lastQuery: query.toLocaleLowerCase(), updatedAt: now,
        }).onConflictDoUpdate({
          target: [providerSearchTracks.provider, providerSearchTracks.externalId],
          set: { title: item.title, artist: item.artist, album: item.album, duration: item.duration,
            artworkUrl: item.artworkURL, webpageUrl: item.webpageURL, streamPath: item.streamPath,
            capabilities: item.capabilities, attribution: item.attribution,
            lastQuery: query.toLocaleLowerCase(), updatedAt: now },
        });
      }
    });
  }
}
