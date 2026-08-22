CREATE TABLE "external_metadata_cache" (
  "key" text PRIMARY KEY NOT NULL,
  "payload" jsonb NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX "external_metadata_cache_expiry_idx" ON "external_metadata_cache" ("expires_at");
