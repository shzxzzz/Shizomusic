import { and, asc, eq, lte } from "drizzle-orm";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdir, readdir, rename, rm, stat } from "node:fs/promises";
import { dirname, extname, join } from "node:path";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import type { Database } from "../db/client.js";
import { acquisitionExternalReferences, acquisitionJobs, catalogFiles, mediaJobs } from "../db/schema.js";

const maxBytes = Number(process.env.ACQUISITION_MAX_BYTES ?? 536_870_912);
const timeoutMilliseconds = Number(process.env.ACQUISITION_TIMEOUT_MS ?? 1_200_000);

export async function processNextAcquisition(db: Database, storageRoot: string): Promise<boolean> {
  const [job] = await db.select().from(acquisitionJobs).where(and(eq(acquisitionJobs.state, "queued"), lte(acquisitionJobs.nextAttemptAt, new Date())))
    .orderBy(asc(acquisitionJobs.createdAt)).limit(1);
  if (!job) return false;
  const work = join(storageRoot, "acquisitions", job.id);
  const claimed = await db.update(acquisitionJobs).set({ state: "running", progress: 0.02, temporaryDirectory: work, updatedAt: new Date() })
    .where(and(eq(acquisitionJobs.id, job.id), eq(acquisitionJobs.state, "queued"))).returning({ id: acquisitionJobs.id });
  if (!claimed.length) return true;
  try {
    await mkdir(work, { recursive: true });
    const source = await acquire(job, work, db);
    const size = (await stat(source)).size; if (size <= 0 || size > maxBytes) throw coded("size_limit", `downloaded ${size} bytes`);
    await run("ffprobe", ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "json", source], timeoutMilliseconds);
    await db.update(acquisitionJobs).set({ state: "postProcessing", progress: 0.9, updatedAt: new Date() }).where(eq(acquisitionJobs.id, job.id));
    const hash = await digestFile(source); const storageKey = join("objects", hash.slice(0, 2), hash); const destination = join(storageRoot, storageKey);
    await mkdir(dirname(destination), { recursive: true });
    const [existing] = await db.select().from(catalogFiles).where(eq(catalogFiles.contentHash, hash)).limit(1);
    if (!existing) { try { await rename(source, destination); } catch { await rm(source, { force: true }); } }
    await db.transaction(async (tx) => {
      const file = existing ?? (await tx.insert(catalogFiles).values({ contentHash: hash, byteSize: BigInt(size), mimeType: mime(source), storageKey,
        originalFilename: safe(`${job.title}${extname(source) || ".mp3"}`), title: job.title, artist: job.artist ?? "Unknown Artist",
        addedByUserId: job.userId }).returning())[0];
      if (!file) throw coded("catalog_insert_failed", "catalog insert returned no row");
      await tx.insert(acquisitionExternalReferences).values({ provider: job.provider, entityType: job.entityType, externalId: job.externalId, catalogFileId: file.id })
        .onConflictDoUpdate({ target: [acquisitionExternalReferences.provider, acquisitionExternalReferences.entityType, acquisitionExternalReferences.externalId], set: { catalogFileId: file.id } });
      if (!existing) await tx.insert(mediaJobs).values({ catalogFileId: file.id });
      await tx.update(acquisitionJobs).set(existing?.status === "ready" ? { state: "completed", progress: 1, catalogFileId: file.id, completedAt: new Date(), updatedAt: new Date() }
        : { state: "postProcessing", progress: 0.95, catalogFileId: file.id, updatedAt: new Date() }).where(eq(acquisitionJobs.id, job.id));
    });
    await rm(work, { recursive: true, force: true }); return true;
  } catch (error) {
    const attempt = job.attemptCount + 1; const terminal = attempt >= job.maxAttempts;
    const detail = error instanceof Error ? error.message.slice(0, 2_000) : String(error); const code = error instanceof WorkerError ? error.code : "acquisition_failed";
    await db.update(acquisitionJobs).set({ state: terminal ? "failed" : "queued", progress: 0, attemptCount: attempt,
      nextAttemptAt: new Date(Date.now() + Math.min(300, 2 ** attempt) * 1_000), errorCode: code, errorDetail: detail, updatedAt: new Date() })
      .where(eq(acquisitionJobs.id, job.id));
    await rm(work, { recursive: true, force: true }); return true;
  }
}

