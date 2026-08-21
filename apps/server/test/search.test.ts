import { describe, expect, test } from "vitest";
import type { MusicSearchCache, MusicSourceAdapter, MusicSourceSearchResult } from "../src/search/models.js";
import { MusicProviderError } from "../src/search/models.js";
import { MusicSearchService } from "../src/search/service.js";
import { SoundCloudMusicSourceAdapter } from "../src/search/soundcloud-adapter.js";

class RecordingCache implements MusicSearchCache {
  saved: string[] = [];
  async save(_query: string, result: MusicSourceSearchResult): Promise<void> { this.saved.push(result.provider); }
}

function adapter(id: string, operation: () => Promise<MusicSourceSearchResult>): MusicSourceAdapter {
  return { id, capabilities: new Set(["search"]), search: operation };
}

describe("music source search", () => {
  test("keeps successful catalog results when SoundCloud fails and persists before returning", async () => {
    const cache = new RecordingCache();
    const catalog = adapter("catalog", async () => ({ provider: "catalog", items: [{
      id: "local-1", provider: "catalog", title: "Local result", artist: "Artist", album: null,
      duration: 10, artworkURL: null, webpageURL: null, streamPath: "/catalog/files/hash",
      capabilities: ["search", "stream", "download"], attribution: "Owner",
    }] }));
    const soundcloud = adapter("soundcloud", async () => {
      throw new MusicProviderError("soundcloud", "rate_limit", "soundcloud.http_429", 20);
    });
    const result = await new MusicSearchService([catalog, soundcloud], cache).search("test");
    expect(result.results.map((item) => item.title)).toEqual(["Local result"]);
    expect(result.failures).toEqual([{ provider: "soundcloud", kind: "rate_limit", message: "soundcloud.http_429", retryAfterSeconds: 20 }]);
    expect(cache.saved).toEqual(["catalog"]);
  });

  test("retries only the requested provider", async () => {
    const calls: string[] = [];
    const service = new MusicSearchService([
      adapter("catalog", async () => { calls.push("catalog"); return { provider: "catalog", items: [] }; }),
      adapter("soundcloud", async () => { calls.push("soundcloud"); return { provider: "soundcloud", items: [] }; }),
    ], new RecordingCache());
    await service.search("test", 10, "soundcloud");
    expect(calls).toEqual(["soundcloud"]);
  });

  test("SoundCloud uses OAuth, refreshes after 401, normalizes branding and resolves a fresh stream", async () => {
    const calls: Array<{ url: string; authorization?: string }> = [];
    let tokenNumber = 0;
    let searchNumber = 0;
    const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      const authorization = new Headers(init?.headers).get("authorization") ?? undefined;
      calls.push({ url, ...(authorization ? { authorization } : {}) });
      if (url.includes("/oauth/token")) {
        tokenNumber += 1;
        return Response.json({ access_token: `token-${tokenNumber}`, refresh_token: `refresh-${tokenNumber}`, expires_in: 3600 });
      }
      if (url.includes("/tracks?") && searchNumber++ === 0) return Response.json({}, { status: 401 });
      if (url.includes("/tracks?")) return Response.json({ collection: [{
        id: 42, title: "Cloud song", duration: 125_000, access: "playable", downloadable: true,
        download_url: "https://api.soundcloud.com/tracks/42/download", artwork_url: "https://i1.sndcdn.com/art.jpg",
        permalink_url: "https://soundcloud.com/artist/cloud-song", user: { username: "Artist" },
      }] });
      if (url.includes("/tracks/42/streams")) return Response.json({ hls_aac_160_url: "https://cf-media.sndcdn.com/fresh.m3u8" });
      return Response.json({}, { status: 404 });
    }) as typeof fetch;
    const soundcloud = new SoundCloudMusicSourceAdapter("client", "secret", fetcher);
    const result = await soundcloud.search("cloud", 10);
    expect(result.items[0]?.capabilities).toEqual(["search", "stream"]);
    expect(result.items[0]?.attribution).toContain("SoundCloud");
    expect(await soundcloud.resolveStream("42")).toBe("https://cf-media.sndcdn.com/fresh.m3u8");
    expect(calls.some((call) => call.authorization === "OAuth token-2")).toBe(true);
  });
});
