import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string | null | undefined): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function artistRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { id: string } }>("/artists/:id", async (req, reply) => {
    const artist = await prisma.artist.findUnique({
      where: { id: req.params.id },
      include: {
        albums: {
          orderBy: { releaseYear: "desc" },
          select: { id: true, title: true, coverUrl: true, releaseYear: true },
        },
        tracks: {
          take: 5,
          orderBy: { createdAt: "desc" },
          include: {
            album: { select: { id: true, title: true, coverUrl: true } },
          },
        },
      },
    });
    if (!artist) return reply.status(404).send({ error: "not_found" });

    return {
      id: artist.id,
      name: artist.name,
      imageUrl: publicCoverUrl(artist.imageUrl),
      topTracks: artist.tracks.map((t) => ({
        id: t.id,
        title: t.title,
        durationMs: t.durationMs,
        trackNumber: t.trackNumber,    // iOS AlbumTrackItem expects this (required)
        artist: artist.name,
        artistId: artist.id,
        album: t.album.title,
        albumId: t.album.id,
        coverUrl: publicCoverUrl(t.album.coverUrl),
      })),
      albums: artist.albums.map((a) => ({
        id: a.id,
        title: a.title,
        coverUrl: publicCoverUrl(a.coverUrl),
        releaseYear: a.releaseYear,
        artist: artist.name,
      })),
    };
  });

  // Back-compat — /artists/:id/top-tracks existierte vorher als eigener Endpoint
  app.get<{ Params: { id: string } }>("/artists/:id/top-tracks", async (req) => {
    const tracks = await prisma.track.findMany({
      where: { artistId: req.params.id },
      orderBy: { createdAt: "desc" },
      take: 10,
      include: { album: { select: { id: true, title: true, coverUrl: true } } },
    });
    return tracks.map((t) => ({
      id: t.id,
      title: t.title,
      durationMs: t.durationMs,
      album: t.album.title,
      albumId: t.album.id,
      coverUrl: publicCoverUrl(t.album.coverUrl),
    }));
  });
}
