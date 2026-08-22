import type { CatalogStore } from "../catalog/models.js";
import type { ExternalEntityReference, MusicSourceAdapter, MusicSourceSearchResult } from "./models.js";

export class CatalogMusicSourceAdapter implements MusicSourceAdapter {
  readonly id = "catalog";
  readonly capabilities = new Set(["search", "stream", "acquire"] as const);
  constructor(private readonly catalog: CatalogStore) {}

  async search(query: string, limit: number): Promise<MusicSourceSearchResult> {
    const needle = query.toLocaleLowerCase();
    const tracks = (await this.catalog.listCatalog()).filter((track) =>
      [track.title, track.artist, track.album, track.albumArtist].some((value) => value?.toLocaleLowerCase().includes(needle))
    ).slice(0, limit);
    return { provider: this.id, items: tracks.map((track) => this.item(track)) };
  }

  async lookupExternal(reference: ExternalEntityReference) {
    const track = await this.catalog.findByExternalReference?.(reference.provider, reference.entityType, reference.externalID);
    return track ? this.item(track) : null;
  }

  private item(track: Awaited<ReturnType<CatalogStore["listCatalog"]>>[number]) {
    const reference: ExternalEntityReference = { provider: this.id, entityType: "track", externalID: track.id, canonicalURL: null };
    return { id: `catalog:track:${track.id}`, entityType: "track" as const, title: track.title, artist: track.artist,
      release: track.album, duration: track.duration, artworkURL: track.artworkPath,
      metadataSource: { provider: this.id, reference }, audioSource: { provider: this.id, reference, resolverPath: track.streamPath },
      acquisition: { provider: this.id, reference, method: "direct" as const, allowed: true },
      attribution: `ShizoMusic · ${track.addedBy.displayName}` };
  }
}
