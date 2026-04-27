import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

/// Lyrics-API mit lazy LRClib-Cache.
///
/// Erster Call zu /tracks/:id/lyrics:
///   - Cache-miss → fetch lrclib.net → speichere in Lyrics-Tabelle → response
///   - Cache-hit → response direkt aus DB
///
/// Cache-Strategy: forever (Lyrics aendern sich nie, LRClib ist stabil).

interface LRClibResponse {
  id?: number;
  trackName?: string;
  artistName?: string;
  albumName?: string;
  duration?: number;
  syncedLyrics?: string | null;
  plainLyrics?: string | null;
}

async function fetchLrclib(opts: {
  track: string;
  artist: string;
  album: string;
  duration: number;
}): Promise<LRClibResponse | null> {
  const params = new URLSearchParams({
    track_name: opts.track,
    artist_name: opts.artist,
    album_name: opts.album,
    duration: String(Math.round(opts.duration)),
  });
  try {
    const res = await fetch(`https://lrclib.net/api/get?${params.toString()}`, {
      headers: { "User-Agent": "Rolify/0.17 (+https://github.com/MrJanci/Rolify)" },
    });
    if (res.status === 404) {
      // Try search-fallback: less strict matching
      const searchRes = await fetch(
        `https://lrclib.net/api/search?${new URLSearchParams({
          track_name: opts.track,
          artist_name: opts.artist,
        }).toString()}`,
        { headers: { "User-Agent": "Rolify/0.17" } },
      );
      if (!searchRes.ok) return null;
      const arr = (await searchRes.json()) as LRClibResponse[];
      return arr.length > 0 ? arr[0]! : null;
    }
    if (!res.ok) return null;
    return (await res.json()) as LRClibResponse;
  } catch {
    return null;
  }
}

export default async function lyricsRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { id: string } }>("/tracks/:id/lyrics", async (req, reply) => {
    const trackId = req.params.id;

    // Cache-Check
    const cached = await prisma.lyrics.findUnique({ where: { trackId } });
    if (cached) {
      return {
        lrcSynced: cached.lrcSynced,
        plain: cached.plain,
        hasSync: !!cached.lrcSynced,
        source: cached.source,
        cached: true,
      };
    }

    // Track holen fuer Lookup-Params
    const track = await prisma.track.findUnique({
      where: { id: trackId },
      include: {
        artist: { select: { name: true } },
        album: { select: { title: true } },
      },
    });
    if (!track) return reply.status(404).send({ error: "track_not_found" });

    // Erster Artist-Name nehmen (falls "Artist1, Artist2"-feature)
    const firstArtist = track.artist.name.split(",")[0]!.trim();
    const lrclib = await fetchLrclib({
      track: track.title,
      artist: firstArtist,
      album: track.album.title,
      duration: track.durationMs / 1000,
    });

    // Cache write (auch bei "none"-Result, damit wir nicht spam'n)
    const lrcSynced = lrclib?.syncedLyrics || null;
    const plain = lrclib?.plainLyrics || null;
    await prisma.lyrics.create({
      data: {
        trackId,
        lrcSynced,
        plain,
        source: lrclib ? "lrclib" : "none",
      },
    }).catch(() => void 0);  // ignore race-condition duplicate

    return {
      lrcSynced,
      plain,
      hasSync: !!lrcSynced,
      source: lrclib ? "lrclib" : "none",
      cached: false,
    };
  });
}
