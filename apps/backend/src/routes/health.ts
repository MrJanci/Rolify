import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { redis } from "../lib/redis.js";

export default async function healthRoutes(app: FastifyInstance) {
  // Public: minimaler Ping, keine Info-Leaks (kein Hostname, keine Service-Versionen)
  app.get("/health", async () => ({ status: "ok", ts: Date.now() }));

  // Auth-required: leakt sonst Status der internen Services (DB, Redis)
  app.get("/health/deep", { preHandler: app.requireAuth }, async () => {
    const [dbOk, redisOk] = await Promise.all([
      prisma.$queryRaw`SELECT 1`.then(() => true).catch(() => false),
      redis.ping().then((r: string) => r === "PONG").catch(() => false),
    ]);
    const ok = dbOk && redisOk;
    return { status: ok ? "ok" : "degraded", services: { db: dbOk, redis: redisOk } };
  });
}
