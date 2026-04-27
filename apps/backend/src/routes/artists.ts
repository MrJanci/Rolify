import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";
import { spotifyArtistTopTracks } from "../lib/spotifyClient.js";

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
          // Vorher take:5, viel zu wenig — INNA hat z.B. 20+ Songs in DB.
          take: 50,
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
      take: 50,
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

  /// Discover-Tracks fuer Artist: Spotify-Top-Tracks holen + mit local-state mergen.
  /// Same response-shape wie /search/external + /albums/:id/discover.
  /// Frontend nutzt das fuer "Tippen zum Herunterladen"-Section in ArtistDetailView.
  app.get<{ Params: { id: string } }>("/artists/:id/discover", async (req, reply) => {
    const artist = await prisma.artist.findUnique({
      where: { id: req.params.id },
      select: { id: true, name: true },
    });
    if (!artist) return reply.status(404).send({ error: "not_found" });
    try {
      const hits = await spotifyArtistTopTracks(artist.name);
      if (hits.length === 0) return { tracks: [] };

      const spotifyIds = hits.map((h) => h.spotifyId);
      const [localTracks, likedRows, queuedJobs] = await Promise.all([
        prisma.track.findMany({
          where: { spotifyId: { in: spotifyIds } },
          select: { id: true, spotifyId: true },
        }),
        prisma.libraryTrack.findMany({
          where: { userId: req.user.sub, track: { spotifyId: { in: spotifyIds } } },
          include: { track: { select: { spotifyId: true } } },
        }),
        prisma.scrapeJob.findMany({
          where: {
            status: { in: ["QUEUED", "RUNNING", "PAUSED"] },
            playlistUrl: { in: spotifyIds.map((id) => `spotify:track:${id}`) },
          },
          select: { playlistUrl: true },
        }),
      ]);
      const localMap = new Map(localTracks.map((t) => [t.spotifyId!, t.id]));
      const likedSet = new Set(likedRows.map((r) => r.track.spotifyId).filter((x): x is string => !!x));
      const queuedSet = new Set(queuedJobs.map((j) => j.playlistUrl.replace("spotify:track:", "")));

      return {
        tracks: hits.map((h) => ({
          spotifyId: h.spotifyId,
          localId: localMap.get(h.spotifyId) ?? null,
          title: h.title,
          artist: h.artist,
          album: h.album,
          albumId: h.albumId,
          coverUrl: h.coverUrl,
          durationMs: h.durationMs,
          isDownloaded: localMap.has(h.spotifyId),
          isLiked: likedSet.has(h.spotifyId),
          isQueued: queuedSet.has(h.spotifyId),
        })),
      };
    } catch (err) {
      req.log.warn({ err }, "artist_discover_failed");
      return { tracks: [] };
    }
  });
}
