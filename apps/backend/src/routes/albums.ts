import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";
import { spotifyDiscoverAlbumTracks } from "../lib/spotifyClient.js";

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

  /// Discover-Tracks fuers Album: Spotify-Album-Tracks holen + mit local-state mergen.
  /// Same response-shape wie /search/external (spotifyId, localId, isDownloaded, isLiked, isQueued).
  /// Frontend nutzt das fuer "Tippen zum Herunterladen"-Pattern in AlbumDetailView.
  app.get<{ Params: { id: string } }>("/albums/:id/discover", async (req, reply) => {
    const album = await prisma.album.findUnique({
      where: { id: req.params.id },
      include: { artist: { select: { name: true } } },
    });
    if (!album) return reply.status(404).send({ error: "not_found" });
    try {
      const hits = await spotifyDiscoverAlbumTracks(album.title, album.artist.name);
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
      req.log.warn({ err }, "album_discover_failed");
      return { tracks: [] };
    }
  });
}