async function acquire(job: typeof acquisitionJobs.$inferSelect, work: string, db: Database): Promise<string> {
  if (job.entityType !== "track") throw coded("unsupported_entity", "only tracks can be acquired");
  if (job.method === "direct" && job.provider === "audius") {
    const base = (process.env.AUDIUS_API_URL ?? "https://api.audius.co/v1").replace(/\/$/, "");
    const url = new URL(`${base}/tracks/${encodeURIComponent(job.externalId)}/download`);
    if (process.env.AUDIUS_API_KEY) url.searchParams.set("api_key", process.env.AUDIUS_API_KEY);
    const response = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(timeoutMilliseconds) });
    if (!response.ok || !response.body) throw coded("provider_download_failed", `Audius HTTP ${response.status}`);
    const contentLength = Number(response.headers.get("content-length")); if (Number.isFinite(contentLength) && contentLength > maxBytes) throw coded("size_limit", "provider content-length exceeds limit");
    const path = join(work, "source.mp3"); await pipeline(Readable.from(response.body as AsyncIterable<Uint8Array>), createWriteStream(path)); return path;
  }
  if (!job.canonicalUrl) throw coded("source_url_missing", "canonical URL is required");
  validateURL(job.provider, job.canonicalUrl);
  if (job.method === "yt_dlp") {
    const template = join(work, "source.%(ext)s");
    await run("yt-dlp", ["--ignore-config", "--no-playlist", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0",
      "--max-filesize", String(maxBytes), "--socket-timeout", "20", "--retries", "2", "--newline",
      "--progress-template", "download:%(progress._percent_str)s", "-o", template, "--", job.canonicalUrl], timeoutMilliseconds,
      async (line) => updateProgress(db, job.id, line));
  } else if (job.method === "spotdl") {
    await run("spotdl", ["download", job.canonicalUrl, "--format", "mp3", "--max-retries", "2", "--threads", "1", "--overwrite", "force",
      "--output", join(work, "source.{output-ext}")], timeoutMilliseconds, async (line) => updateProgress(db, job.id, line));
  } else throw coded("unsupported_method", `unsupported acquisition method ${job.method}`);
  const files = (await readdir(work)).filter((name) => name.startsWith("source.") && !name.endsWith(".part"));
  if (!files[0]) throw coded("output_missing", "acquisition tool produced no output"); return join(work, files[0]);
}

function validateURL(provider: string, value: string): void {
  const url = new URL(value); if (url.protocol !== "https:") throw coded("invalid_source_url", "only HTTPS sources are allowed");
  if (provider === "piped" && !["youtube.com", "www.youtube.com", "youtu.be", "music.youtube.com"].includes(url.hostname)) throw coded("invalid_source_url", "Piped acquisition must reference YouTube");
  if (provider === "spotify" && !["open.spotify.com"].includes(url.hostname)) throw coded("invalid_source_url", "spotDL acquisition must reference Spotify");
}
async function updateProgress(db: Database, id: string, line: string): Promise<void> {
  const match = line.match(/([0-9]+(?:\.[0-9]+)?)%/); if (!match) return;
  const percent = Number(match[1]); if (Number.isFinite(percent)) await db.update(acquisitionJobs).set({ progress: Math.min(0.85, Math.max(0.03, percent / 120)), updatedAt: new Date() }).where(eq(acquisitionJobs.id, id));
}
function run(executable: string, args: string[], timeout: number, output?: (line: string) => Promise<void>): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"], shell: false }); const stdout: Buffer[] = []; const stderr: Buffer[] = [];
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(coded("timeout", `${executable} exceeded time limit`)); }, timeout);
    child.stdout.on("data", (chunk: Buffer) => { stdout.push(chunk); if (output) for (const line of chunk.toString().split(/\r?\n/)) void output(line); });
    child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk)); child.on("error", (error) => { clearTimeout(timer); reject(error); });
    child.on("close", (code) => { clearTimeout(timer); code === 0 ? resolve(Buffer.concat(stdout).toString()) : reject(coded("tool_failed", Buffer.concat(stderr).toString().slice(-2_000) || `${executable} exited ${code}`)); });
  });
}
async function digestFile(path: string): Promise<string> { const hash = createHash("sha256"); for await (const chunk of createReadStream(path)) hash.update(chunk as Buffer); return hash.digest("hex"); }
function mime(path: string): string { return extname(path).toLowerCase() === ".flac" ? "audio/flac" : "audio/mpeg"; }
function safe(value: string): string { return value.replace(/[\\/\0]/g, "_").slice(0, 240) || "track.mp3"; }
class WorkerError extends Error { constructor(readonly code: string, message: string) { super(message); } }
function coded(code: string, message: string): WorkerError { return new WorkerError(code, message); }
