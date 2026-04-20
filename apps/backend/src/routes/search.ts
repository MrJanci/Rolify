import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

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
}
