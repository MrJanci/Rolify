import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

// Skeleton fuer Woche 4.

export default async function libraryRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/library/tracks", async (req) => {
    return prisma.libraryTrack.findMany({
      where: { userId: req.user.sub },
      orderBy: { savedAt: "desc" },
      take: 200,
      include: { track: { include: { artist: true, album: true } } },
    });
  });

  app.post<{ Params: { id: string } }>("/library/tracks/:id", async (req, reply) => {
    await prisma.libraryTrack
      .create({ data: { userId: req.user.sub, trackId: req.params.id } })
      .catch(() => void 0);
    return reply.status(204).send();
  });

  app.delete<{ Params: { id: string } }>("/library/tracks/:id", async (req, reply) => {
    await prisma.libraryTrack
      .delete({ where: { userId_trackId: { userId: req.user.sub, trackId: req.params.id } } })
      .catch(() => void 0);
    return reply.status(204).send();
  });
}
