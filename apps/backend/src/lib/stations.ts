import { prisma } from "./prisma.js";
import { redis } from "./redis.js";
import { env } from "../config.js";

/**
 * Recommended Stations: pro Saved-Artist eine "Radio-Station" aehnlich Spotify's
 * artist-radio. Greift Last.fm's `artist.getsimilar` API auf um aehnliche
 * Kuenstler zu listen — der Frontend-Tile zeigt 3 Faces vom Kuenstler + 2 ahnlichen.
 *
 * Cache: per-User in Redis fuer 6 Stunden (sonst Last.fm-Quota geht hoch).
 * Fallback: wenn keine Saved-Artists, nimmt Top-Tracks-Artists aus PlayHistory.
 */

const LASTFM_KEY = process.env["LASTFM_API_KEY"] ?? "";
const CACHE_TTL = 6 * 3600; // 6 hours
const STATION_LIMIT = 6;

export interface RecommendedStation {
  id: string;
  name: string;        // "Tame Impala Radio"
  subtitle: string;    // "Tame Impala, MGMT, Pond, ..."
  coverUrl: string;    // Artist-Cover des Seeds
  tintHex: string;     // Background-Tint fuer den Card
}

interface LastfmSimilarArtist {
  name: string;
  match?: string;
  image?: { size: string; "#text": string }[];
}

interface CachedStationPayload {
  generatedAt: number;
  stations: RecommendedStation[];
}

const TINT_PALETTE = [
  "#C39BD3", // lavender
  "#7FCBC4", // mint
  "#A2D5C6", // sage
  "#F5B7B1", // coral
  "#85C1E9", // sky
  "#F8C471", // sand
  "#D7BDE2", // rose
  "#76D7C4", // teal
];

function hashTint(seed: string): string {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) | 0;
  return TINT_PALETTE[Math.abs(h) % TINT_PALETTE.length]!;
}

/// Fetch similar artists for `artistName` via Last.fm. Returns max 4 similar names.
async function lastfmSimilarArtists(artistName: string, limit = 4): Promise<string[]> {
  if (!LASTFM_KEY) return [];
  try {
    const url = new URL("https://ws.audioscrobbler.com/2.0/");
    url.searchParams.set("method", "artist.getsimilar");
    url.searchParams.set("artist", artistName);
    url.searchParams.set("api_key", LASTFM_KEY);
    url.searchParams.set("format", "json");
    url.searchParams.set("limit", String(limit));

    const ctrl = new AbortController();
    const tid = setTimeout(() => ctrl.abort(), 8000);
    const res = await fetch(url, { signal: ctrl.signal });
    clearTimeout(tid);
    if (!res.ok) return [];
    const data = await res.json() as { similarartists?: { artist?: LastfmSimilarArtist[] } };
    const arr = data.similarartists?.artist ?? [];
    return arr.map((a) => a.name).filter(Boolean).slice(0, limit);
  } catch {
    return [];
  }
}

/// Cache-key helper
function cacheKey(userId: string): string {
  return `rolify:stations:v1:${userId}`;
}

export async function getRecommendedStations(userId: string): Promise<RecommendedStation[]> {
  // 1) Redis-Cache check
  try {
    const cached = await redis.get(cacheKey(userId));
    if (cached) {
      const parsed = JSON.parse(cached) as CachedStationPayload;
      if (Date.now() - parsed.generatedAt < CACHE_TTL * 1000) {
        return parsed.stations;
      }
    }
  } catch {
    // Cache-Misses sind nicht kritisch
  }

  // 2) Seed-Artists holen: erst Saved-Artists, dann Fallback PlayHistory
  let seedArtists: { id: string; name: string; imageUrl: string | null }[] = [];

  const saved = await prisma.savedArtist.findMany({
    where: { userId },
    orderBy: { savedAt: "desc" },
    take: STATION_LIMIT,
    include: { artist: { select: { id: true, name: true, imageUrl: true } } },
  });
  seedArtists = saved.map((s) => s.artist);

  if (seedArtists.length === 0) {
    // Fallback: top-played artists from PlayHistory
    const played = await prisma.playHistory.findMany({
      where: { userId },
      orderBy: { playedAt: "desc" },
      take: 30,
      include: { track: { select: { artist: { select: { id: true, name: true, imageUrl: true } } } } },
    });
    const seen = new Set<string>();
    for (const p of played) {
      const a = p.track.artist;
      if (!seen.has(a.id)) {
        seen.add(a.id);
        seedArtists.push(a);
      }
      if (seedArtists.length >= STATION_LIMIT) break;
    }
  }

  if (seedArtists.length === 0) return [];

  // 3) Pro Seed: Last.fm-Similar fetchen, dann Station-Card formen
  const stations: RecommendedStation[] = [];
  for (const seed of seedArtists) {
    const similar = await lastfmSimilarArtists(seed.name, 3);
    const subtitleParts = [seed.name, ...similar].slice(0, 4);
    stations.push({
      id: seed.id,
      name: `${seed.name} Radio`,
      subtitle: subtitleParts.join(", "),
      coverUrl: seed.imageUrl ?? "",
      tintHex: hashTint(seed.id),
    });
  }

  // 4) Cache write
  try {
    await redis.set(
      cacheKey(userId),
      JSON.stringify({ generatedAt: Date.now(), stations } satisfies CachedStationPayload),
      "EX", CACHE_TTL,
    );
  } catch {
    // Cache-Write-Fail ist nicht kritisch
  }

  return stations;
}

// Suppress unused-import warning fuer env
void env;
