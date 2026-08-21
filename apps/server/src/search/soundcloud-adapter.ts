import type { MusicSourceAdapter, MusicSourceSearchResult, NormalizedMusicResult } from "./models.js";
import { MusicProviderError } from "./models.js";

interface TokenResponse { access_token: string; refresh_token?: string; expires_in: number }
interface SoundCloudUser { username?: string; permalink_url?: string }
interface SoundCloudTrack {
  id?: number | string; urn?: string; title?: string; duration?: number; artwork_url?: string | null;
  permalink_url?: string | null; downloadable?: boolean; download_url?: string | null; access?: string;
  user?: SoundCloudUser; publisher_metadata?: { artist?: string; album_title?: string } | null;
}
interface SoundCloudPage { collection?: SoundCloudTrack[] }

export class SoundCloudMusicSourceAdapter implements MusicSourceAdapter {
  readonly id = "soundcloud";
  readonly capabilities = new Set(["search", "stream"] as const);
  private token: { access: string; refresh?: string; expiresAt: number } | undefined;

  constructor(private readonly clientID: string, private readonly clientSecret: string, private readonly fetcher: typeof fetch = fetch) {}

  async search(query: string, limit: number): Promise<MusicSourceSearchResult> {
    const url = new URL("https://api.soundcloud.com/tracks");
    url.searchParams.set("q", query);
    url.searchParams.set("access", "playable");
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("linked_partitioning", "true");
    const response = await this.authorizedFetch(url);
    await this.ensureSuccess(response);
    const payload = await response.json() as SoundCloudPage | SoundCloudTrack[];
    const tracks = Array.isArray(payload) ? payload : payload.collection ?? [];
    return { provider: this.id, items: tracks.map((track) => this.normalize(track)).filter((item): item is NormalizedMusicResult => item !== null) };
  }

  async resolveStream(externalID: string): Promise<string> {
    const response = await this.authorizedFetch(`https://api.soundcloud.com/tracks/${encodeURIComponent(externalID)}/streams`, true);
    await this.ensureSuccess(response);
    const streams = await response.json() as Record<string, string | undefined>;
    const url = streams.hls_aac_160_url ?? streams.hls_mp3_128_url ?? streams.http_mp3_128_url ?? streams.preview_mp3_128_url;
    if (!url) throw new MusicProviderError(this.id, "geo_restricted", "soundcloud.stream_unavailable");
    return url;
  }

  private normalize(track: SoundCloudTrack): NormalizedMusicResult | null {
    const rawID = track.urn ?? track.id;
    if (rawID === undefined || !track.title) return null;
    const id = String(rawID).replace(/^soundcloud:tracks:/, "");
    return {
      id, provider: this.id, title: track.title,
      artist: track.publisher_metadata?.artist ?? track.user?.username ?? "SoundCloud",
      album: track.publisher_metadata?.album_title ?? null,
      duration: Math.max((track.duration ?? 0) / 1000, 0), artworkURL: track.artwork_url ?? null,
      webpageURL: track.permalink_url ?? null,
      streamPath: track.access === "blocked" ? null : `/search/providers/soundcloud/tracks/${encodeURIComponent(id)}/stream`,
      // This adapter intentionally does not proxy original-file downloads yet.
      // The capability remains absent even when SoundCloud metadata says that the
      // creator enabled downloads, so clients cannot offer a non-working action.
      capabilities: ["search", ...(track.access === "blocked" ? [] : ["stream"])],
      attribution: track.permalink_url ? `SoundCloud · ${track.user?.username ?? ""}`.trim() : "SoundCloud",
    } as NormalizedMusicResult;
  }

  private async authorizedFetch(input: string | URL, retry401 = true): Promise<Response> {
    const token = await this.accessToken();
    const response = await this.fetcher(input, { headers: { Accept: "application/json; charset=utf-8", Authorization: `OAuth ${token}` } });
    if (response.status === 401 && retry401) {
      this.token = undefined;
      return this.authorizedFetch(input, false);
    }
    return response;
  }

  private async accessToken(): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now() + 60_000) return this.token.access;
    const body = new URLSearchParams({ grant_type: this.token?.refresh ? "refresh_token" : "client_credentials" });
    if (this.token?.refresh) body.set("refresh_token", this.token.refresh);
    const response = await this.fetcher("https://secure.soundcloud.com/oauth/token", {
      method: "POST", headers: { Accept: "application/json; charset=utf-8", "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${Buffer.from(`${this.clientID}:${this.clientSecret}`).toString("base64")}` }, body,
    });
    if (!response.ok) throw new MusicProviderError(this.id, response.status === 429 ? "rate_limit" : "authentication", "soundcloud.authentication_failed", retryAfter(response));
    const value = await response.json() as TokenResponse;
    this.token = { access: value.access_token, ...(value.refresh_token ? { refresh: value.refresh_token } : {}), expiresAt: Date.now() + value.expires_in * 1000 };
    return value.access_token;
  }

  private async ensureSuccess(response: Response): Promise<void> {
    if (response.ok) return;
    const kind = response.status === 401 ? "authentication" : response.status === 429 ? "rate_limit"
      : response.status === 403 || response.status === 404 || response.status === 406 ? "geo_restricted"
      : response.status >= 500 ? "temporary" : "unavailable";
    throw new MusicProviderError(this.id, kind, `soundcloud.http_${response.status}`, retryAfter(response));
  }
}

function retryAfter(response: Response): number | undefined {
  const header = response.headers.get("retry-after");
  if (header === null) return undefined;
  const value = Number(header);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}
