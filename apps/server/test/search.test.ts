import { describe, expect, test } from "vitest";
import { AudiusMusicSourceAdapter } from "../src/search/audius-adapter.js";
import { PipedMusicSourceAdapter } from "../src/search/piped-adapter.js";
import type { MusicSearchCache, MusicSourceAdapter, MusicSourceSearchResult, NormalizedMusicResult } from "../src/search/models.js";
import { MusicProviderError } from "../src/search/models.js";
import { MemoryMusicSearchCache, MusicSearchService } from "../src/search/service.js";
import { MemoryExternalMetadataCache, SpotDLArtistMetadataResolver } from "../src/search/spotdl-metadata.js";
import { SpotDLStreamAdapter } from "../src/search/spotdl-stream-adapter.js";

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
      if (url.includes("/search")) return Response.json({ items: [
        { type: "stream", url: "/watch?v=abc123XYZ", title: "Video", uploaderName: "Creator", duration: 90 },
        { type: "channel", url: "/channel/UCartist123", name: "Creator", thumbnail: "https://art.test/artist.jpg" },
        { type: "playlist", url: "/playlist?list=PLrelease123", name: "Release", uploaderName: "Creator" },
      ] });
      return Response.json({ audioStreams: [{ url: "https://temporary.cdn/audio", bitrate: 128000 }] });
    }) as typeof fetch;
    const piped = new PipedMusicSourceAdapter(["https://bad", "https://good"], fetcher);
    const result = await piped.search("x", 10); const track = result.items[0]!;
    expect(track.metadataSource.reference.externalID).toBe("abc123XYZ");
    expect(JSON.stringify(track)).not.toContain("temporary.cdn");
    expect(await piped.resolveAudio(track.metadataSource.reference)).toBe("https://temporary.cdn/audio");
    expect(result.items.map((value) => value.entityType)).toEqual(["track", "artist", "release"]);
    expect(calls.some((url) => url.startsWith("https://good"))).toBe(true);
  });

  test("Piped falls back when a retired API redirects to an HTML page", async () => {
    const calls: string[] = [];
    const fetcher = (async (input: string | URL | Request) => {
      const url = String(input); calls.push(url);
      if (url.startsWith("https://retired")) {
        return new Response("<!doctype html><title>Moved</title>", { headers: { "content-type": "text/html" } });
      }
      return Response.json({ items: [{ type: "stream", url: "/watch?v=abc123XYZ", title: "Video" }] });
    }) as typeof fetch;
    const piped = new PipedMusicSourceAdapter(["https://retired", "https://current"], fetcher);

    const result = await piped.search("x", 10);

    expect(result.items).toHaveLength(1);
    expect(calls).toEqual([
      "https://retired/search?q=x&filter=all",
      "https://current/search?q=x&filter=all",
    ]);
  });

  test("spotDL metadata builds an artist page with releases and acquirable tracks", async () => {
    const metadata = artistFixture();
    const resolver = new SpotDLArtistMetadataResolver(async (args) => {
      expect(args).toEqual(["artist", "17 Seventeen"]); return metadata;
    });
    const result = await resolver.resolveArtist("17 Seventeen");
    expect(result.artist.title).toBe("17 Seventeen");
    expect(result.artist.metadataSource.reference.externalID).toBe("artist17");
    expect(result.releases.map((value) => [value.title, value.releaseType])).toEqual([
      ["Album A", "album"], ["Single B", "single"], ["Collection C", "compilation"],
    ]);
    expect(result.tracks).toHaveLength(4);
    expect(result.tracks.every((value) => value.acquisition.method === "spotdl" && value.acquisition.allowed)).toBe(true);
    const release = await new SpotDLArtistMetadataResolver(async () => JSON.stringify(JSON.parse(metadata).releases[0])).resolveRelease("albumAAAA");
    expect(release.tracks.map((value) => [value.discNumber, value.trackNumber, value.title])).toEqual([
      [1, 1, "Prelude"], [1, 2, "Second"], [2, 1, "First"],
    ]);
    await expect(new SpotDLArtistMetadataResolver(async () => "not-json").resolveArtist("Broken"))
      .rejects.toMatchObject({ kind: "malformed_response" });
  });

  test("spotDL metadata serves an expired cache when refresh fails", async () => {
    const cache = new MemoryExternalMetadataCache();
    const warm = new SpotDLArtistMetadataResolver(async () => artistFixture(), cache, 100, -1);
    await warm.resolveArtist("17 Seventeen");
    const offline = new SpotDLArtistMetadataResolver(async () => { throw new Error("offline"); }, cache);
    expect((await offline.resolveArtist("17 Seventeen")).releases).toHaveLength(3);
  });

  test("spotDL stream resolver validates URLs and caches successful resolutions", async () => {
    let calls = 0;
    const adapter = new SpotDLStreamAdapter(async (args) => {
      calls += 1; expect(args.slice(0, 2)).toEqual(["url", "https://open.spotify.com/track/trackOne123"]);
      return "diagnostic\nhttps://audio.example.test/file.m4a\n";
    });
    const reference = { provider: "spotify", entityType: "track" as const, externalID: "trackOne123", canonicalURL: null };
    expect(await adapter.resolveAudio(reference)).toBe("https://audio.example.test/file.m4a");
    expect(await adapter.resolveAudio(reference)).toBe("https://audio.example.test/file.m4a");
    expect(calls).toBe(1);
    const unsafe = new SpotDLStreamAdapter(async () => "https://127.0.0.1/private");
    await expect(unsafe.resolveAudio(reference)).rejects.toMatchObject({ kind: "unavailable" });
  });

  test("spotDL stream resolver caps concurrency and reports runner timeouts", async () => {
    let active = 0; let maximum = 0;
    const limited = new SpotDLStreamAdapter(async () => {
      active += 1; maximum = Math.max(maximum, active);
      await new Promise((resolve) => setTimeout(resolve, 5)); active -= 1;
      return "https://audio.example.test/limited.m4a";
    }, 100, 1_000, 2);
    await Promise.all(["trackOne123", "trackTwo123", "trackThree123"].map((externalID) => limited.resolveAudio(
      { provider: "spotify", entityType: "track", externalID, canonicalURL: null })));
    expect(maximum).toBe(2);
    const timeout = new SpotDLStreamAdapter(async () => { throw new Error("spotdl.timeout"); });
    await expect(timeout.resolveAudio({ provider: "spotify", entityType: "track", externalID: "trackTimeout1", canonicalURL: null }))
      .rejects.toMatchObject({ kind: "temporary", message: "spotdl.timeout" });
  });

  test("spotDL playback resolver is signed and rejects missing signatures", async () => {
    const metadata = new SpotDLArtistMetadataResolver(async () => artistFixture());
    const stream = new SpotDLStreamAdapter(async () => "https://audio.example.test/signed.m4a");
    const service = new MusicSearchService([stream], new MemoryMusicSearchCache(), metadata, "test-playback-secret");
    const track = (await service.artistLibrary("17 Seventeen")).tracks.find(
      (value) => value.metadataSource.reference.externalID === "trackOne123")!;
    const resolver = new URL(track.audioSource!.resolverPath!, "https://server.test");

    await expect(service.resolveAudio("spotdl", "track", "trackOne123")).rejects.toMatchObject({ kind: "authentication" });
    await expect(service.resolveAudio("spotdl", "track", "trackOne123",
      resolver.searchParams.get("expires")!, resolver.searchParams.get("signature")!))
      .resolves.toBe("https://audio.example.test/signed.m4a");
  });

  test("an acquired external reference wins over the spotDL resolver", async () => {
    const catalogTrack = item("catalog");
    catalogTrack.audioSource = { provider: "catalog", reference: catalogTrack.metadataSource.reference, resolverPath: "/catalog/files/hash" };
    const catalog: MusicSourceAdapter = {
      id: "catalog", capabilities: new Set(["search", "stream"]),
      search: async () => ({ provider: "catalog", items: [] }),
      lookupExternal: async (reference) => reference.externalID === "trackOne123" ? catalogTrack : null,
    };
    const metadata = new SpotDLArtistMetadataResolver(async () => artistFixture());
    const service = new MusicSearchService([catalog, new SpotDLStreamAdapter(async () => "https://audio.example.test/fallback.m4a")],
      new MemoryMusicSearchCache(), metadata);

    const tracks = (await service.artistLibrary("17 Seventeen")).tracks;

    expect(tracks.find((track) => track.metadataSource.reference.externalID === "trackOne123")?.audioSource?.provider).toBe("catalog");
    expect(tracks.find((track) => track.metadataSource.reference.externalID === "trackTwo123")?.audioSource?.provider).toBe("spotdl");
  });
});

