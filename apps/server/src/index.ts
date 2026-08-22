import { DatabaseAuthStore } from "./auth/database-store.js";
import { buildApp } from "./app.js";
import { createDatabase } from "./db/client.js";
import { DatabaseSyncStore } from "./sync/database-store.js";
import { DatabaseCatalogStore } from "./catalog/database-store.js";
import { CatalogMusicSourceAdapter } from "./search/catalog-adapter.js";
import { DatabaseMusicSearchCache } from "./search/database-cache.js";
import { MusicSearchService } from "./search/service.js";
import { AudiusMusicSourceAdapter } from "./search/audius-adapter.js";
import { PipedMusicSourceAdapter } from "./search/piped-adapter.js";
import type { MusicSourceAdapter } from "./search/models.js";
import { DatabaseAcquisitionStore } from "./acquisition/database-store.js";
import { SpotDLArtistMetadataResolver } from "./search/spotdl-metadata.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");
const { db, pool } = createDatabase(databaseURL);
const catalogStore = new DatabaseCatalogStore(db, process.env.MEDIA_STORAGE_ROOT ?? "/data");
const searchAdapters: MusicSourceAdapter[] = [new CatalogMusicSourceAdapter(catalogStore)];
if (process.env.ENABLE_AUDIUS_SEARCH === "true") {
  searchAdapters.push(new AudiusMusicSourceAdapter(process.env.AUDIUS_API_URL, process.env.AUDIUS_API_KEY));
}
const pipedInstances = (process.env.PIPED_INSTANCES ?? "https://api.piped.private.coffee,https://pipedapi.kavin.rocks,https://pipedapi.leptons.xyz")
  .split(",").map((value) => value.trim()).filter(Boolean);
searchAdapters.push(new PipedMusicSourceAdapter(pipedInstances));
const app = buildApp({
  authStore: new DatabaseAuthStore(db),
  syncStore: new DatabaseSyncStore(db),
  catalogStore,
  searchService: new MusicSearchService(searchAdapters, new DatabaseMusicSearchCache(db), new SpotDLArtistMetadataResolver()),
  acquisitionStore: new DatabaseAcquisitionStore(db),
  readiness: async () => { await pool.query("select 1"); },
});

try {
  await app.listen({ port: Number(process.env.PORT ?? 3000), host: "0.0.0.0" });
} catch (error) {
  app.log.error(error);
  await pool.end();
  process.exit(1);
}
