import { eq } from "drizzle-orm";
import { devices, invitations, refreshTokens, users } from "./db/schema.js";
import { createDatabase } from "./db/client.js";
import { hashInvitationCode, randomInvitationCode } from "./auth/security.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) fail("DATABASE_URL is required. Run through docker compose or export it first.");
const { db, pool } = createDatabase(databaseURL);
const [command, ...args] = process.argv.slice(2);

try {
  switch (command) {
    case "invite": {
      const hours = numericOption(args, "--hours", 72, 1, 720);
      const code = randomInvitationCode();
      const expiresAt = new Date(Date.now() + hours * 3_600_000);
      await db.insert(invitations).values({ codeHash: hashInvitationCode(code), role: "member", expiresAt });
      console.log(`Invitation: ${code}`);
      console.log(`Expires:    ${expiresAt.toISOString()}`);
      break;
    }
    case "devices": {
      const rows = await db.select({
        id: devices.id, name: devices.name, userId: users.id, user: users.displayName,
        role: users.role, lastSeenAt: devices.lastSeenAt, revokedAt: devices.revokedAt,
      }).from(devices).innerJoin(users, eq(users.id, devices.userId));
      console.table(rows.map((row) => ({ ...row, lastSeenAt: row.lastSeenAt.toISOString(), revokedAt: row.revokedAt?.toISOString() ?? "active" })));
      break;
    }
    case "revoke-device": {
      const id = requiredId(args[0], "device UUID");
      const now = new Date();
      await db.transaction(async (tx) => {
        await tx.update(devices).set({ revokedAt: now }).where(eq(devices.id, id));
        await tx.update(refreshTokens).set({ revokedAt: now }).where(eq(refreshTokens.deviceId, id));
      });
      console.log(`Revoked device ${id}`);
      break;
    }
    case "revoke-user": {
      const id = requiredId(args[0], "user UUID");
      const now = new Date();
      await db.transaction(async (tx) => {
        await tx.update(users).set({ revokedAt: now }).where(eq(users.id, id));
        const ownedDevices = await tx.select({ id: devices.id }).from(devices).where(eq(devices.userId, id));
        for (const device of ownedDevices) {
          await tx.update(devices).set({ revokedAt: now }).where(eq(devices.id, device.id));
          await tx.update(refreshTokens).set({ revokedAt: now }).where(eq(refreshTokens.deviceId, device.id));
        }
      });
      console.log(`Revoked user ${id} and all devices`);
      break;
    }
    default:
      console.log(`ShizoMusic server commands:
  npm run invite -- --hours 72
  npm run devices
  npm run revoke-device -- <device-uuid>
  npm run revoke-user -- <user-uuid>`);
      if (command) process.exitCode = 1;
  }
} finally {
  await pool.end();
}

function numericOption(args: string[], name: string, fallback: number, minimum: number, maximum: number): number {
  const spaced = args.indexOf(name);
  const inline = args.find((value) => value.startsWith(`${name}=`))?.split("=")[1];
  const value = Number(inline ?? (spaced >= 0 ? args[spaced + 1] : fallback));
  if (!Number.isInteger(value) || value < minimum || value > maximum) fail(`${name} must be ${minimum}...${maximum}`);
  return value;
}

function requiredId(value: string | undefined, label: string): string {
  if (!value || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) fail(`Valid ${label} is required`);
  return value;
}

function fail(message: string): never { console.error(message); process.exit(1); }
