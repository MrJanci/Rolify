import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function trackRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { id: string } }>("/tracks/:id", async (req, reply) => {
    const track = await prisma.track.findUnique({
      where: { id: req.params.id },
      include: {
        artist: { select: { id: true, name: true } },
        album: { select: { id: true, title: true, coverUrl: true } },
      },
    });
    if (!track) return reply.status(404).send({ error: "not_found" });
    // Wichtig: masterKey NIE zurueckgeben.
    return {
      id: track.id,
      title: track.title,
      durationMs: track.durationMs,
      trackNumber: track.trackNumber,
      isrc: track.isrc,
      artist: track.artist.name,
      artistId: track.artist.id,
      album: track.album.title,
      albumId: track.album.id,
      coverUrl: publicCoverUrl(track.album.coverUrl),
    };
  });
}
