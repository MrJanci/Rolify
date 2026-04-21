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

  /// POST /browse/mixed — generiert Mix-Playlist aus Liked-Tracks + ihre Artists.
  /// Algo (v1 simple): nimm User-Likes als Seed, ziehe Tracks von gleichen Artists + Album-Sisters.
  /// Erstellt eine neue Playlist mit isMixed=true.
  app.post("/browse/mixed", async (req, reply) => {
    const userId = req.user.sub;

    // Seeds: liked Tracks (oder Fallback: recent listening - nicht getrackt, also: recent Tracks)
    const likedTracks = await prisma.libraryTrack.findMany({
      where: { userId },
      select: { trackId: true, track: { select: { artistId: true } } },
      take: 20,
      orderBy: { savedAt: "desc" },
    });

    let seedArtistIds: string[] = [];
    if (likedTracks.length > 0) {
      seedArtistIds = [...new Set(likedTracks.map((l) => l.track.artistId))];
    } else {
      // Fallback: alle Saved-Artists
      const saved = await prisma.savedArtist.findMany({
        where: { userId },
        select: { artistId: true },
        take: 10,
      });
      seedArtistIds = saved.map((s) => s.artistId);
    }

    if (seedArtistIds.length === 0) {
      return reply.status(400).send({ error: "no_seeds", message: "Like ein paar Tracks dann klappt das." });
    }

    // Bau Kandidaten: Tracks der Seed-Artists die der User nicht gelikt hat (sonst boring)
    const likedTrackIds = new Set(likedTracks.map((l) => l.trackId));
    const candidates = await prisma.track.findMany({
      where: {
        artistId: { in: seedArtistIds },
        id: { notIn: [...likedTrackIds] },
      },
      select: { id: true },
      take: 60,
    });

    // Shuffle + nimm 30 (Fisher-Yates mit explicit-swap - noUncheckedIndexedAccess-safe)
    for (let i = candidates.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = candidates[i]!;
      candidates[i] = candidates[j]!;
      candidates[j] = tmp;
    }
    const chosen = candidates.slice(0, 30);
    if (chosen.length === 0) {
      return reply.status(400).send({ error: "no_candidates" });
    }

    // Erstelle Mixed-Playlist
    const playlist = await prisma.playlist.create({
      data: {
        userId,
        name: "Dein Mix vom Tag",
        description: "Algorithmisch aus deinen Likes generiert.",
        isMixed: true,
        isPublic: false,
      },
    });
    await prisma.$transaction(
      chosen.map((t, i) =>
        prisma.playlistTrack.create({
          data: { playlistId: playlist.id, trackId: t.id, position: i },
        })
      )
    );

    return reply.status(201).send({
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      coverUrl: "",
      isPublic: false,
      isMixed: true,
      trackCount: chosen.length,
    });
  });
}
