import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { resolve } from "node:path";
import type { ExternalEntityReference, ExternalReleaseType, NormalizedMusicResult } from "./models.js";
import { MusicProviderError } from "./models.js";

type JSONRecord = Record<string, unknown>;
export interface ExternalArtistLibrary { artist: NormalizedMusicResult; releases: NormalizedMusicResult[]; tracks: NormalizedMusicResult[] }
export interface ExternalReleaseDetail { release: NormalizedMusicResult; tracks: NormalizedMusicResult[] }
export interface ExternalMetadataCacheEntry { value: unknown; expiresAt: Date }
export interface ExternalMetadataCache { load(key: string): Promise<ExternalMetadataCacheEntry | null>; save(key: string, value: unknown, expiresAt: Date): Promise<void> }
export class MemoryExternalMetadataCache implements ExternalMetadataCache {
  private readonly values = new Map<string, ExternalMetadataCacheEntry>();
  async load(key: string): Promise<ExternalMetadataCacheEntry | null> { return this.values.get(key) ?? null; }
  async save(key: string, value: unknown, expiresAt: Date): Promise<void> { this.values.set(key, { value: structuredClone(value), expiresAt }); }
}
export type SpotDLMetadataRunner = (args: string[], timeoutMilliseconds: number) => Promise<string>;

export class SpotDLArtistMetadataResolver {
  readonly id = "spotdl";
  constructor(private readonly runner: SpotDLMetadataRunner = runHelper, private readonly cache: ExternalMetadataCache = new MemoryExternalMetadataCache(),
              private readonly timeoutMilliseconds = 60_000, private readonly cacheMilliseconds = 24 * 60 * 60 * 1_000) {}

  async resolveArtist(name: string): Promise<ExternalArtistLibrary> {
    const normalized = name.trim().replace(/\s+/g, " ");
    if (!normalized) throw new MusicProviderError(this.id, "unavailable", "spotdl.artist_name_required");
    return this.cached(`artist:${normalized.toLocaleLowerCase()}`, ["artist", normalized], normalizeArtist);
  }
  async resolveRelease(externalID: string): Promise<ExternalReleaseDetail> {
    if (!/^[A-Za-z0-9]{8,64}$/.test(externalID)) throw new MusicProviderError(this.id, "unavailable", "spotdl.invalid_release");
    return this.cached(`release:${externalID}`, ["release", externalID], normalizeReleaseDetail);
  }
  private async cached<T>(key: string, args: string[], normalize: (payload: unknown) => T): Promise<T> {
    const saved = await this.cache.load(key);
    if (saved && saved.expiresAt.getTime() > Date.now()) return structuredClone(saved.value) as T;
    try {
      const value = normalize(parsePayload(await this.runner(args, this.timeoutMilliseconds)));
      await this.cache.save(key, value, new Date(Date.now() + this.cacheMilliseconds));
      return structuredClone(value);
    } catch (error) {
      if (saved) return structuredClone(saved.value) as T;
      if (error instanceof MusicProviderError) throw error;
      throw new MusicProviderError(this.id, "temporary", error instanceof Error ? error.message : "spotdl.failed");
    }
  }
}

