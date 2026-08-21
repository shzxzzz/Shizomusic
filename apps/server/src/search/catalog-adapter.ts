import type { CatalogStore } from "../catalog/models.js";
import type { MusicSourceAdapter, MusicSourceSearchResult } from "./models.js";

export class CatalogMusicSourceAdapter implements MusicSourceAdapter {
  readonly id = "catalog";
  readonly capabilities = new Set(["search", "stream", "download"] as const);
  constructor(private readonly catalog: CatalogStore) {}

  async search(query: string, limit: number): Promise<MusicSourceSearchResult> {
    const needle = query.toLocaleLowerCase();
    const tracks = (await this.catalog.listCatalog()).filter((track) =>
      [track.title, track.artist, track.album, track.albumArtist].some((value) => value?.toLocaleLowerCase().includes(needle))
    ).slice(0, limit);
    return { provider: this.id, items: tracks.map((track) => ({
      id: track.id, provider: this.id, title: track.title, artist: track.artist, album: track.album,
      duration: track.duration, artworkURL: track.artworkPath, webpageURL: null, streamPath: track.streamPath,
      capabilities: ["search", "stream", "download"], attribution: track.addedBy.displayName,
    })) };
  }
}
