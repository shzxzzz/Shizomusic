import { and, asc, eq, lte } from "drizzle-orm";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { mkdir, readFile, rename, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { catalogFiles, mediaJobs } from "./db/schema.js";
import { createDatabase } from "./db/client.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");
const storageRoot = process.env.MEDIA_STORAGE_ROOT ?? "/data";
const { db, pool } = createDatabase(databaseURL);
let stopping = false;
process.on("SIGTERM", () => { stopping = true; });
process.on("SIGINT", () => { stopping = true; });

while (!stopping) {
  const [job] = await db.select().from(mediaJobs).where(and(eq(mediaJobs.state, "pending"), lte(mediaJobs.nextAttemptAt, new Date())))
    .orderBy(asc(mediaJobs.createdAt)).limit(1);
  if (!job) { await delay(2_000); continue; }
  const claimed = await db.update(mediaJobs).set({ state: "processing", updatedAt: new Date() })
    .where(and(eq(mediaJobs.id, job.id), eq(mediaJobs.state, "pending"))).returning({ id: mediaJobs.id });
  if (!claimed.length) continue;
  try {
    const [file] = await db.select().from(catalogFiles).where(eq(catalogFiles.id, job.catalogFileId)).limit(1);
    if (!file) throw new Error("catalog_file_missing");
    const path = join(storageRoot, file.storageKey);
    const probe = JSON.parse(await command("ffprobe", ["-v", "error", "-of", "json", "-show_format", "-show_streams", path])) as Probe;
    const audio = probe.streams?.find((stream) => stream.codec_type === "audio");
    if (!audio) throw new Error("audio_stream_missing");
    const tags = { ...(probe.format?.tags ?? {}), ...(audio.tags ?? {}) };
    const artwork = await extractArtwork(path, file.contentHash);
    await db.transaction(async (tx) => {
      await tx.update(catalogFiles).set({
        status: "ready", title: tag(tags, "title") ?? file.title, artist: tag(tags, "artist") ?? file.artist,
        album: tag(tags, "album"), albumArtist: tag(tags, "album_artist", "albumartist"),
        duration: finiteNumber(probe.format?.duration) ?? finiteNumber(audio.duration) ?? 0,
        format: probe.format?.format_name?.split(",")[0] ?? null, codec: audio.codec_name ?? null,
        artworkStorageKey: artwork?.key ?? null, artworkMimeType: artwork ? "image/jpeg" : null,
        probeError: null, updatedAt: new Date(),
      }).where(eq(catalogFiles.id, file.id));
      await tx.update(mediaJobs).set({ state: "complete", updatedAt: new Date(), lastError: null }).where(eq(mediaJobs.id, job.id));
    });
  } catch (error) {
    const attempt = job.attemptCount + 1;
    const terminal = attempt >= 5;
    const message = error instanceof Error ? error.message.slice(0, 2_000) : String(error);
    await db.transaction(async (tx) => {
      await tx.update(mediaJobs).set({ state: terminal ? "failed" : "pending", attemptCount: attempt,
        nextAttemptAt: new Date(Date.now() + Math.min(300, 2 ** attempt) * 1_000), lastError: message, updatedAt: new Date() })
        .where(eq(mediaJobs.id, job.id));
      if (terminal) await tx.update(catalogFiles).set({ status: "failed", probeError: message, updatedAt: new Date() }).where(eq(catalogFiles.id, job.catalogFileId));
    });
  }
}
await pool.end();

async function extractArtwork(source: string, contentHash: string): Promise<{ key: string } | null> {
  const temporary = join(storageRoot, "work", `${contentHash}.tmp.jpg`);
  await mkdir(dirname(temporary), { recursive: true });
  try {
    await command("ffmpeg", ["-v", "error", "-y", "-i", source, "-map", "0:v:0", "-frames:v", "1", "-vf", "scale=min(1200\\,iw):-2", temporary]);
    const bytes = await readFile(temporary);
    const hash = createHash("sha256").update(bytes).digest("hex");
    const key = join("artwork", hash.slice(0, 2), `${hash}.jpg`);
    const destination = join(storageRoot, key);
    await mkdir(dirname(destination), { recursive: true });
    try { await rename(temporary, destination); } catch { await rm(temporary, { force: true }); }
    return { key };
  } catch { await rm(temporary, { force: true }); return null; }
}

function command(executable: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"] });
    const output: Buffer[] = []; const errors: Buffer[] = [];
    child.stdout.on("data", (value: Buffer) => output.push(value));
    child.stderr.on("data", (value: Buffer) => errors.push(value));
    child.on("error", reject);
    child.on("close", (code) => code === 0 ? resolve(Buffer.concat(output).toString("utf8")) : reject(new Error(Buffer.concat(errors).toString("utf8") || `${executable} exited ${code}`)));
  });
}
function tag(tags: Record<string, string>, ...names: string[]): string | null {
  const entries = Object.entries(tags);
  for (const name of names) { const value = entries.find(([key]) => key.toLowerCase() === name)?.[1]?.trim(); if (value) return value; }
  return null;
}
function finiteNumber(value: string | undefined): number | null { const number = Number(value); return Number.isFinite(number) ? number : null; }
function delay(milliseconds: number): Promise<void> { return new Promise((resolve) => setTimeout(resolve, milliseconds)); }
interface Probe { streams?: Array<{ codec_type?: string; codec_name?: string; duration?: string; tags?: Record<string, string> }>; format?: { format_name?: string; duration?: string; tags?: Record<string, string> } }
