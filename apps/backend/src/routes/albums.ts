import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function albumRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { id: string } }>("/albums/:id", async (req, reply) => {
    const album = await prisma.album.findUnique({
      where: { id: req.params.id },
      include: {
        artist: { select: { id: true, name: true, imageUrl: true } },
        tracks: {
          orderBy: { trackNumber: "asc" },
          select: {
            id: true, title: true, durationMs: true, trackNumber: true,
          },
        },
      },
    });
    if (!album) return reply.status(404).send({ error: "not_found" });

    return {
      id: album.id,
      title: album.title,
      coverUrl: publicCoverUrl(album.coverUrl),
      releaseYear: album.releaseYear,
      artist: {
        id: album.artist.id,
        name: album.artist.name,
        imageUrl: album.artist.imageUrl ? publicCoverUrl(album.artist.imageUrl) : null,
      },
      tracks: album.tracks.map((t) => ({
        id: t.id,
        title: t.title,
        durationMs: t.durationMs,
        trackNumber: t.trackNumber,
        artist: album.artist.name,
        artistId: album.artist.id,
        album: album.title,
        albumId: album.id,
        coverUrl: publicCoverUrl(album.coverUrl),
      })),
    };
  });
}
