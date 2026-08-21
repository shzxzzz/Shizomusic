CREATE TABLE "provider_search_tracks" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"provider" text NOT NULL,
	"external_id" text NOT NULL,
	"title" text NOT NULL,
	"artist" text NOT NULL,
	"album" text,
	"duration" double precision DEFAULT 0 NOT NULL,
	"artwork_url" text,
	"webpage_url" text,
	"stream_path" text,
	"capabilities" jsonb NOT NULL,
	"attribution" text,
	"last_query" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "provider_search_tracks_provider_external_unique" ON "provider_search_tracks" USING btree ("provider","external_id");--> statement-breakpoint
CREATE INDEX "provider_search_tracks_query_idx" ON "provider_search_tracks" USING btree ("last_query","updated_at");