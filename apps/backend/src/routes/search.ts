import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";
import { spotifySearchTracks } from "../lib/spotifyClient.js";

/**
 * pg_trgm similarity-basierte Fuzzy-Suche.
 * Findet Tippfehler, Teil-Treffer, Substring-Matches.
 * GIN-Indexes auf Track.title, Artist.name, Album.title beschleunigen similarity().
 */

const Query = z.object({
  q: z.string().min(1).max(100),
  limit: z.coerce.number().min(1).max(50).default(20),
});

// Threshold fuer similarity (0 .. 1). 0.2 = tolerant fuer Tippfehler; 0.4 = strict.
const SIMILARITY_THRESHOLD = 0.15;

interface TrackSearchRow {
  id: string;
  title: string;
  durationMs: number;
  artistName: string;
  albumId: string;
  albumTitle: string;
  coverUrl: string;
  similarity: number;
}

interface ArtistSearchRow {
  id: string;
  name: string;
  imageUrl: string | null;
  similarity: number;
}

interface AlbumSearchRow {
  id: string;
  title: string;
  coverUrl: string;
  releaseYear: number;
  artistName: string;
  similarity: number;
}

function publicCoverUrl(storedUrl: string): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function searchRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/search", async (req) => {
    const { q, limit } = Query.parse(req.query);

    const [tracks, artists, albums] = await Promise.all([
      prisma.$queryRaw<TrackSearchRow[]>`
        SELECT t.id,
               t.title,
               t."durationMs",
               a.name AS "artistName",
               alb.id AS "albumId",
               alb.title AS "albumTitle",
               alb."coverUrl",
               similarity(t.title, ${q}) AS similarity
          FROM "Track" t
          JOIN "Artist" a ON a.id = t."artistId"
          JOIN "Album"  alb ON alb.id = t."albumId"
         WHERE similarity(t.title, ${q}) > ${SIMILARITY_THRESHOLD}
            OR t.title ILIKE ${"%" + q + "%"}
         ORDER BY similarity DESC
         LIMIT ${limit}
      `,
      prisma.$queryRaw<ArtistSearchRow[]>`
        SELECT id, name, "imageUrl", similarity(name, ${q}) AS similarity
          FROM "Artist"
         WHERE similarity(name, ${q}) > ${SIMILARITY_THRESHOLD}
            OR name ILIKE ${"%" + q + "%"}
         ORDER BY similarity DESC
         LIMIT ${limit}
      `,
      prisma.$queryRaw<AlbumSearchRow[]>`
        SELECT alb.id,
               alb.title,
               alb."coverUrl",
               alb."releaseYear",
               a.name AS "artistName",
               similarity(alb.title, ${q}) AS similarity
          FROM "Album" alb
          JOIN "Artist" a ON a.id = alb."artistId"
         WHERE similarity(alb.title, ${q}) > ${SIMILARITY_THRESHOLD}
            OR alb.title ILIKE ${"%" + q + "%"}
         ORDER BY similarity DESC
         LIMIT ${limit}
      `,
    ]);

    return {
      tracks: tracks.map((t) => ({
        id: t.id,
        title: t.title,
        artist: t.artistName,
        album: t.albumTitle,
        albumId: t.albumId,
        coverUrl: publicCoverUrl(t.coverUrl),
        durationMs: t.durationMs,
      })),
      artists: artists.map((a) => ({
        id: a.id,
        name: a.name,
        imageUrl: a.imageUrl ? publicCoverUrl(a.imageUrl) : null,
      })),
      albums: albums.map((alb) => ({
        id: alb.id,
        title: alb.title,
        artist: alb.artistName,
        coverUrl: publicCoverUrl(alb.coverUrl),
        releaseYear: alb.releaseYear,
      })),
    };
  });

  /// External-Search: Spotify-Katalog + Check welche Tracks wir schon haben/saved/queued.
  /// Response: pro Track {spotifyId, title, artist, ..., localId?, isDownloaded, isLiked, isQueued}
  /// - localId = vorhandener Track.id in DB (null wenn noch nicht gescrapt)
  /// - isDownloaded = lokal in DB und abspielbar
  /// - isLiked = userLibraryTrack existiert
  /// - isQueued = ScrapeJob status QUEUED|RUNNING|PAUSED fuer diesen spotifyId
  app.get("/search/external", async (req, reply) => {
    const { q, limit } = Query.parse(req.query);
    try {
      const hits = await spotifySearchTracks(q, limit);
      if (hits.length === 0) {
        return { tracks: [] };
      }
      const spotifyIds = hits.map((h) => h.spotifyId);
      // Check local-state fuer jeden Hit
      const [localTracks, likedRows, queuedJobs] = await Promise.all([
        prisma.track.findMany({
          where: { spotifyId: { in: spotifyIds } },
          select: { id: true, spotifyId: true, album: { select: { coverUrl: true } } },
        }),
        prisma.libraryTrack.findMany({
          where: {
            userId: req.user.sub,
            track: { spotifyId: { in: spotifyIds } },
          },
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
      const localMap = new Map(localTracks.map((t) => [t.spotifyId!, { id: t.id, cover: t.album.coverUrl }]));
      const likedSet = new Set(likedRows.map((r) => r.track.spotifyId).filter((x): x is string => !!x));
      const queuedSet = new Set(queuedJobs.map((j) => j.playlistUrl.replace("spotify:track:", "")));

      return {
        tracks: hits.map((h) => {
          const local = localMap.get(h.spotifyId);
          return {
            spotifyId: h.spotifyId,
            localId: local?.id ?? null,
            title: h.title,
            artist: h.artist,
            album: h.album,
            albumId: h.albumId,
            coverUrl: h.coverUrl,
            durationMs: h.durationMs,
            isDownloaded: !!local,
            isLiked: likedSet.has(h.spotifyId),
            isQueued: queuedSet.has(h.spotifyId),
          };
        }),
      };
    } catch (err) {
      req.log.error({ err }, "external_search_failed");
      return reply.status(502).send({ error: "spotify_search_failed", message: err instanceof Error ? err.message : "unknown" });
    }
  });

  /// Trigger-Download fuer einen einzelnen Spotify-Track.
  /// Enqueue'd ScrapeJob mit spotify:track:ID Format.
  /// Idempotent: wenn bereits gequeued, gibt existing job zurueck.
  app.post<{ Params: { id: string } }>("/search/external/:id/download", async (req, reply) => {
    const spotifyId = req.params.id;
    if (!/^[a-zA-Z0-9]{10,30}$/.test(spotifyId)) {
      return reply.status(400).send({ error: "invalid_spotify_id" });
    }
    // Schon in DB?
    const existing = await prisma.track.findUnique({
      where: { spotifyId },
      select: { id: true },
    });
    if (existing) {
      return { status: "already_downloaded", localId: existing.id };
    }
    // Schon queued?
    const existingJob = await prisma.scrapeJob.findFirst({
      where: {
        playlistUrl: `spotify:track:${spotifyId}`,
        status: { in: ["QUEUED", "RUNNING", "PAUSED"] },
      },
      select: { id: true, status: true },
    });
    if (existingJob) {
      return { status: "already_queued", jobId: existingJob.id };
    }
    const job = await prisma.scrapeJob.create({
      data: {
        playlistUrl: `spotify:track:${spotifyId}`,
        createdBy: req.user.sub,
      },
    });
    return reply.status(201).send({ status: "queued", jobId: job.id });
  });
}
