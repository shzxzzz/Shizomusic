import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import type { ExternalEntityReference, NormalizedMusicResult } from "./models.js";
import { MusicProviderError } from "./models.js";

type JSONRecord = Record<string, unknown>;

export interface ExternalArtistLibrary {
  artist: NormalizedMusicResult;
  releases: NormalizedMusicResult[];
  tracks: NormalizedMusicResult[];
}

export type SpotDLRunner = (args: string[], timeoutMilliseconds: number) => Promise<string>;

/** Metadata-only spotDL integration. Audio is still resolved/acquired separately. */
export class SpotDLArtistMetadataResolver {
  readonly id = "spotdl";
  private readonly cache = new Map<string, { expiresAt: number; value: ExternalArtistLibrary }>();

  constructor(private readonly runner: SpotDLRunner = runSpotDL,
              private readonly timeoutMilliseconds = 45_000,
              private readonly cacheMilliseconds = 6 * 60 * 60 * 1_000) {}

  async resolveArtist(name: string): Promise<ExternalArtistLibrary> {
    const normalized = name.trim().replace(/\s+/g, " ");
    if (!normalized) throw new MusicProviderError(this.id, "unavailable", "spotdl.artist_name_required");
    const key = normalized.toLocaleLowerCase();
    const cached = this.cache.get(key);
    if (cached && cached.expiresAt > Date.now()) return structuredClone(cached.value);

    let stdout: string;
    try {
      stdout = await this.runner(["save", `artist:${normalized}`, "--save-file", "-", "--max-retries", "2"], this.timeoutMilliseconds);
    } catch (error) {
      throw new MusicProviderError(this.id, "temporary", error instanceof Error ? error.message : "spotdl.failed");
    }
    const songs = parseSongs(stdout);
    if (!songs.length) throw new MusicProviderError(this.id, "unavailable", "spotdl.artist_not_found");
    const value = normalizeLibrary(normalized, songs);
    this.cache.set(key, { expiresAt: Date.now() + this.cacheMilliseconds, value });
    return structuredClone(value);
  }
}

function parseSongs(stdout: string): JSONRecord[] {
  const trimmed = stdout.trim();
  let payload: unknown;
  try { payload = JSON.parse(trimmed); }
  catch {
    // spotDL may print diagnostics before its JSON when providers emit warnings.
    const start = trimmed.indexOf("["); const end = trimmed.lastIndexOf("]");
    if (start < 0 || end <= start) throw new MusicProviderError("spotdl", "malformed_response", "spotdl.invalid_json");
    try { payload = JSON.parse(trimmed.slice(start, end + 1)); }
    catch { throw new MusicProviderError("spotdl", "malformed_response", "spotdl.invalid_json"); }
  }
  const values = Array.isArray(payload) ? payload : isRecord(payload) && Array.isArray(payload.songs) ? payload.songs : [];
  return values.filter(isRecord);
}

function normalizeLibrary(requestedName: string, songs: JSONRecord[]): ExternalArtistLibrary {
  const artistName = text(songs[0]?.artist) ?? stringArray(songs[0]?.artists)[0] ?? requestedName;
  const artistExternalID = externalID(text(songs[0]?.artist_url) ?? text(songs[0]?.artistUrl)) ?? stableID(artistName);
  const artistReference: ExternalEntityReference = { provider: "spotdl", entityType: "artist", externalID: artistExternalID,
    canonicalURL: text(songs[0]?.artist_url) ?? text(songs[0]?.artistUrl) };
  const artwork = text(songs[0]?.artist_image_url) ?? text(songs[0]?.artistImageUrl) ?? text(songs[0]?.image_url) ?? text(songs[0]?.cover_url);
  const artist: NormalizedMusicResult = entity(artistReference, artistName, null, null, 0, artwork, "Spotify metadata via spotDL");

  const tracks = songs.map((song) => {
    const title = text(song.name) ?? text(song.title) ?? "Unknown Track";
    const url = text(song.song_url) ?? text(song.url);
    const id = externalID(url) ?? text(song.song_id) ?? text(song.track_id) ?? stableID(`${artistName}|${title}|${text(song.album_name) ?? ""}`);
    const reference: ExternalEntityReference = { provider: "spotify", entityType: "track", externalID: id, canonicalURL: url };
    return entity(reference, title, stringArray(song.artists).join(", ") || text(song.artist) || artistName,
      text(song.album_name) ?? text(song.album), number(song.duration), text(song.image_url) ?? text(song.cover_url), "Spotify metadata via spotDL", true);
  });

  const releasesByKey = new Map<string, NormalizedMusicResult>();
  for (const song of songs) {
    const title = text(song.album_name) ?? text(song.album); if (!title) continue;
    const url = text(song.album_url); const id = externalID(url) ?? stableID(`${artistName}|${title}`);
    if (releasesByKey.has(id)) continue;
    const reference: ExternalEntityReference = { provider: "spotify", entityType: "release", externalID: id, canonicalURL: url };
    releasesByKey.set(id, entity(reference, title, text(song.album_artist) ?? artistName, null, 0,
      text(song.image_url) ?? text(song.cover_url), "Spotify metadata via spotDL"));
  }
  return { artist, releases: [...releasesByKey.values()], tracks };
}

function entity(reference: ExternalEntityReference, title: string, artist: string | null, release: string | null,
                duration: number, artworkURL: string | null, attribution: string, acquirable = false): NormalizedMusicResult {
  return { id: `${reference.provider}:${reference.entityType}:${reference.externalID}`, entityType: reference.entityType, title, artist, release,
    duration, artworkURL, metadataSource: { provider: "spotdl", reference }, audioSource: null,
    acquisition: { provider: reference.provider, reference, method: acquirable ? "spotdl" : "unavailable", allowed: acquirable }, attribution };
}

function runSpotDL(args: string[], timeoutMilliseconds: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn("spotdl", args, { shell: false, stdio: ["ignore", "pipe", "pipe"] });
    const stdout: Buffer[] = []; const stderr: Buffer[] = [];
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("spotdl.timeout")); }, timeoutMilliseconds);
    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk)); child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
    child.on("error", (error) => { clearTimeout(timer); reject(error); });
    child.on("close", (code) => { clearTimeout(timer); code === 0 ? resolve(Buffer.concat(stdout).toString())
      : reject(new Error(Buffer.concat(stderr).toString().slice(-2_000) || `spotdl.exit_${code}`)); });
  });
}

function isRecord(value: unknown): value is JSONRecord { return typeof value === "object" && value !== null && !Array.isArray(value); }
function text(value: unknown): string | null { return typeof value === "string" && value.trim() ? value.trim() : null; }
function number(value: unknown): number { const parsed = Number(value); return Number.isFinite(parsed) && parsed > 0 ? parsed : 0; }
function stringArray(value: unknown): string[] { return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : []; }
function externalID(value: string | null): string | null { return value?.match(/open\.spotify\.com\/(?:artist|track|album)\/([A-Za-z0-9]+)/)?.[1] ?? null; }
function stableID(value: string): string { return createHash("sha256").update(value.toLocaleLowerCase()).digest("hex").slice(0, 24); }
