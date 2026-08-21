import type { MusicSearchCache, MusicSourceAdapter, MusicSourceFailure, NormalizedMusicResult } from "./models.js";
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

  constructor(private readonly adapters: MusicSourceAdapter[], private readonly cache: MusicSearchCache) {
    this.byID = new Map(adapters.map((adapter) => [adapter.id, adapter]));
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
