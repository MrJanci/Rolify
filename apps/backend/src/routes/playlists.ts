import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string | null | undefined): string {
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

const CreatePlaylistBody = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  coverUrl: z.string().max(1024).optional(),
  isPublic: z.boolean().default(false),
});

const UpdatePlaylistBody = z.object({
  name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  coverUrl: z.string().max(1024).optional(),
  isPublic: z.boolean().optional(),
});

const AddTracksBody = z.object({
  trackIds: z.array(z.string()).min(1).max(100),
});

const ReorderBody = z.object({
  moves: z.array(
    z.object({ trackId: z.string(), position: z.number().int().nonnegative() })
  ).min(1).max(200),
});

export default async function playlistRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // Liste der eigenen Playlists
  app.get("/playlists/me", async (req) => {
    const rows = await prisma.playlist.findMany({
      where: { userId: req.user.sub },
      orderBy: { updatedAt: "desc" },
      select: {
        id: true, name: true, description: true, coverUrl: true,
        isPublic: true, updatedAt: true,
        _count: { select: { tracks: true } },
      },
    });
    return rows.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      coverUrl: publicCoverUrl(p.coverUrl),
      isPublic: p.isPublic,
      updatedAt: p.updatedAt,
      trackCount: p._count.tracks,
    }));
  });

  // Neue Playlist erstellen
  app.post("/playlists", async (req, reply) => {
    const body = CreatePlaylistBody.parse(req.body);
    const created = await prisma.playlist.create({
      data: { ...body, userId: req.user.sub },
    });
    return reply.status(201).send({
      id: created.id,
      name: created.name,
      description: created.description,
      coverUrl: publicCoverUrl(created.coverUrl),
      isPublic: created.isPublic,
      trackCount: 0,
    });
  });

  // Playlist-Detail mit Tracks
  app.get<{ Params: { id: string } }>("/playlists/:id", async (req, reply) => {
    const playlist = await prisma.playlist.findUnique({
      where: { id: req.params.id },
      include: {
        tracks: {
          orderBy: { position: "asc" },
          include: {
            track: {
              include: {
                artist: { select: { id: true, name: true } },
                album: { select: { id: true, title: true, coverUrl: true } },
              },
            },
          },
        },
      },
    });
    if (!playlist) return reply.status(404).send({ error: "not_found" });
    // Private -> only owner
    if (!playlist.isPublic && playlist.userId !== req.user.sub) {
      return reply.status(403).send({ error: "forbidden" });
    }
    return {
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      coverUrl: publicCoverUrl(playlist.coverUrl),
      isPublic: playlist.isPublic,
      ownerId: playlist.userId,
      tracks: playlist.tracks.map((pt) => ({
        id: pt.track.id,
        title: pt.track.title,
        artist: pt.track.artist.name,
        artistId: pt.track.artist.id,
        album: pt.track.album.title,
        albumId: pt.track.album.id,
        coverUrl: publicCoverUrl(pt.track.album.coverUrl),
        durationMs: pt.track.durationMs,
        position: pt.position,
      })),
    };
  });

  // Playlist-Metadaten aendern
  app.patch<{ Params: { id: string } }>("/playlists/:id", async (req, reply) => {
    const body = UpdatePlaylistBody.parse(req.body);
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }
    const updated = await prisma.playlist.update({
      where: { id: req.params.id },
      data: body,
    });
    return {
      id: updated.id,
      name: updated.name,
      description: updated.description,
      coverUrl: publicCoverUrl(updated.coverUrl),
      isPublic: updated.isPublic,
    };
  });

  // Playlist loeschen
  app.delete<{ Params: { id: string } }>("/playlists/:id", async (req, reply) => {
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }
    await prisma.playlist.delete({ where: { id: req.params.id } });
    return reply.status(204).send();
  });

  // Tracks zur Playlist hinzufuegen (am Ende)
  app.post<{ Params: { id: string } }>("/playlists/:id/tracks", async (req, reply) => {
    const { trackIds } = AddTracksBody.parse(req.body);
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }

    // Validiere: nur Track-IDs die wirklich existieren, sonst FK-Violation
    const validTracks = await prisma.track.findMany({
      where: { id: { in: trackIds } },
      select: { id: true },
    });
    const validIds = new Set(validTracks.map((t) => t.id));
    const filtered = trackIds.filter((id) => validIds.has(id));
    const skippedInvalid = trackIds.length - filtered.length;

    if (filtered.length === 0) {
      return reply.status(400).send({
        error: "no_valid_tracks",
        message: `Alle ${skippedInvalid} Tracks existieren nicht mehr in der Datenbank`,
      });
    }

    // Max position ermitteln
    const maxPos = await prisma.playlistTrack.aggregate({
      where: { playlistId: req.params.id },
      _max: { position: true },
    });
    const startPos = (maxPos._max.position ?? -1) + 1;

    await prisma.$transaction(
      filtered.map((trackId, i) =>
        prisma.playlistTrack.upsert({
          where: { playlistId_trackId: { playlistId: req.params.id, trackId } },
          create: { playlistId: req.params.id, trackId, position: startPos + i },
          update: {}, // wenn schon drin, position nicht aendern (Dedupe)
        })
      )
    );
    await prisma.playlist.update({
      where: { id: req.params.id },
      data: { updatedAt: new Date() },
    });
    return reply.status(201).send({
      added: filtered.length,
      skippedInvalid,
    });
  });

  // Track aus Playlist entfernen
  app.delete<{ Params: { id: string; trackId: string } }>("/playlists/:id/tracks/:trackId", async (req, reply) => {
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }
    await prisma.playlistTrack.delete({
      where: { playlistId_trackId: { playlistId: req.params.id, trackId: req.params.trackId } },
    }).catch(() => void 0);
    return reply.status(204).send();
  });

  // Reorder (bulk) — atomic transaction
  app.patch<{ Params: { id: string } }>("/playlists/:id/reorder", async (req, reply) => {
    const { moves } = ReorderBody.parse(req.body);
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }
    await prisma.$transaction(
      moves.map((m) =>
        prisma.playlistTrack.update({
          where: { playlistId_trackId: { playlistId: req.params.id, trackId: m.trackId } },
          data: { position: m.position },
        })
      )
    );
    return reply.status(204).send();
  });
}
