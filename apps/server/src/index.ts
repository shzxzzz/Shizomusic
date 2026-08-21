import { DatabaseAuthStore } from "./auth/database-store.js";
import { buildApp } from "./app.js";
import { createDatabase } from "./db/client.js";
import { DatabaseSyncStore } from "./sync/database-store.js";
import { DatabaseCatalogStore } from "./catalog/database-store.js";
import { CatalogMusicSourceAdapter } from "./search/catalog-adapter.js";
import { DatabaseMusicSearchCache } from "./search/database-cache.js";
import { MusicSearchService } from "./search/service.js";
import { SoundCloudMusicSourceAdapter } from "./search/soundcloud-adapter.js";
import type { MusicSourceAdapter } from "./search/models.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");
const { db, pool } = createDatabase(databaseURL);
const catalogStore = new DatabaseCatalogStore(db, process.env.MEDIA_STORAGE_ROOT ?? "/data");
const searchAdapters: MusicSourceAdapter[] = [new CatalogMusicSourceAdapter(catalogStore)];
if (process.env.SOUNDCLOUD_CLIENT_ID && process.env.SOUNDCLOUD_CLIENT_SECRET) {
  searchAdapters.push(new SoundCloudMusicSourceAdapter(process.env.SOUNDCLOUD_CLIENT_ID, process.env.SOUNDCLOUD_CLIENT_SECRET));
}
const app = buildApp({
  authStore: new DatabaseAuthStore(db),
  syncStore: new DatabaseSyncStore(db),
  catalogStore,
  searchService: new MusicSearchService(searchAdapters, new DatabaseMusicSearchCache(db)),
  readiness: async () => { await pool.query("select 1"); },
});

try {
  await app.listen({ port: Number(process.env.PORT ?? 3000), host: "0.0.0.0" });
} catch (error) {
  app.log.error(error);
  await pool.end();
  process.exit(1);
}
