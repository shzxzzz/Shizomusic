import type { ArtistMetadataResolver, MusicSearchCache, MusicSourceAdapter, MusicSourceFailure, NormalizedMusicResult } from "./models.js";
import type { ExternalArtistLibrary } from "./spotdl-metadata.js";
import { MusicProviderError } from "./models.js";

export interface MusicSearchResponse {
  results: NormalizedMusicResult[];
  failures: MusicSourceFailure[];
}

export class MemoryMusicSearchCache implements MusicSearchCache {
  readonly values = new Map<string, NormalizedMusicResult[]>();
  async save(query: string, result: { provider: string; items: NormalizedMusicResult[] }): Promise<void> {
    this.values.set(`${result.provider}:${query.toLocaleLowerCase()}`, structuredClone(result.items));
  }
  async load(query: string, provider: string): Promise<NormalizedMusicResult[]> {
    return structuredClone(this.values.get(`${provider}:${query.toLocaleLowerCase()}`) ?? []);
  }
}

export class MusicSearchService {
  private readonly byID: Map<string, MusicSourceAdapter>;

  constructor(private readonly adapters: MusicSourceAdapter[], private readonly cache: MusicSearchCache,
              private readonly artistMetadata?: ArtistMetadataResolver) {
    this.byID = new Map(adapters.map((adapter) => [adapter.id, adapter]));
  }

  async artistLibrary(name: string): Promise<ExternalArtistLibrary> {
    if (!this.artistMetadata) throw new MusicProviderError("spotdl", "unavailable", "spotdl.not_configured");
    // Resolve audio once for the whole artist page: catalog wins, then Piped.
    // Temporary provider URLs remain behind resolverPath and are never persisted.
    const audioAdapters = this.adapters.filter((adapter) => adapter.id === "catalog" || adapter.id === "piped");
    const [metadata, settled] = await Promise.all([
      this.artistMetadata.resolveArtist(name).then((value) => ({ value })).catch((error: unknown) => ({ error })),
      Promise.allSettled(audioAdapters.map((adapter) => adapter.search(name, 50))),
    ]);
    const candidates = settled.flatMap((value) => value.status === "fulfilled" ? value.value.items : [])
      .filter((value) => value.entityType === "track" && value.audioSource !== null);
    const catalogTracks = candidates.filter((value) => value.metadataSource.provider === "catalog" && artistMatches(value, name));
    if (!("value" in metadata) && !catalogTracks.length) throw metadata.error;
    const library = "value" in metadata ? metadata.value : catalogFallback(name, catalogTracks);
    const tracks = library.tracks.map((track) => {
      const match = candidates.find((candidate) => sameTrack(track, candidate, name));
      return match ? { ...track, audioSource: match.audioSource } : track;
    });
    const known = new Set(tracks.map(trackFingerprint));
    for (const candidate of candidates.filter((value) => value.metadataSource.provider === "catalog")) {
      if (!known.has(trackFingerprint(candidate))) tracks.push(candidate);
    }
    return { ...library, tracks };
  }

  async search(query: string, limit = 30, onlyProvider?: string): Promise<MusicSearchResponse> {
    const selected = onlyProvider ? this.adapters.filter((adapter) => adapter.id === onlyProvider) : this.adapters;
    const settled = await Promise.allSettled(selected.map(async (adapter) => {
      const result = await adapter.search(query, limit);
      // Persistence is part of the result contract: the UI never sees a provider
      // item that cannot be recovered from the server cache.
      await this.cache.save(query, result);
      return result;
    }));
    const results: NormalizedMusicResult[] = [];
    const failures: MusicSourceFailure[] = [];
    for (const [index, outcome] of settled.entries()) {
      const provider = selected[index]?.id ?? "unknown";
      if (outcome.status === "fulfilled") results.push(...outcome.value.items);
      else {
        const error = outcome.reason;
        if (this.cache.load) results.push(...await this.cache.load(query, provider));
        failures.push(error instanceof MusicProviderError
          ? { provider, kind: error.kind, message: error.message, ...(error.retryAfterSeconds === undefined ? {} : { retryAfterSeconds: error.retryAfterSeconds }) }
          : { provider, kind: "temporary", message: error instanceof Error ? error.message : "provider_failed" });
      }
    }
    return { results, failures };
  }

  async resolveAudio(provider: string, entityType: "track" | "artist" | "release", externalID: string): Promise<string> {
    const adapter = this.byID.get(provider);
    if (!adapter?.capabilities.has("stream") || !adapter.resolveAudio) throw new MusicProviderError(provider, "unavailable", "stream_not_supported");
    return adapter.resolveAudio({ provider, entityType, externalID, canonicalURL: null });
  }
}

function normalized(value: string | null): string {
  return (value ?? "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}
function trackFingerprint(value: NormalizedMusicResult): string { return `${normalized(value.title)}|${normalized(value.artist)}`; }
function sameTrack(left: NormalizedMusicResult, right: NormalizedMusicResult, artistName: string): boolean {
  const leftTitle = normalized(left.title); const rightTitle = normalized(right.title);
  if (!leftTitle || leftTitle !== rightTitle) return false;
  const expectedArtist = normalized(artistName); const candidateArtist = normalized(right.artist);
  return !candidateArtist || candidateArtist.includes(expectedArtist) || expectedArtist.includes(candidateArtist);
}
function artistMatches(value: NormalizedMusicResult, artistName: string): boolean {
  const expected = normalized(artistName); const actual = normalized(value.artist);
  return actual === expected || actual.split(" ").includes(expected) || actual.includes(expected);
}
function catalogFallback(name: string, tracks: NormalizedMusicResult[]): ExternalArtistLibrary {
  const externalID = normalized(name).replace(/\s+/g, "-");
  const artistReference = { provider: "catalog", entityType: "artist" as const, externalID, canonicalURL: null };
  const artist: NormalizedMusicResult = { id: `catalog:artist:${externalID}`, entityType: "artist", title: name, artist: null, release: null,
    duration: 0, artworkURL: tracks.find((value) => value.artworkURL)?.artworkURL ?? null,
    metadataSource: { provider: "catalog", reference: artistReference }, audioSource: null,
    acquisition: { provider: "catalog", reference: artistReference, method: "unavailable", allowed: false }, attribution: "ShizoMusic" };
  const releases = new Map<string, NormalizedMusicResult>();
  for (const track of tracks) {
    if (!track.release) continue; const id = normalized(track.release).replace(/\s+/g, "-");
    if (releases.has(id)) continue;
    const reference = { provider: "catalog", entityType: "release" as const, externalID: id, canonicalURL: null };
    releases.set(id, { id: `catalog:release:${id}`, entityType: "release", title: track.release, artist: name, release: null,
      duration: 0, artworkURL: track.artworkURL, metadataSource: { provider: "catalog", reference }, audioSource: null,
      acquisition: { provider: "catalog", reference, method: "unavailable", allowed: false }, attribution: "ShizoMusic" });
  }
  return { artist, releases: [...releases.values()], tracks };
}
