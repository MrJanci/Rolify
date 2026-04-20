import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

export default async function userRoutes(app: FastifyInstance) {
  // Oeffentliches Profil — keine Auth noetig, aber nur public-safe Felder.
  app.get<{ Params: { id: string } }>("/users/:id", async (req, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: req.params.id },
      select: {
        id: true,
        displayName: true,
        avatarUrl: true,
        bio: true,
        playlists: {
          where: { isPublic: true },
          select: { id: true, name: true, coverUrl: true, description: true },
          take: 20,
        },
      },
    });
    if (!user) return reply.status(404).send({ error: "not_found" });
    return user;
  });
}
