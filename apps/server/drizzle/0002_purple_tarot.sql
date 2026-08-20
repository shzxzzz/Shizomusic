CREATE TABLE "sync_changes" (
	"cursor" bigserial PRIMARY KEY NOT NULL,
	"operation_id" uuid NOT NULL,
	"actor_device_id" uuid NOT NULL,
	"entity_type" text NOT NULL,
	"entity_id" text NOT NULL,
	"operation_type" text NOT NULL,
	"payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_conflicts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"operation_id" uuid NOT NULL,
	"entity_type" text NOT NULL,
	"entity_id" text NOT NULL,
	"reason" text NOT NULL,
	"local_payload" jsonb NOT NULL,
	"server_payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_operations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"actor_user_id" uuid NOT NULL,
	"actor_device_id" uuid NOT NULL,
	"entity_type" text NOT NULL,
	"entity_id" text NOT NULL,
	"operation_type" text NOT NULL,
	"payload" jsonb NOT NULL,
	"client_timestamp" timestamp with time zone NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "synced_playlist_items" (
	"id" uuid PRIMARY KEY NOT NULL,
	"playlist_id" uuid NOT NULL,
	"track_id" text NOT NULL,
	"rank" double precision NOT NULL,
	"created_at" timestamp with time zone NOT NULL,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"version" bigint DEFAULT 0 NOT NULL,
	"last_operation_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "synced_playlists" (
	"id" uuid PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"cover_style" text NOT NULL,
	"custom_cover_data" text,
	"created_at" timestamp with time zone NOT NULL,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"version" bigint DEFAULT 0 NOT NULL,
	"last_operation_id" uuid NOT NULL
);
--> statement-breakpoint
ALTER TABLE "sync_changes" ADD CONSTRAINT "sync_changes_operation_id_sync_operations_id_fk" FOREIGN KEY ("operation_id") REFERENCES "public"."sync_operations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_conflicts" ADD CONSTRAINT "sync_conflicts_operation_id_sync_operations_id_fk" FOREIGN KEY ("operation_id") REFERENCES "public"."sync_operations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_operations" ADD CONSTRAINT "sync_operations_actor_user_id_users_id_fk" FOREIGN KEY ("actor_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_operations" ADD CONSTRAINT "sync_operations_actor_device_id_devices_id_fk" FOREIGN KEY ("actor_device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "sync_changes_cursor_idx" ON "sync_changes" USING btree ("cursor");--> statement-breakpoint
CREATE INDEX "sync_conflicts_operation_idx" ON "sync_conflicts" USING btree ("operation_id");--> statement-breakpoint
CREATE INDEX "synced_playlist_items_playlist_rank" ON "synced_playlist_items" USING btree ("playlist_id","rank");