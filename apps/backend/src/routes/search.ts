import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

// Skeleton fuer Woche 4. Volle Impl nutzt pg_trgm + Postgres Full-Text.

const Query = z.object({ q: z.string().min(1).max(100), limit: z.coerce.number().min(1).max(50).default(20) });

export default async function searchRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/search", async (req) => {
    const { q, limit } = Query.parse(req.query);
    const [tracks, artists, albums] = await Promise.all([
      prisma.track.findMany({
        where: { title: { contains: q, mode: "insensitive" } },
        take: limit,
        include: { artist: true, album: { select: { coverUrl: true } } },
      }),
      prisma.artist.findMany({
        where: { name: { contains: q, mode: "insensitive" } },
        take: limit,
      }),
      prisma.album.findMany({
        where: { title: { contains: q, mode: "insensitive" } },
        take: limit,
        include: { artist: true },
      }),
    ]);
    return { tracks, artists, albums };
  });
}
