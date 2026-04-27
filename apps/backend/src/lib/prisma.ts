import { PrismaClient } from "@prisma/client";

/// Prisma-Pool-Size: default ist `cpus*2+1` was auf Pi 5 nur 9 ergibt.
/// /browse/home macht 7 parallele Queries → bei 2 concurrent users = 14, exhausted.
/// PRISMA_CONNECTION_LIMIT in .env override-bar (default 20 = passt fuer Pi).
const POOL = parseInt(process.env["PRISMA_CONNECTION_LIMIT"] ?? "20", 10);

function buildDatabaseUrl(): string | undefined {
  const raw = process.env["DATABASE_URL"];
  if (!raw) return undefined;
  // Wenn schon connection_limit dran ist, lass es. Sonst anhaengen.
  if (raw.includes("connection_limit=")) return raw;
  const sep = raw.includes("?") ? "&" : "?";
  return `${raw}${sep}connection_limit=${POOL}&pool_timeout=20`;
}

export const prisma = new PrismaClient({
  log: process.env["NODE_ENV"] === "development" ? ["query", "warn", "error"] : ["warn", "error"],
  datasources: { db: { url: buildDatabaseUrl() ?? "" } },
});
