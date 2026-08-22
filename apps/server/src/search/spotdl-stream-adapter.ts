import { spawn } from "node:child_process";
import { isIP } from "node:net";
import type { ExternalEntityReference, MusicSourceAdapter, MusicSourceSearchResult } from "./models.js";
import { MusicProviderError } from "./models.js";

export type SpotDLURLRunner = (args: string[], timeoutMilliseconds: number) => Promise<string>;

export class SpotDLStreamAdapter implements MusicSourceAdapter {
  readonly id = "spotdl";
  readonly capabilities = new Set(["stream"] as const);
  private readonly cache = new Map<string, { url: string; expiresAt: number }>();
  private active = 0;
  private readonly waiters: Array<() => void> = [];

  constructor(private readonly runner: SpotDLURLRunner = runSpotDL,
              private readonly timeoutMilliseconds = 20_000,
              private readonly cacheMilliseconds = 3 * 60_000,
              private readonly maxConcurrency = 2) {}

  async search(): Promise<MusicSourceSearchResult> { return { provider: this.id, items: [] }; }

  async resolveAudio(reference: ExternalEntityReference): Promise<string> {
    if (reference.entityType !== "track" || !/^[A-Za-z0-9]{8,64}$/.test(reference.externalID)) {
      throw new MusicProviderError(this.id, "unavailable", "spotdl.invalid_track");
    }
    const cached = this.cache.get(reference.externalID);
    if (cached && cached.expiresAt > Date.now()) return cached.url;
    await this.acquireSlot();
    try {
      const stdout = await this.runner(["url", `https://open.spotify.com/track/${reference.externalID}`, "--audio",
        "youtube-music", "youtube", "soundcloud", "bandcamp", "piped", "--max-retries", "2", "--threads", "1"], this.timeoutMilliseconds);
      const url = extractPublicURL(stdout);
      if (!url) throw new MusicProviderError(this.id, "unavailable", "spotdl.audio_not_found");
      this.cache.set(reference.externalID, { url, expiresAt: Date.now() + this.cacheMilliseconds });
      return url;
    } catch (error) {
      if (error instanceof MusicProviderError) throw error;
      throw new MusicProviderError(this.id, "temporary", error instanceof Error ? error.message : "spotdl.stream_failed");
    } finally { this.releaseSlot(); }
  }

  private async acquireSlot(): Promise<void> {
    if (this.active < this.maxConcurrency) { this.active += 1; return; }
    await new Promise<void>((resolve) => this.waiters.push(resolve)); this.active += 1;
  }
  private releaseSlot(): void { this.active -= 1; this.waiters.shift()?.(); }
}

function extractPublicURL(stdout: string): string | null {
  const candidates = stdout.split(/\r?\n/).map((line) => line.trim()).filter((line) => /^https?:\/\//i.test(line));
  for (const candidate of candidates.reverse()) {
    try {
      const url = new URL(candidate);
      const host = url.hostname.toLowerCase();
      const ip = isIP(host) ? host : null;
      if (url.protocol !== "https:" || host === "localhost" || host.endsWith(".local") || ip && isPrivateIP(ip)) continue;
      return url.toString();
    } catch { continue; }
  }
  return null;
}
function isPrivateIP(value: string): boolean {
  return value === "::1" || value.startsWith("fc") || value.startsWith("fd") || value.startsWith("fe80:")
    || /^10\./.test(value) || /^127\./.test(value) || /^192\.168\./.test(value)
    || /^172\.(1[6-9]|2\d|3[01])\./.test(value) || /^169\.254\./.test(value);
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
