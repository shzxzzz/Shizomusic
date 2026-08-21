import type { ExternalEntityReference, MusicSourceAdapter, MusicSourceSearchResult, NormalizedMusicResult } from "./models.js";
import { MusicProviderError } from "./models.js";

type JSONRecord = Record<string, unknown>;

export class AudiusMusicSourceAdapter implements MusicSourceAdapter {
  readonly id = "audius";
  readonly capabilities = new Set(["search", "stream", "acquire"] as const);
  constructor(private readonly baseURL = "https://api.audius.co/v1", private readonly apiKey?: string,
              private readonly fetcher: typeof fetch = fetch, private readonly timeoutMilliseconds = 6_000) {}

  async search(query: string, limit: number): Promise<MusicSourceSearchResult> {
    const endpoints: Array<["track" | "artist" | "release", string]> = [["track", "tracks/search"], ["artist", "users/search"], ["release", "playlists/search"]];
    const settled = await Promise.allSettled(endpoints.map(async ([kind, endpoint]) => {
      const url = new URL(`${this.baseURL.replace(/\/$/, "")}/${endpoint}`);
      url.searchParams.set("query", query); url.searchParams.set("limit", String(limit));
      const response = await this.request(url); const payload = await response.json() as JSONRecord;
      if (!Array.isArray(payload.data)) throw new MusicProviderError(this.id, "malformed_response", "audius.malformed_response");
      return payload.data.map((raw) => this.normalize(kind, raw as JSONRecord)).filter((item): item is NormalizedMusicResult => item !== null);
    }));
    const items = settled.flatMap((value) => value.status === "fulfilled" ? value.value : []);
    if (items.length === 0) { const rejected = settled.find((value) => value.status === "rejected"); if (rejected?.status === "rejected") throw rejected.reason; }
    return { provider: this.id, items: items.slice(0, limit * 3) };
  }

  async resolveAudio(reference: ExternalEntityReference): Promise<string> {
    if (reference.entityType !== "track") throw new MusicProviderError(this.id, "unavailable", "audius.not_playable");
    const url = new URL(`${this.baseURL.replace(/\/$/, "")}/tracks/${encodeURIComponent(reference.externalID)}/stream`);
    if (this.apiKey) url.searchParams.set("api_key", this.apiKey);
    return url.toString();
  }

  private async request(url: URL): Promise<Response> {
    let response: Response;
    try { response = await this.fetcher(url, { headers: this.apiKey ? { "x-api-key": this.apiKey } : {}, signal: AbortSignal.timeout(this.timeoutMilliseconds) }); }
    catch { throw new MusicProviderError(this.id, "temporary", "audius.unavailable"); }
    if (!response.ok) throw new MusicProviderError(this.id, response.status === 429 ? "rate_limit" : response.status === 401 ? "authentication" : "temporary", `audius.http_${response.status}`, retryAfter(response));
    return response;
  }

  private normalize(kind: "track" | "artist" | "release", raw: JSONRecord): NormalizedMusicResult | null {
    const externalID = text(raw.id); if (!externalID) return null;
    const user = object(raw.user); const artwork = object(raw.artwork) ?? object(raw.profilePicture) ?? object(raw.profile_picture);
    const title = kind === "track" ? text(raw.title) : kind === "artist" ? text(raw.name) : text(raw.playlistName) ?? text(raw.playlist_name);
    if (!title) return null;
    const artist = kind === "artist" ? title : text(user?.name) ?? text(user?.handle);
    const permalink = text(raw.permalink);
    const canonicalURL = permalink?.startsWith("/") ? `https://audius.co${permalink}` : permalink;
    const reference: ExternalEntityReference = { provider: this.id, entityType: kind, externalID, canonicalURL };
    const playable = kind === "track" && raw.isStreamable !== false && raw.is_streamable !== false;
    return { id: `${this.id}:${kind}:${externalID}`, entityType: kind, title, artist,
      release: kind === "track" ? text(raw.album) : null, duration: kind === "track" ? finite(raw.duration) : 0,
      artworkURL: text(artwork?._480x480) ?? text(artwork?.["480x480"]) ?? text(artwork?._150x150) ?? text(artwork?.["150x150"]), metadataSource: { provider: this.id, reference },
      audioSource: playable ? { provider: this.id, reference, resolverPath: `/external/audio/${this.id}/${kind}/${encodeURIComponent(externalID)}` } : null,
      acquisition: { provider: this.id, reference, method: kind === "track" ? "direct" : "unavailable", allowed: kind === "track" },
      attribution: artist ? `Audius · ${artist}` : "Audius" };
  }
}

function object(value: unknown): JSONRecord | null { return typeof value === "object" && value !== null ? value as JSONRecord : null; }
function text(value: unknown): string | null { return typeof value === "string" && value.trim() ? value.trim() : typeof value === "number" ? String(value) : null; }
function finite(value: unknown): number { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function retryAfter(response: Response): number | undefined { const value = Number(response.headers.get("retry-after")); return Number.isFinite(value) ? value : undefined; }
