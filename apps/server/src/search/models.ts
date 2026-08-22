export type ExternalEntityType = "track" | "artist" | "release";
export type MusicSourceCapability = "search" | "stream" | "acquire";
export type AcquisitionMethod = "direct" | "yt_dlp" | "spotdl" | "unavailable";
export type ExternalReleaseType = "album" | "single" | "compilation" | "unknown";

export type MusicSourceFailureKind = "authentication" | "rate_limit" | "geo_restricted" | "temporary" | "unavailable" | "malformed_response";

export interface ExternalEntityReference { provider: string; entityType: ExternalEntityType; externalID: string; canonicalURL: string | null }
export interface ExternalSourceDescriptor { provider: string; reference: ExternalEntityReference }
export interface ExternalAudioDescriptor extends ExternalSourceDescriptor { resolverPath: string | null }
export interface ExternalAcquisitionDescriptor extends ExternalSourceDescriptor { method: AcquisitionMethod; allowed: boolean }

export interface NormalizedMusicResult {
  id: string;
  entityType: ExternalEntityType;
  title: string;
  artist: string | null;
  release: string | null;
  duration: number;
  artworkURL: string | null;
  metadataSource: ExternalSourceDescriptor;
  audioSource: ExternalAudioDescriptor | null;
  acquisition: ExternalAcquisitionDescriptor;
  attribution: string;
  releaseType?: ExternalReleaseType;
  releaseDate?: string | null;
  trackCount?: number;
  discNumber?: number;
  trackNumber?: number;
  explicit?: boolean;
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
  lookupExternal?(reference: ExternalEntityReference): Promise<NormalizedMusicResult | null>;
  resolveAudio?(reference: ExternalEntityReference): Promise<string>;
}

export interface ArtistMetadataResolver {
  resolveArtist(name: string): Promise<import("./spotdl-metadata.js").ExternalArtistLibrary>;
  resolveRelease(externalID: string): Promise<import("./spotdl-metadata.js").ExternalReleaseDetail>;
}

export interface MusicSearchCache {
  save(query: string, result: MusicSourceSearchResult): Promise<void>;
  load?(query: string, provider: string): Promise<NormalizedMusicResult[]>;
}

export class MusicProviderError extends Error {
  constructor(
    readonly provider: string,
    readonly kind: MusicSourceFailureKind,
    message: string,
    readonly retryAfterSeconds?: number,
  ) { super(message); }
}