function artistFixture(): string {
  return JSON.stringify({ artist: { id: "artist17", name: "17 Seventeen", url: "https://open.spotify.com/artist/artist17" }, releases: [
    { id: "albumAAAA", title: "Album A", artist: "17 Seventeen", url: "https://open.spotify.com/album/albumAAAA", releaseType: "album",
      releaseDate: "2025-01-02", artworkURL: "https://art.test/a.jpg", tracks: [
        { id: "trackOne123", title: "First", artist: "17 Seventeen", duration: 120, discNumber: 2, trackNumber: 1 },
        { id: "trackTwo123", title: "Second", artist: "17 Seventeen, Guest", duration: 130, discNumber: 1, trackNumber: 2 },
        { id: "trackFour12", title: "Prelude", artist: "17 Seventeen", duration: 90, discNumber: 1, trackNumber: 1 },
      ] },
    { id: "singleBBBB", title: "Single B", artist: "17 Seventeen", url: "https://open.spotify.com/album/singleBBBB", releaseType: "single",
      releaseDate: "2026-03-04", tracks: [{ id: "trackThree123", title: "Third", artist: "17 Seventeen", duration: 140, discNumber: 1, trackNumber: 1 }] },
    { id: "compCCCC", title: "Collection C", artist: "17 Seventeen", url: "https://open.spotify.com/album/compCCCC", releaseType: "compilation",
      releaseDate: "2026-07-08", tracks: [{ id: "trackOne123", title: "First", artist: "17 Seventeen", duration: 120, discNumber: 1, trackNumber: 4 }] },
  ] });
}
