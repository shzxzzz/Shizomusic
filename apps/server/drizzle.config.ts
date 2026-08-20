import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "postgresql://shizomusic:shizomusic@localhost:5432/shizomusic",
  },
  migrations: {
    table: "__drizzle_migrations",
    schema: "drizzle",
  },
});
