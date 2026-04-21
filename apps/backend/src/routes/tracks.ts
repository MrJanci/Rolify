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

  // Alle verfuegbaren Tracks (flat, paginated). Fuer Library-"Alle Songs"-Filter.
  app.get<{ Querystring: { limit?: string; offset?: string } }>("/tracks", async (req) => {
    const limit = Math.min(500, parseInt(req.query.limit ?? "100", 10) || 100);
    const offset = Math.max(0, parseInt(req.query.offset ?? "0", 10) || 0);
    const rows = await prisma.track.findMany({
      orderBy: { createdAt: "desc" },
      take: limit,
      skip: offset,
      include: {
        artist: { select: { id: true, name: true } },
        album: { select: { id: true, title: true, coverUrl: true } },
      },
    });
    return {
      tracks: rows.map((t) => ({
        id: t.id,
        title: t.title,
        artist: t.artist.name,
        artistId: t.artist.id,
        album: t.album.title,
        albumId: t.album.id,
        coverUrl: publicCoverUrl(t.album.coverUrl),
        durationMs: t.durationMs,
      })),
    };
  });

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
