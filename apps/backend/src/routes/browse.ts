import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string | null | undefined): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function browseRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/browse/home", async (req) => {
    const userId = req.user.sub;

    const [recentTracks, userPlaylists, topAlbums] = await Promise.all([
      prisma.track.findMany({
        orderBy: { createdAt: "desc" },
        take: 10,
        select: {
          id: true, title: true, durationMs: true,
          artist: { select: { name: true } },
          album: { select: { id: true, title: true, coverUrl: true } },
        },
      }),
      prisma.playlist.findMany({
        where: { userId },
        orderBy: { updatedAt: "desc" },
        take: 10,
        select: {
          id: true, name: true, description: true, coverUrl: true, isPublic: true,
          _count: { select: { tracks: true } },
        },
      }),
      prisma.album.findMany({
        orderBy: { releaseYear: "desc" },
        take: 10,
        select: {
          id: true, title: true, coverUrl: true, releaseYear: true,
          artist: { select: { name: true } },
        },
      }),
    ]);

    const shelves = [
      {
        id: "recent",
        title: "Neu hinzugefuegt",
        kind: "tracks" as const,
        tracks: recentTracks.map((t) => ({
          id: t.id,
          title: t.title,
          artist: t.artist.name,
          album: t.album.title,
          albumId: t.album.id,
          coverUrl: publicCoverUrl(t.album.coverUrl),
          durationMs: t.durationMs,
        })),
      },
      {
        id: "playlists",
        title: "Deine Playlists",
        kind: "playlists" as const,
        playlists: userPlaylists.map((p) => ({
          id: p.id,
          name: p.name,
          description: p.description,
          coverUrl: publicCoverUrl(p.coverUrl),
          isPublic: p.isPublic,
          trackCount: p._count.tracks,
        })),
      },
      {
        id: "albums",
        title: "Alben",
        kind: "albums" as const,
        albums: topAlbums.map((a) => ({
          id: a.id,
          title: a.title,
          artist: a.artist.name,
          coverUrl: publicCoverUrl(a.coverUrl),
          releaseYear: a.releaseYear,
        })),
      },
    ];

    // Legacy "tracks" Feld fuer backwards-compat (v0.8 client nutzt das noch)
    return { shelves, tracks: shelves[0]?.tracks ?? [] };
  });
}
