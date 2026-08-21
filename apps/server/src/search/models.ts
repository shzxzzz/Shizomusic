export type MusicSourceCapability = "search" | "stream" | "download";

export type MusicSourceFailureKind = "authentication" | "rate_limit" | "geo_restricted" | "temporary" | "unavailable";

export interface NormalizedMusicResult {
  id: string;
  provider: string;
  title: string;
  artist: string;
  album: string | null;
  duration: number;
  artworkURL: string | null;
  webpageURL: string | null;
  streamPath: string | null;
  capabilities: MusicSourceCapability[];
  attribution: string | null;
}

export interface MusicSourceFailure {
  provider: string;
  kind: MusicSourceFailureKind;
  message: string;
  retryAfterSeconds?: number;
}

export interface MusicSourceSearchResult {
  provider: string;
  items: NormalizedMusicResult[];
}

export interface MusicSourceAdapter {
  readonly id: string;
  readonly capabilities: ReadonlySet<MusicSourceCapability>;
  search(query: string, limit: number): Promise<MusicSourceSearchResult>;
  resolveStream?(externalID: string): Promise<string>;
}

export interface MusicSearchCache {
  save(query: string, result: MusicSourceSearchResult): Promise<void>;
}

export class MusicProviderError extends Error {
  constructor(
    readonly provider: string,
    readonly kind: MusicSourceFailureKind,
    message: string,
    readonly retryAfterSeconds?: number,
  ) { super(message); }
}