function parsePayload(stdout: string): unknown {
  const trimmed = stdout.trim();
  try { return JSON.parse(trimmed); }
  catch {
    const start = trimmed.indexOf("{"); const end = trimmed.lastIndexOf("}");
    if (start < 0 || end <= start) throw malformed();
    try { return JSON.parse(trimmed.slice(start, end + 1)); } catch { throw malformed(); }
  }
}
function normalizeArtist(payload: unknown): ExternalArtistLibrary {
  if (!isRecord(payload) || !isRecord(payload.artist) || !Array.isArray(payload.releases)) throw malformed();
  const raw = payload.artist; const name = text(raw.name) ?? "Unknown Artist"; const id = text(raw.id) ?? stableID(name);
  const releases = payload.releases.filter(isRecord).map((release) => normalizeRelease(release, name));
  const artwork = text(raw.artworkURL) ?? releases.find((item) => item.release.artworkURL)?.release.artworkURL ?? null;
  const reference: ExternalEntityReference = { provider: "spotify", entityType: "artist", externalID: id,
    canonicalURL: text(raw.url) ?? `https://open.spotify.com/artist/${id}` };
  return { artist: entity(reference, name, null, null, 0, artwork, false), releases: releases.map((value) => value.release),
    tracks: releases.flatMap((value) => value.tracks).filter(uniqueTrack) };
}
function normalizeReleaseDetail(payload: unknown): ExternalReleaseDetail {
  if (!isRecord(payload)) throw malformed();
  const raw = isRecord(payload.release) ? { ...payload.release, tracks: payload.tracks } : payload;
  return normalizeRelease(raw, text(raw.artist) ?? "Unknown Artist");
}
function normalizeRelease(raw: JSONRecord, fallbackArtist: string): ExternalReleaseDetail {
  const id = text(raw.id) ?? stableID(`${fallbackArtist}|${text(raw.title) ?? "release"}`); const title = text(raw.title) ?? "Unknown Release";
  const artist = text(raw.artist) ?? fallbackArtist; const releaseType = releaseKind(raw.releaseType); const releaseDate = text(raw.releaseDate);
  const rows = Array.isArray(raw.tracks) ? raw.tracks.filter(isRecord) : []; const artwork = text(raw.artworkURL) ?? text(rows[0]?.artworkURL);
  const reference: ExternalEntityReference = { provider: "spotify", entityType: "release", externalID: id,
    canonicalURL: text(raw.url) ?? `https://open.spotify.com/album/${id}` };
  const release = { ...entity(reference, title, artist, null, 0, artwork, false), releaseType, releaseDate, trackCount: rows.length };
  const tracks = rows.map((song) => normalizeTrack(song, artist, title, artwork, releaseType, releaseDate))
    .sort((a, b) => (a.discNumber ?? 1) - (b.discNumber ?? 1) || (a.trackNumber ?? 0) - (b.trackNumber ?? 0));
  return { release, tracks };
}
function normalizeTrack(raw: JSONRecord, fallbackArtist: string, release: string, artwork: string | null,
                        releaseType: ExternalReleaseType, releaseDate: string | null): NormalizedMusicResult {
  const title = text(raw.title) ?? "Unknown Track"; const artist = text(raw.artist) ?? fallbackArtist;
  const id = text(raw.id) ?? stableID(`${artist}|${title}|${release}`);
  const reference: ExternalEntityReference = { provider: "spotify", entityType: "track", externalID: id,
    canonicalURL: text(raw.url) ?? `https://open.spotify.com/track/${id}` };
  return { ...entity(reference, title, artist, release, number(raw.duration), text(raw.artworkURL) ?? artwork, true), releaseType, releaseDate,
    discNumber: integer(raw.discNumber, 1), trackNumber: integer(raw.trackNumber, 0), explicit: raw.explicit === true };
}
function entity(reference: ExternalEntityReference, title: string, artist: string | null, release: string | null,
                duration: number, artworkURL: string | null, acquirable: boolean): NormalizedMusicResult {
  return { id: `${reference.provider}:${reference.entityType}:${reference.externalID}`, entityType: reference.entityType, title, artist, release,
    duration, artworkURL, metadataSource: { provider: "spotdl", reference }, audioSource: null,
    acquisition: { provider: reference.provider, reference, method: acquirable ? "spotdl" : "unavailable", allowed: acquirable },
    attribution: "Spotify metadata via spotDL" };
}
function runHelper(args: string[], timeoutMilliseconds: number): Promise<string> {
  // The helper remains in src/ when TypeScript is compiled to dist/, so resolve
  // it from the application working directory in both dev and production.
  const helper = resolve(process.cwd(), "src", "search", "spotdl-metadata-helper.py");
  return new Promise((resolve, reject) => {
    const child = spawn(process.env.PYTHON_BIN ?? "python3", [helper, ...args], { shell: false, stdio: ["ignore", "pipe", "pipe"] });
    const stdout: Buffer[] = []; const stderr: Buffer[] = [];
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("spotdl.metadata_timeout")); }, timeoutMilliseconds);
    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk)); child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
    child.on("error", (error) => { clearTimeout(timer); reject(error); });
    child.on("close", (code) => { clearTimeout(timer); code === 0 ? resolve(Buffer.concat(stdout).toString())
      : reject(new Error(Buffer.concat(stderr).toString().slice(-2_000) || `spotdl.helper_exit_${code}`)); });
  });
}
function uniqueTrack(value: NormalizedMusicResult, index: number, values: NormalizedMusicResult[]): boolean {
  return values.findIndex((item) => item.metadataSource.reference.externalID === value.metadataSource.reference.externalID) === index;
}
function malformed(): MusicProviderError { return new MusicProviderError("spotdl", "malformed_response", "spotdl.invalid_payload"); }
function isRecord(value: unknown): value is JSONRecord { return typeof value === "object" && value !== null && !Array.isArray(value); }
function text(value: unknown): string | null { return typeof value === "string" && value.trim() ? value.trim() : null; }
function number(value: unknown): number { const parsed = Number(value); return Number.isFinite(parsed) && parsed > 0 ? parsed : 0; }
function integer(value: unknown, fallback: number): number { const parsed = Number(value); return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback; }
function releaseKind(value: unknown): ExternalReleaseType { return value === "album" || value === "single" || value === "compilation" ? value : "unknown"; }
function stableID(value: string): string { return createHash("sha256").update(value.toLocaleLowerCase()).digest("hex").slice(0, 24); }
