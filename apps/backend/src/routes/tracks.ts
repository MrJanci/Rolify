import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

// Skeleton fuer Woche 4.

export default async function trackRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { id: string } }>("/tracks/:id", async (req, reply) => {
    const track = await prisma.track.findUnique({
      where: { id: req.params.id },
      include: { artist: true, album: true },
    });
    if (!track) return reply.status(404).send({ error: "not_found" });
    // Wichtig: masterKey NIE zurueckgeben.
    const { masterKey: _omit, ...safe } = track;
    return safe;
  });

  app.get<{ Params: { id: string } }>("/albums/:id", async (req, reply) => {
    const album = await prisma.album.findUnique({
      where: { id: req.params.id },
      include: {
        artist: true,
        tracks: { orderBy: { trackNumber: "asc" }, select: { id: true, title: true, durationMs: true, trackNumber: true } },
      },
    });
    if (!album) return reply.status(404).send({ error: "not_found" });
    return album;
  });

  app.get<{ Params: { id: string } }>("/artists/:id/top-tracks", async (req) => {
    return prisma.track.findMany({
      where: { artistId: req.params.id },
      orderBy: { createdAt: "desc" },
      take: 10,
      select: { id: true, title: true, durationMs: true, album: { select: { id: true, coverUrl: true } } },
    });
  });
}
