ALTER TABLE "provider_search_tracks" ADD COLUMN "entity_type" text DEFAULT 'track' NOT NULL;
ALTER TABLE "provider_search_tracks" ADD COLUMN "canonical_url" text;
ALTER TABLE "provider_search_tracks" ADD COLUMN "metadata_provider" text DEFAULT 'catalog' NOT NULL;
ALTER TABLE "provider_search_tracks" ADD COLUMN "audio_provider" text;
ALTER TABLE "provider_search_tracks" ADD COLUMN "acquisition_method" text DEFAULT 'unavailable' NOT NULL;
DROP INDEX "provider_search_tracks_provider_external_unique";
CREATE UNIQUE INDEX "provider_search_tracks_provider_entity_external_unique" ON "provider_search_tracks" ("provider", "entity_type", "external_id");
CREATE TABLE "acquisition_jobs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL REFERENCES "users"("id") ON DELETE cascade,
  "device_id" uuid NOT NULL REFERENCES "devices"("id") ON DELETE cascade,
  "provider" text NOT NULL, "entity_type" text NOT NULL, "external_id" text NOT NULL,
  "canonical_url" text, "method" text NOT NULL, "title" text NOT NULL, "artist" text, "artwork_url" text,
  "state" text DEFAULT 'queued' NOT NULL, "progress" double precision DEFAULT 0 NOT NULL,
  "attempt_count" integer DEFAULT 0 NOT NULL, "max_attempts" integer DEFAULT 3 NOT NULL,
  "next_attempt_at" timestamp with time zone DEFAULT now() NOT NULL,
  "error_code" text, "error_detail" text, "temporary_directory" text,
  "catalog_file_id" uuid REFERENCES "catalog_files"("id") ON DELETE set null,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL, "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "completed_at" timestamp with time zone
);
CREATE INDEX "acquisition_jobs_ready_idx" ON "acquisition_jobs" ("state", "next_attempt_at");
CREATE INDEX "acquisition_jobs_user_created_idx" ON "acquisition_jobs" ("user_id", "created_at");
CREATE TABLE "acquisition_external_references" (
  "provider" text NOT NULL, "entity_type" text NOT NULL, "external_id" text NOT NULL,
  "catalog_file_id" uuid NOT NULL REFERENCES "catalog_files"("id") ON DELETE cascade,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE UNIQUE INDEX "acquisition_external_reference_unique" ON "acquisition_external_references" ("provider", "entity_type", "external_id");
