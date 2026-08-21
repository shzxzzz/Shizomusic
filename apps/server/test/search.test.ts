import { describe, expect, test } from "vitest";
import { AudiusMusicSourceAdapter } from "../src/search/audius-adapter.js";
import { PipedMusicSourceAdapter } from "../src/search/piped-adapter.js";
import type { MusicSearchCache, MusicSourceAdapter, MusicSourceSearchResult, NormalizedMusicResult } from "../src/search/models.js";
import { MusicProviderError } from "../src/search/models.js";
import { MemoryMusicSearchCache, MusicSearchService } from "../src/search/service.js";

class RecordingCache implements MusicSearchCache {
  saved: string[] = [];
  async save(_query: string, result: MusicSourceSearchResult): Promise<void> { this.saved.push(result.provider); }
}
function adapter(id: string, operation: () => Promise<MusicSourceSearchResult>): MusicSourceAdapter { return { id, capabilities: new Set(["search"]), search: operation }; }
function item(provider: string): NormalizedMusicResult {
  const reference = { provider, entityType: "track" as const, externalID: "1", canonicalURL: null };
  return { id: `${provider}:track:1`, entityType: "track", title: provider, artist: "Artist", release: null, duration: 10, artworkURL: null,
    metadataSource: { provider, reference }, audioSource: null, acquisition: { provider, reference, method: "unavailable", allowed: false }, attribution: provider };
}

describe("two-layer music search", () => {
  test("one provider failure does not hide successful results", async () => {
    const cache = new RecordingCache();
    const audius = adapter("audius", async () => ({ provider: "audius", items: [item("audius")] }));
    const piped = adapter("piped", async () => { throw new MusicProviderError("piped", "temporary", "piped.offline"); });
    const result = await new MusicSearchService([audius, piped], cache).search("test");
    expect(result.results.map((value) => value.title)).toEqual(["audius"]);
    expect(result.failures[0]).toMatchObject({ provider: "piped", kind: "temporary" });
    expect(cache.saved).toEqual(["audius"]);
  });

  test("retry invokes only the requested provider", async () => {
    const calls: string[] = [];
    const service = new MusicSearchService([adapter("audius", async () => { calls.push("audius"); return { provider: "audius", items: [] }; }),
      adapter("piped", async () => { calls.push("piped"); return { provider: "piped", items: [] }; })], new RecordingCache());
    await service.search("test", 10, "piped"); expect(calls).toEqual(["piped"]);
  });

  test("returns a cached provider result together with a fresh failure", async () => {
    let online = true; const cache = new MemoryMusicSearchCache();
    const source = adapter("audius", async () => {
      if (!online) throw new MusicProviderError("audius", "temporary", "offline");
      return { provider: "audius", items: [item("audius")] };
    });
    const service = new MusicSearchService([source], cache); await service.search("cached"); online = false;
    const result = await service.search("cached");
    expect(result.results).toHaveLength(1); expect(result.failures).toHaveLength(1);
  });

  test("Audius normalizes three entity types and diagnoses malformed responses", async () => {
    const fetcher = (async (input: string | URL | Request) => {
      const url = String(input);
      if (url.includes("tracks/search")) return Response.json({ data: [{ id: "t1", title: "Track", duration: 42, user: { name: "Artist" }, isStreamable: true, artwork: { _480x480: "https://art.test/track.jpg" } }] });
      if (url.includes("users/search")) return Response.json({ data: [{ id: "u1", name: "Artist" }] });
      return Response.json({ data: [{ id: "p1", playlistName: "Release", user: { name: "Artist" } }] });
    }) as typeof fetch;
    const result = await new AudiusMusicSourceAdapter("https://audius.test/v1", undefined, fetcher).search("x", 10);
    expect(result.items.map((value) => value.entityType)).toEqual(["track", "artist", "release"]);
    expect(result.items[0]?.artworkURL).toBe("https://art.test/track.jpg");
    expect(result.items[0]?.audioSource?.resolverPath).toContain("/external/audio/audius/track/t1");
    const malformed = new AudiusMusicSourceAdapter("https://audius.test/v1", undefined, (async () => Response.json({ nope: [] })) as typeof fetch);
    await expect(malformed.search("x", 10)).rejects.toMatchObject({ kind: "malformed_response" });
  });

  test("Piped falls back and resolves fresh audio without persisting it", async () => {
    const calls: string[] = [];
    const fetcher = (async (input: string | URL | Request) => {
      const url = String(input); calls.push(url);
      if (url.startsWith("https://bad")) throw new Error("offline");
      if (url.includes("/search")) return Response.json({ items: [{ url: "/watch?v=abc123XYZ", title: "Video", uploaderName: "Creator", duration: 90 }] });
      return Response.json({ audioStreams: [{ url: "https://temporary.cdn/audio", bitrate: 128000 }] });
    }) as typeof fetch;
    const piped = new PipedMusicSourceAdapter(["https://bad", "https://good"], fetcher);
    const result = await piped.search("x", 10); const track = result.items[0]!;
    expect(track.metadataSource.reference.externalID).toBe("abc123XYZ");
    expect(JSON.stringify(track)).not.toContain("temporary.cdn");
    expect(await piped.resolveAudio(track.metadataSource.reference)).toBe("https://temporary.cdn/audio");
    expect(calls.some((url) => url.startsWith("https://good"))).toBe(true);
  });
});
