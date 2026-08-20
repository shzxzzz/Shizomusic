import { DatabaseAuthStore } from "./auth/database-store.js";
import { buildApp } from "./app.js";
import { createDatabase } from "./db/client.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");
const { db, pool } = createDatabase(databaseURL);
const app = buildApp({
  authStore: new DatabaseAuthStore(db),
  readiness: async () => { await pool.query("select 1"); },
});

try {
  await app.listen({ port: Number(process.env.PORT ?? 3000), host: "0.0.0.0" });
} catch (error) {
  app.log.error(error);
  await pool.end();
  process.exit(1);
}
