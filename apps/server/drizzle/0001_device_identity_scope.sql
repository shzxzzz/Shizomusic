DROP INDEX "devices_identifier_unique";--> statement-breakpoint
CREATE UNIQUE INDEX "devices_user_identifier_unique" ON "devices" USING btree ("user_id","device_identifier");