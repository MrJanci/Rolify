import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { redis } from "../lib/redis.js";

export default async function healthRoutes(app: FastifyInstance) {
  app.get("/health", async () => ({ status: "ok", ts: Date.now() }));

  app.get("/health/deep", async () => {
    const [dbOk, redisOk] = await Promise.all([
      prisma.$queryRaw`SELECT 1`.then(() => true).catch(() => false),
      redis.ping().then((r: string) => r === "PONG").catch(() => false),
    ]);
    const ok = dbOk && redisOk;
    return { status: ok ? "ok" : "degraded", services: { db: dbOk, redis: redisOk } };
  });
}
