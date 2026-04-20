import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

// Skeleton fuer Woche 4. Erweitert spaeter mit recently-played, made-for-you etc.

export default async function browseRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/browse/home", async () => {
    const [newReleases, trending] = await Promise.all([
      prisma.album.findMany({
        orderBy: { releaseYear: "desc" },
        take: 10,
        include: { artist: true },
      }),
      prisma.track.findMany({
        orderBy: { createdAt: "desc" },
        take: 20,
        include: { artist: true, album: { select: { coverUrl: true } } },
      }),
    ]);
    return { newReleases, trending };
  });
}
