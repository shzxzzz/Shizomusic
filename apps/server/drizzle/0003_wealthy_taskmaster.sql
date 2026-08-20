CREATE TABLE "catalog_files" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"content_hash" text NOT NULL,
	"byte_size" bigint NOT NULL,
	"mime_type" text NOT NULL,
	"storage_key" text NOT NULL,
	"original_filename" text NOT NULL,
	"status" text DEFAULT 'processing' NOT NULL,
	"title" text,
	"artist" text,
	"album" text,
	"album_artist" text,
	"duration" double precision,
	"format" text,
	"codec" text,
	"artwork_storage_key" text,
	"artwork_mime_type" text,
	"probe_error" text,
	"added_by_user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "catalog_files_content_hash_unique" UNIQUE("content_hash"),
	CONSTRAINT "catalog_files_storage_key_unique" UNIQUE("storage_key")
);
--> statement-breakpoint
CREATE TABLE "media_jobs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"catalog_file_id" uuid NOT NULL,
	"state" text DEFAULT 'pending' NOT NULL,
	"attempt_count" integer DEFAULT 0 NOT NULL,
	"next_attempt_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_error" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "upload_parts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"upload_id" uuid NOT NULL,
	"part_number" integer NOT NULL,
	"byte_size" bigint NOT NULL,
	"sha256" text NOT NULL,
	"storage_path" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "upload_sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"device_id" uuid NOT NULL,
	"expected_hash" text NOT NULL,
	"expected_size" bigint NOT NULL,
	"mime_type" text NOT NULL,
	"filename" text NOT NULL,
	"part_size" integer NOT NULL,
	"total_parts" integer NOT NULL,
	"state" text DEFAULT 'uploading' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"completed_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "synced_playlist_items" ALTER COLUMN "version" SET DEFAULT 0;--> statement-breakpoint
ALTER TABLE "synced_playlists" ALTER COLUMN "version" SET DEFAULT 0;--> statement-breakpoint
ALTER TABLE "catalog_files" ADD CONSTRAINT "catalog_files_added_by_user_id_users_id_fk" FOREIGN KEY ("added_by_user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "media_jobs" ADD CONSTRAINT "media_jobs_catalog_file_id_catalog_files_id_fk" FOREIGN KEY ("catalog_file_id") REFERENCES "public"."catalog_files"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "upload_parts" ADD CONSTRAINT "upload_parts_upload_id_upload_sessions_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."upload_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "upload_sessions" ADD CONSTRAINT "upload_sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "upload_sessions" ADD CONSTRAINT "upload_sessions_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "catalog_files_status_created_idx" ON "catalog_files" USING btree ("status","created_at");--> statement-breakpoint
CREATE INDEX "media_jobs_ready_idx" ON "media_jobs" USING btree ("state","next_attempt_at");--> statement-breakpoint
CREATE UNIQUE INDEX "upload_parts_upload_number_unique" ON "upload_parts" USING btree ("upload_id","part_number");--> statement-breakpoint
CREATE INDEX "upload_sessions_user_state_idx" ON "upload_sessions" USING btree ("user_id","state");