import { describe, expect, test } from "vitest";
import { MemoryAcquisitionStore } from "../src/acquisition/memory-store.js";
import { validateAcquisitionRequest } from "../src/acquisition/models.js";

describe("acquisition jobs", () => {
  test("uses a stable external reference and queues an idempotent-shaped job", async () => {
    const request = validateAcquisitionRequest({ reference: { provider: "piped", entityType: "track", externalID: "abc123XYZ",
      canonicalURL: "https://www.youtube.com/watch?v=abc123XYZ" }, method: "yt_dlp", title: "Track", artist: "Artist", artworkURL: null });
    const principal = { userId: crypto.randomUUID(), deviceId: crypto.randomUUID(), role: "member" as const };
    const store = new MemoryAcquisitionStore(); const job = await store.create(principal, request);
    expect(job.state).toBe("queued"); expect(job.reference.externalID).toBe("abc123XYZ"); expect(job.progress).toBe(0);
  });

  test("rejects executable arguments disguised as provider URLs", () => {
    expect(() => validateAcquisitionRequest({ reference: { provider: "piped", entityType: "track", externalID: "x", canonicalURL: "file:///etc/passwd" },
      method: "yt_dlp", title: "x" })).toThrow("invalid_acquisition_url");
  });
});
