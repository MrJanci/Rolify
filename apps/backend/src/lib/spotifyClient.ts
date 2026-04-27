import { env } from "../config.js";
import { redis } from "./redis.js";

/// Spotify Client-Credentials-Flow fuer Catalog-Search.
/// Token wird in Redis gecacht (TTL ~50 min, echte TTL ist 60 min).

interface SpotifyToken {
  access_token: string;
  token_type: string;
  expires_in: number;
}

const CACHE_KEY = "rolify:spotify:cc_token";
const CACHE_TTL = 3000; // 50 min (5-min safety margin vor Apples 60-min TTL)

async function fetchNewToken(): Promise<string> {
  const creds = Buffer.from(`${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`).toString("base64");
  const res = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Authorization": `Basic ${creds}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) {
    throw new Error(`Spotify token fetch failed: ${res.status}`);
  }
  const data = (await res.json()) as SpotifyToken;
  await redis.set(CACHE_KEY, data.access_token, "EX", CACHE_TTL);
  return data.access_token;
}

async function getToken(): Promise<string> {
  const cached = await redis.get(CACHE_KEY);
  if (cached) return cached;
  return fetchNewToken();
}

export interface SpotifyTrackHit {
  spotifyId: string;
  title: string;
  artist: string;
  album: string;
  albumId: string;
  coverUrl: string;
  durationMs: number;
  isrc: string | null;
  previewUrl: string | null;
}

export async function spotifySearchTracks(query: string, limit = 20): Promise<SpotifyTrackHit[]> {
  const token = await getToken();
  const params = new URLSearchParams({
    q: query,
    type: "track",
    limit: String(Math.min(50, limit)),
    market: "CH",
  });
  const res = await fetch(`https://api.spotify.com/v1/search?${params.toString()}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`Spotify search failed: ${res.status}`);
  }
  const data = await res.json() as { tracks?: { items?: any[] } };
  const items = data.tracks?.items ?? [];
  return items
    .filter((t) => t && !t.is_local)
    .map((t) => ({
      spotifyId: t.id as string,
      title: (t.name as string) ?? "",
      artist: (t.artists ?? []).map((a: { name: string }) => a.name).join(", "),
      album: (t.album?.name as string) ?? "",
      albumId: (t.album?.id as string) ?? "",
      coverUrl: t.album?.images?.[0]?.url ?? "",
      durationMs: (t.duration_ms as number) ?? 0,
      isrc: t.external_ids?.isrc ?? null,
      previewUrl: t.preview_url ?? null,
    }));
}

/// Spotify-Artist-Top-Tracks fuer Discover-on-Artist-Detail.
/// Sucht erst Artist via Search, nimmt besten Match, fetched dann top-tracks.
/// Returns leere liste wenn Artist nicht gefunden.
export async function spotifyArtistTopTracks(artistName: string, market = "CH"): Promise<SpotifyTrackHit[]> {
  const token = await getToken();
  // Search Artist
  const searchParams = new URLSearchParams({
    q: artistName,
    type: "artist",
    limit: "1",
  });
  const searchRes = await fetch(`https://api.spotify.com/v1/search?${searchParams.toString()}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!searchRes.ok) throw new Error(`Spotify artist search failed: ${searchRes.status}`);
  const searchData = await searchRes.json() as { artists?: { items?: { id: string; name: string }[] } };
  const artist = searchData.artists?.items?.[0];
  if (!artist) return [];

  // Fetch top-tracks
  const topRes = await fetch(`https://api.spotify.com/v1/artists/${artist.id}/top-tracks?market=${market}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!topRes.ok) throw new Error(`Spotify top-tracks failed: ${topRes.status}`);
  const topData = await topRes.json() as { tracks?: any[] };
  const items = topData.tracks ?? [];
  return items
    .filter((t) => t && !t.is_local)
    .map((t) => ({
      spotifyId: t.id as string,
      title: (t.name as string) ?? "",
      artist: (t.artists ?? []).map((a: { name: string }) => a.name).join(", "),
      album: (t.album?.name as string) ?? "",
      albumId: (t.album?.id as string) ?? "",
      coverUrl: t.album?.images?.[0]?.url ?? "",
      durationMs: (t.duration_ms as number) ?? 0,
      isrc: t.external_ids?.isrc ?? null,
      previewUrl: t.preview_url ?? null,
    }));
}

/// Discover Album-Tracks via Search "artist title". Filtert auf gleichen Album-Namen.
/// Pragmatic-Approach: kein Album.spotifyId gespeichert, also Search-by-Name.
export async function spotifyDiscoverAlbumTracks(albumTitle: string, artistName: string): Promise<SpotifyTrackHit[]> {
  const token = await getToken();
  // Erst Album finden (Search-by-Album)
  const searchParams = new URLSearchParams({
    q: `album:${albumTitle} artist:${artistName}`,
    type: "album",
    limit: "3",
  });
  const searchRes = await fetch(`https://api.spotify.com/v1/search?${searchParams.toString()}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!searchRes.ok) throw new Error(`Spotify album search failed: ${searchRes.status}`);
  const searchData = await searchRes.json() as { albums?: { items?: { id: string; name: string; artists?: { name: string }[] }[] } };
  const albums = searchData.albums?.items ?? [];
  // Best-Match: gleiche Lower-Case Title + Artist-Name enthaelt
  const wanted = albums.find((a) =>
    a.name.toLowerCase().trim() === albumTitle.toLowerCase().trim()
    && (a.artists ?? []).some((art) => art.name.toLowerCase().includes(artistName.toLowerCase().split(",")[0]?.trim() ?? ""))
  ) ?? albums[0];
  if (!wanted) return [];

  // Fetch all album-tracks
  const albumRes = await fetch(`https://api.spotify.com/v1/albums/${wanted.id}?market=CH`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!albumRes.ok) throw new Error(`Spotify album fetch failed: ${albumRes.status}`);
  const albumData = await albumRes.json() as {
    images?: { url: string }[];
    tracks?: { items?: any[] };
  };
  const items = albumData.tracks?.items ?? [];
  const cover = albumData.images?.[0]?.url ?? "";
  return items
    .filter((t) => t && !t.is_local)
    .map((t) => ({
      spotifyId: t.id as string,
      title: (t.name as string) ?? "",
      artist: (t.artists ?? []).map((a: { name: string }) => a.name).join(", "),
      album: wanted.name,
      albumId: wanted.id,
      coverUrl: cover,
      durationMs: (t.duration_ms as number) ?? 0,
      isrc: t.external_ids?.isrc ?? null,
      previewUrl: t.preview_url ?? null,
    }));
}
