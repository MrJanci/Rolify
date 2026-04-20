import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

// Skeleton fuer Woche 4. Volle Implementierung folgt dann.

const CreatePlaylistBody = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  isPublic: z.boolean().default(false),
});

export default async function playlistRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/playlists/me", async (req) => {
    return prisma.playlist.findMany({
      where: { userId: req.user.sub },
      orderBy: { updatedAt: "desc" },
      select: { id: true, name: true, description: true, coverUrl: true, isPublic: true, updatedAt: true },
    });
  });

  app.post("/playlists", async (req) => {
    const body = CreatePlaylistBody.parse(req.body);
    return prisma.playlist.create({
      data: { ...body, userId: req.user.sub },
    });
  });

  // TODO: GET /:id, PATCH /:id, DELETE /:id, POST /:id/tracks, DELETE /:id/tracks/:trackId, PATCH /:id/reorder
}
