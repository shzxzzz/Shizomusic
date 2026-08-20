import { createHash } from "node:crypto";
import { describe, expect, test } from "vitest";
import { buildApp } from "../src/app.js";

describe("shared catalog", () => {
  test("resumes multipart uploads, verifies hashes and serves byte ranges", async () => {
    const app = buildApp({ bootstrapInvitationCode: "OWNER-CATALOG" });
    await app.ready();
    const redeem = await app.inject({ method: "POST", url: "/auth/invitations/redeem", payload: { code: "OWNER-CATALOG", deviceIdentifier: "catalog-device", deviceName: "iPhone" } });
    const auth = await app.inject({ method: "POST", url: "/auth/onboarding/complete", payload: { onboardingToken: redeem.json().onboardingToken, displayName: "Owner" } });
    const token = auth.json().accessToken as string;
    const bytes = Buffer.from("resumable-audio-payload");
    const hash = digest(bytes);
    const created = await app.inject({ method: "POST", url: "/catalog/uploads", headers: bearer(token),
      payload: { filename: "track.flac", mimeType: "audio/flac", byteSize: String(bytes.length), sha256: hash, partSize: 10 } });
    expect(created.statusCode).toBe(200);
    const upload = created.json<{ id: string; totalParts: number }>();
    const chunks = [bytes.subarray(0, 10), bytes.subarray(10, 20), bytes.subarray(20)];
    for (const [index, chunk] of chunks.entries()) {
      const response = await app.inject({ method: "PUT", url: `/catalog/uploads/${upload.id}/parts/${index + 1}`,
        headers: { ...bearer(token), "content-type": "application/octet-stream", "x-part-sha256": digest(chunk) }, payload: chunk });
      expect(response.statusCode).toBe(204);
    }
    const resumed = await app.inject({ method: "POST", url: "/catalog/uploads", headers: bearer(token),
      payload: { filename: "track.flac", mimeType: "audio/flac", byteSize: String(bytes.length), sha256: hash, partSize: 10 } });
    expect(resumed.json<{ uploadedParts: number[] }>().uploadedParts).toEqual([1, 2, 3]);
    expect((await app.inject({ method: "POST", url: `/catalog/uploads/${upload.id}/complete`, headers: bearer(token), payload: {} })).statusCode).toBe(200);
    const catalog = await app.inject({ method: "GET", url: "/catalog", headers: bearer(token) });
    expect(catalog.json<{ tracks: unknown[] }>().tracks).toHaveLength(1);
    const range = await app.inject({ method: "GET", url: `/catalog/files/${hash}`, headers: { range: "bytes=2-8" } });
    expect(range.statusCode).toBe(206);
    expect(range.headers.etag).toBe(`"sha256-${hash}"`);
    expect(range.rawPayload).toEqual(bytes.subarray(2, 9));
    const suffix = await app.inject({ method: "GET", url: `/catalog/files/${hash}`, headers: { range: "bytes=-5" } });
    expect(suffix.statusCode).toBe(206);
    expect(suffix.rawPayload).toEqual(bytes.subarray(bytes.length - 5));
    const unchanged = await app.inject({ method: "GET", url: `/catalog/files/${hash}`, headers: { "if-none-match": `"sha256-${hash}"` } });
    expect(unchanged.statusCode).toBe(304);
    const invalid = await app.inject({ method: "GET", url: `/catalog/files/${hash}`, headers: { range: "bytes=999-" } });
    expect(invalid.statusCode).toBe(416);
    await app.close();
  });
});
function digest(value: Buffer): string { return createHash("sha256").update(value).digest("hex"); }
function bearer(token: string) { return { authorization: `Bearer ${token}` }; }
