import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string | null | undefined): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function libraryRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // ========== LIKED TRACKS ==========

  app.get("/library/tracks", async (req) => {
    const rows = await prisma.libraryTrack.findMany({
      where: { userId: req.user.sub },
      orderBy: { savedAt: "desc" },
      take: 500,
      include: {
        track: {
          include: {
            artist: { select: { id: true, name: true } },
            album: { select: { id: true, title: true, coverUrl: true } },
          },
        },
      },
    });
    return {
      tracks: rows.map((lt) => ({
        id: lt.track.id,
        title: lt.track.title,
        artist: lt.track.artist.name,
        artistId: lt.track.artist.id,
        album: lt.track.album.title,
        albumId: lt.track.album.id,
        coverUrl: publicCoverUrl(lt.track.album.coverUrl),
        durationMs: lt.track.durationMs,
        savedAt: lt.savedAt,
      })),
    };
  });

  // Check ob ein Track gelikt ist
  app.get<{ Params: { id: string } }>("/library/tracks/:id/status", async (req) => {
    const row = await prisma.libraryTrack.findUnique({
      where: { userId_trackId: { userId: req.user.sub, trackId: req.params.id } },
    });
    return { liked: row !== null };
  });

  app.post<{ Params: { id: string } }>("/library/tracks/:id", async (req, reply) => {
    await prisma.libraryTrack
      .upsert({
        where: { userId_trackId: { userId: req.user.sub, trackId: req.params.id } },
        create: { userId: req.user.sub, trackId: req.params.id },
        update: {},
      })
      .catch(() => void 0);
    return reply.status(204).send();
  });

  app.delete<{ Params: { id: string } }>("/library/tracks/:id", async (req, reply) => {
    await prisma.libraryTrack
      .delete({ where: { userId_trackId: { userId: req.user.sub, trackId: req.params.id } } })
      .catch(() => void 0);
    return reply.status(204).send();
  });

  // ========== SAVED ALBUMS ==========

  app.get("/library/albums", async (req) => {
    const rows = await prisma.savedAlbum.findMany({
      where: { userId: req.user.sub },
      orderBy: { savedAt: "desc" },
      take: 200,
      include: { album: { include: { artist: { select: { id: true, name: true } } } } },
    });
    return {
      albums: rows.map((r) => ({
        id: r.album.id,
        title: r.album.title,
        artist: r.album.artist.name,
        artistId: r.album.artist.id,
        coverUrl: publicCoverUrl(r.album.coverUrl),
        releaseYear: r.album.releaseYear,
        savedAt: r.savedAt,
      })),
    };
  });

  app.get<{ Params: { id: string } }>("/library/albums/:id/status", async (req) => {
    const row = await prisma.savedAlbum.findUnique({
      where: { userId_albumId: { userId: req.user.sub, albumId: req.params.id } },
    });
    return { saved: row !== null };
  });

  app.post<{ Params: { id: string } }>("/library/albums/:id", async (req, reply) => {
    await prisma.savedAlbum
      .upsert({
        where: { userId_albumId: { userId: req.user.sub, albumId: req.params.id } },
        create: { userId: req.user.sub, albumId: req.params.id },
        update: {},
      })
      .catch(() => void 0);
    return reply.status(204).send();
  });

  app.delete<{ Params: { id: string } }>("/library/albums/:id", async (req, reply) => {
    await prisma.savedAlbum
      .delete({ where: { userId_albumId: { userId: req.user.sub, albumId: req.params.id } } })
      .catch(() => void 0);
    return reply.status(204).send();
  });

  // ========== SAVED ARTISTS ==========

  app.get("/library/artists", async (req) => {
    const rows = await prisma.savedArtist.findMany({
      where: { userId: req.user.sub },
      orderBy: { savedAt: "desc" },
      take: 200,
      include: { artist: true },
    });
    return {
      artists: rows.map((r) => ({
        id: r.artist.id,
        name: r.artist.name,
        imageUrl: r.artist.imageUrl,
        savedAt: r.savedAt,
      })),
    };
  });

  app.get<{ Params: { id: string } }>("/library/artists/:id/status", async (req) => {
    const row = await prisma.savedArtist.findUnique({
      where: { userId_artistId: { userId: req.user.sub, artistId: req.params.id } },
    });
    return { saved: row !== null };
  });

  app.post<{ Params: { id: string } }>("/library/artists/:id", async (req, reply) => {
    await prisma.savedArtist
      .upsert({
        where: { userId_artistId: { userId: req.user.sub, artistId: req.params.id } },
        create: { userId: req.user.sub, artistId: req.params.id },
        update: {},
      })
      .catch(() => void 0);
    return reply.status(204).send();
  });

  app.delete<{ Params: { id: string } }>("/library/artists/:id", async (req, reply) => {
    await prisma.savedArtist
      .delete({ where: { userId_artistId: { userId: req.user.sub, artistId: req.params.id } } })
      .catch(() => void 0);
    return reply.status(204).send();
  });
}
