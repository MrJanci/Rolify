import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";
import { getRecommendedStations } from "../lib/stations.js";

function publicCoverUrl(storedUrl: string | null | undefined): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

/// Quick-Access-Item: kompakte 2x4-Grid-Tile auf Spotify-Home.
/// kind = "playlist" | "album" | "liked" | "artist"
interface QuickAccessItem {
  id: string;
  kind: "playlist" | "album" | "liked" | "artist";
  title: string;
  coverUrl: string;
  subtitle?: string;
}

export default async function browseRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/browse/home", async (req) => {
    const userId = req.user.sub;

    const [
      recentTracks,
      userPlaylists,
      topAlbums,
      likedCount,
      savedAlbums,
      recentHistory,
      stations,
    ] = await Promise.all([
      // Recently-added Tracks (existing shelf)
      prisma.track.findMany({
        orderBy: { createdAt: "desc" },
        take: 10,
        select: {
          id: true, title: true, durationMs: true,
          artist: { select: { name: true } },
          album: { select: { id: true, title: true, coverUrl: true } },
        },
      }),
      // User-Playlists (recently updated, top 10)
      prisma.playlist.findMany({
        where: { userId },
        orderBy: { updatedAt: "desc" },
        take: 10,
        select: {
          id: true, name: true, description: true, coverUrl: true, isPublic: true,
          _count: { select: { tracks: true } },
        },
      }),
      // Top albums by release-year (existing)
      prisma.album.findMany({
        orderBy: { releaseYear: "desc" },
        take: 10,
        select: {
          id: true, title: true, coverUrl: true, releaseYear: true,
          artist: { select: { name: true } },
        },
      }),
      // Liked-songs count for the special "Liked Songs" tile
      prisma.libraryTrack.count({ where: { userId } }),
      // Recently-saved Albums for Quick-Access
      prisma.savedAlbum.findMany({
        where: { userId },
        orderBy: { savedAt: "desc" },
        take: 4,
        include: {
          album: {
            select: {
              id: true, title: true, coverUrl: true,
              artist: { select: { name: true } },
            },
          },
        },
      }),
      // Recently-played fuer Jump-Back-In Shelf
      prisma.playHistory.findMany({
        where: { userId },
        orderBy: { playedAt: "desc" },
        take: 50, // genug um auf 6 unique Albums/Playlists zu reduzieren
        include: {
          track: {
            select: {
              id: true, title: true,
              album: { select: { id: true, title: true, coverUrl: true } },
              artist: { select: { name: true } },
            },
          },
        },
      }),
      // Recommended Stations (Last.fm-based, in-memory cached)
      getRecommendedStations(userId).catch(() => []),
    ]);

    // ---- Quick-Access-Grid (8 Items: Liked Songs als #1 wenn nicht leer + 7 weitere)
    const quickAccess: QuickAccessItem[] = [];
    if (likedCount > 0) {
      quickAccess.push({
        id: "liked",
        kind: "liked",
        title: "Liked Songs",
        coverUrl: "",  // Frontend rendert ein Heart-Gradient
        subtitle: `${likedCount} Tracks`,
      });
    }
    // Mische top 4 Playlists + top 4 Saved Albums (insgesamt max 8 inkl. Liked)
    const playlistTiles = userPlaylists.slice(0, 4).map<QuickAccessItem>((p) => ({
      id: p.id,
      kind: "playlist",
      title: p.name,
      coverUrl: publicCoverUrl(p.coverUrl),
    }));
    const albumTiles = savedAlbums.slice(0, 4).map<QuickAccessItem>((sa) => ({
      id: sa.album.id,
      kind: "album",
      title: sa.album.title,
      coverUrl: publicCoverUrl(sa.album.coverUrl),
      subtitle: sa.album.artist.name,
    }));
    // Interleave: Playlist, Album, Playlist, Album, ... bis max 8 total inkl. Liked
    const remaining = 8 - quickAccess.length;
    const interleaved: QuickAccessItem[] = [];
    for (let i = 0; i < Math.max(playlistTiles.length, albumTiles.length); i++) {
      if (playlistTiles[i]) interleaved.push(playlistTiles[i]!);
      if (albumTiles[i]) interleaved.push(albumTiles[i]!);
    }
    quickAccess.push(...interleaved.slice(0, remaining));

    // ---- Jump-Back-In: dedupe nach Album/Playlist auf 6 Items
    const seenAlbums = new Set<string>();
    const jumpBackIn: Array<{
      id: string;
      kind: "album" | "playlist";
      title: string;
      subtitle: string;
      coverUrl: string;
    }> = [];
    for (const h of recentHistory) {
      const albId = h.track.album.id;
      // contextType "playlist" -> spaeter Phase wenn Playlist auch in History (PlaylistDetail-Player setzt context)
      if (!seenAlbums.has(albId)) {
        seenAlbums.add(albId);
        jumpBackIn.push({
          id: albId,
          kind: "album",
          title: h.track.album.title,
          subtitle: h.track.artist.name,
          coverUrl: publicCoverUrl(h.track.album.coverUrl),
        });
      }
      if (jumpBackIn.length >= 6) break;
    }

    // ---- Shelves zusammenstellen (in Spotify-typischer Reihenfolge)
    const shelves: Array<Record<string, unknown>> = [];

    if (jumpBackIn.length > 0) {
      shelves.push({
        id: "jump_back_in",
        title: "Springe wieder rein",
        kind: "albums" as const,
        albums: jumpBackIn.map((j) => ({
          id: j.id,
          title: j.title,
          artist: j.subtitle,
          coverUrl: j.coverUrl,
          releaseYear: 0,
        })),
      });
    }

    if (stations.length > 0) {
      shelves.push({
        id: "stations",
        title: "Empfohlene Stationen",
        kind: "stations" as const,
        stations: stations.map((s) => ({
          id: s.id,
          name: s.name,
          subtitle: s.subtitle,
          coverUrl: publicCoverUrl(s.coverUrl),
          tintHex: s.tintHex,
        })),
      });
    }

    shelves.push({
      id: "recent_tracks",
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
    });

    if (userPlaylists.length > 0) {
      shelves.push({
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
      });
    }

    if (topAlbums.length > 0) {
      shelves.push({
        id: "top_albums",
        title: "Alben",
        kind: "albums" as const,
        albums: topAlbums.map((a) => ({
          id: a.id,
          title: a.title,
          artist: a.artist.name,
          coverUrl: publicCoverUrl(a.coverUrl),
          releaseYear: a.releaseYear,
        })),
      });
    }

    return {
      quickAccess,
      shelves,
      // Legacy-Felder fuer alte iOS-Clients (v0.16/v0.17)
      tracks: shelves.find((s) => s.id === "recent_tracks")?.tracks ?? [],
    };
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
