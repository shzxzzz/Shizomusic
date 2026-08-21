import type { ExternalEntityReference, MusicSourceAdapter, MusicSourceSearchResult, NormalizedMusicResult } from "./models.js";
import { MusicProviderError } from "./models.js";

type JSONRecord = Record<string, unknown>;
interface InstanceState { baseURL: string; failures: number; openUntil: number }

export class PipedMusicSourceAdapter implements MusicSourceAdapter {
  readonly id = "piped";
  readonly capabilities = new Set(["search", "stream", "acquire"] as const);
  private readonly instances: InstanceState[];
  constructor(instances: string[], private readonly fetcher: typeof fetch = fetch, private readonly timeoutMilliseconds = 6_000,
              private readonly failureThreshold = 3, private readonly cooldownMilliseconds = 60_000) {
    this.instances = instances.filter(Boolean).map((value) => ({ baseURL: value.replace(/\/$/, ""), failures: 0, openUntil: 0 }));
  }

  async search(query: string, limit: number): Promise<MusicSourceSearchResult> {
    const payload = await this.withFallback(async (instance) => {
      const url = new URL(`${instance.baseURL}/search`); url.searchParams.set("q", query); url.searchParams.set("filter", "videos");
      const response = await this.request(instance, url); const json = await response.json() as JSONRecord | unknown[];
      const items = Array.isArray(json) ? json : json.items;
      if (!Array.isArray(items)) throw new MusicProviderError(this.id, "malformed_response", "piped.malformed_response");
      return items;
    });
    return { provider: this.id, items: payload.map((raw) => this.normalize(raw as JSONRecord)).filter((item): item is NormalizedMusicResult => item !== null).slice(0, limit) };
  }

  async resolveAudio(reference: ExternalEntityReference): Promise<string> {
    if (reference.entityType !== "track") throw new MusicProviderError(this.id, "unavailable", "piped.not_playable");
    return this.withFallback(async (instance) => {
      const response = await this.request(instance, new URL(`${instance.baseURL}/streams/${encodeURIComponent(reference.externalID)}`));
      const payload = await response.json() as JSONRecord;
      if (!Array.isArray(payload.audioStreams)) throw new MusicProviderError(this.id, "malformed_response", "piped.malformed_stream_response");
      const streams = payload.audioStreams.map((raw) => raw as JSONRecord).filter((raw) => typeof raw.url === "string")
        .sort((a, b) => Number(b.bitrate ?? 0) - Number(a.bitrate ?? 0));
      const url = streams[0]?.url; if (typeof url !== "string") throw new MusicProviderError(this.id, "geo_restricted", "piped.audio_unavailable");
      return url;
    });
  }

  private normalize(raw: JSONRecord): NormalizedMusicResult | null {
    const externalID = videoID(raw.url); const title = typeof raw.title === "string" ? raw.title : null;
    if (!externalID || !title) return null;
    const reference: ExternalEntityReference = { provider: this.id, entityType: "track", externalID, canonicalURL: `https://www.youtube.com/watch?v=${externalID}` };
    return { id: `${this.id}:track:${externalID}`, entityType: "track", title,
      artist: typeof raw.uploaderName === "string" ? raw.uploaderName : null, release: null,
      duration: Number.isFinite(Number(raw.duration)) ? Number(raw.duration) : 0,
      artworkURL: typeof raw.thumbnail === "string" ? raw.thumbnail : null, metadataSource: { provider: this.id, reference },
      audioSource: { provider: this.id, reference, resolverPath: `/external/audio/${this.id}/track/${encodeURIComponent(externalID)}` },
      acquisition: { provider: this.id, reference, method: "yt_dlp", allowed: true }, attribution: "Piped · YouTube" };
  }

  private async withFallback<T>(operation: (instance: InstanceState) => Promise<T>): Promise<T> {
    let last: unknown = new MusicProviderError(this.id, "unavailable", "piped.no_instances");
    for (const instance of this.instances) {
      if (instance.openUntil > Date.now()) continue;
      try { const result = await operation(instance); instance.failures = 0; instance.openUntil = 0; return result; }
      catch (error) { last = error; instance.failures += 1; if (instance.failures >= this.failureThreshold) instance.openUntil = Date.now() + this.cooldownMilliseconds; }
    }
    throw last;
  }

  private async request(instance: InstanceState, url: URL): Promise<Response> {
    let response: Response;
    try { response = await this.fetcher(url, { signal: AbortSignal.timeout(this.timeoutMilliseconds) }); }
    catch { throw new MusicProviderError(this.id, "temporary", `piped.instance_unavailable:${instance.baseURL}`); }
    if (!response.ok) throw new MusicProviderError(this.id, response.status === 429 ? "rate_limit" : "temporary", `piped.http_${response.status}`, retryAfter(response));
    return response;
  }
}

function videoID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  return (value.match(/[?&]v=([A-Za-z0-9_-]{6,})/) ?? value.match(/\/watch\/([A-Za-z0-9_-]{6,})/))?.[1] ?? null;
}
function retryAfter(response: Response): number | undefined { const value = Number(response.headers.get("retry-after")); return Number.isFinite(value) ? value : undefined; }
