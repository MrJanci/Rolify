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
  isCollaborative: z.boolean().default(false),
});

const UpdatePlaylistBody = z.object({
  name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  coverUrl: z.string().max(1024).optional(),
  isPublic: z.boolean().optional(),
  isCollaborative: z.boolean().optional(),
});

const AddTracksBody = z.object({
  trackIds: z.array(z.string()).min(1).max(100),
});

const ReorderBody = z.object({
  moves: z.array(
    z.object({ trackId: z.string(), position: z.number().int().nonnegative() })
  ).min(1).max(200),
});

const AddCollabBody = z.object({
  email: z.string().email(),
  role: z.enum(["EDITOR", "VIEWER"]).default("EDITOR"),
});

// Access-Check: Owner ODER Editor (wenn collab) darf writen.
// Fuer Read: owner, collaborator oder wenn isPublic.
async function canRead(playlistId: string, userId: string): Promise<{ ok: boolean; ownerId?: string; isCollab?: boolean }> {
  const pl = await prisma.playlist.findUnique({
    where: { id: playlistId },
    select: {
      userId: true, isPublic: true, isCollaborative: true,
      collaborators: { where: { userId }, select: { role: true } },
    },
  });
  if (!pl) return { ok: false };
  if (pl.userId === userId) return { ok: true, ownerId: pl.userId };
  if (pl.isPublic) return { ok: true, ownerId: pl.userId };
  if (pl.collaborators.length > 0) return { ok: true, ownerId: pl.userId, isCollab: true };
  return { ok: false };
}

async function canWrite(playlistId: string, userId: string): Promise<{ ok: boolean; ownerId?: string }> {
  const pl = await prisma.playlist.findUnique({
    where: { id: playlistId },
    select: {
      userId: true, isCollaborative: true,
      collaborators: { where: { userId, role: "EDITOR" }, select: { userId: true } },
    },
  });
  if (!pl) return { ok: false };
  if (pl.userId === userId) return { ok: true, ownerId: pl.userId };
  if (pl.isCollaborative && pl.collaborators.length > 0) return { ok: true, ownerId: pl.userId };
  return { ok: false };
}

export default async function playlistRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // Liste der eigenen Playlists + Collab-Playlists + sichtbare Dynamic-Playlists
  app.get("/playlists/me", async (req) => {
    const owned = await prisma.playlist.findMany({
      where: { userId: req.user.sub, isDynamic: false },
      orderBy: { updatedAt: "desc" },
      select: {
        id: true, name: true, description: true, coverUrl: true,
        isPublic: true, isCollaborative: true, isMixed: true, isDynamic: true,
        dynamicSource: true,
        updatedAt: true, userId: true,
        _count: { select: { tracks: true } },
      },
    });
    const collab = await prisma.playlist.findMany({
      where: { collaborators: { some: { userId: req.user.sub } }, isDynamic: false },
      orderBy: { updatedAt: "desc" },
      select: {
        id: true, name: true, description: true, coverUrl: true,
        isPublic: true, isCollaborative: true, isMixed: true, isDynamic: true,
        dynamicSource: true,
        updatedAt: true, userId: true,
        _count: { select: { tracks: true } },
        user: { select: { displayName: true } },
      },
    });
    // Dynamic Playlists (global): includieren wenn user nicht explicit disabled
    const userSettings = await prisma.userPlaylistSettings.findMany({
      where: { userId: req.user.sub, enabled: false },
      select: { source: true },
    });
    const disabledSources = new Set(userSettings.map((s) => s.source));
    const dynamic = await prisma.playlist.findMany({
      where: {
        isDynamic: true,
        dynamicSource: { notIn: [...disabledSources] },
      },
      orderBy: { updatedAt: "desc" },
      select: {
        id: true, name: true, description: true, coverUrl: true,
        isPublic: true, isCollaborative: true, isMixed: true, isDynamic: true,
        dynamicSource: true,
        updatedAt: true, userId: true,
        _count: { select: { tracks: true } },
      },
    });

    const all = [...owned, ...collab, ...dynamic].sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
    return all.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      coverUrl: publicCoverUrl(p.coverUrl),
      isPublic: p.isPublic,
      isCollaborative: p.isCollaborative,
      isMixed: p.isMixed,
      isDynamic: p.isDynamic,
      dynamicSource: p.dynamicSource,
      isOwned: !p.isDynamic && p.userId === req.user.sub,
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
      isCollaborative: created.isCollaborative,
      isMixed: created.isMixed,
      isOwned: true,
      trackCount: 0,
    });
  });

  // Playlist-Detail mit Tracks
  app.get<{ Params: { id: string } }>("/playlists/:id", async (req, reply) => {
    const access = await canRead(req.params.id, req.user.sub);
    if (!access.ok) return reply.status(404).send({ error: "not_found" });

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
        collaborators: {
          include: { user: { select: { id: true, displayName: true, avatarUrl: true } } },
        },
      },
    });
    if (!playlist) return reply.status(404).send({ error: "not_found" });
    return {
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      coverUrl: publicCoverUrl(playlist.coverUrl),
      isPublic: playlist.isPublic,
      isCollaborative: playlist.isCollaborative,
      isMixed: playlist.isMixed,
      ownerId: playlist.userId,
      isOwned: playlist.userId === req.user.sub,
      canEdit: playlist.userId === req.user.sub ||
               (playlist.isCollaborative && playlist.collaborators.some((c) => c.userId === req.user.sub && c.role === "EDITOR")),
      collaborators: playlist.collaborators.map((c) => ({
        id: c.user.id,
        displayName: c.user.displayName,
        avatarUrl: c.user.avatarUrl,
        role: c.role,
      })),
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

  // Playlist-Metadaten aendern (nur Owner)
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
      isCollaborative: updated.isCollaborative,
    };
  });

  // Playlist loeschen (nur Owner)
  app.delete<{ Params: { id: string } }>("/playlists/:id", async (req, reply) => {
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }
    await prisma.playlist.delete({ where: { id: req.params.id } });
    return reply.status(204).send();
  });

  // Tracks zur Playlist hinzufuegen (am Ende) - Owner oder Collab-Editor
  app.post<{ Params: { id: string } }>("/playlists/:id/tracks", async (req, reply) => {
    const access = await canWrite(req.params.id, req.user.sub);
    if (!access.ok) return reply.status(404).send({ error: "not_found" });

    const { trackIds } = AddTracksBody.parse(req.body);

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
          update: {},
        })
      )
    );
    await prisma.playlist.update({
      where: { id: req.params.id },
      data: { updatedAt: new Date() },
    });
    return reply.status(201).send({ added: filtered.length, skippedInvalid });
  });

  // Track aus Playlist entfernen
  app.delete<{ Params: { id: string; trackId: string } }>("/playlists/:id/tracks/:trackId", async (req, reply) => {
    const access = await canWrite(req.params.id, req.user.sub);
    if (!access.ok) return reply.status(404).send({ error: "not_found" });
    await prisma.playlistTrack.delete({
      where: { playlistId_trackId: { playlistId: req.params.id, trackId: req.params.trackId } },
    }).catch(() => void 0);
    return reply.status(204).send();
  });

  // Reorder (bulk)
  app.patch<{ Params: { id: string } }>("/playlists/:id/reorder", async (req, reply) => {
    const access = await canWrite(req.params.id, req.user.sub);
    if (!access.ok) return reply.status(404).send({ error: "not_found" });
    const { moves } = ReorderBody.parse(req.body);
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

  // ========================================================================
  // Collaborators
  // ========================================================================

  app.post<{ Params: { id: string } }>("/playlists/:id/collaborators", async (req, reply) => {
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found" });
    }
    const body = AddCollabBody.parse(req.body);
    const target = await prisma.user.findUnique({ where: { email: body.email.toLowerCase() } });
    if (!target) return reply.status(404).send({ error: "user_not_found" });
    if (target.id === req.user.sub) return reply.status(400).send({ error: "cannot_add_self" });

    await prisma.playlistCollaborator.upsert({
      where: { playlistId_userId: { playlistId: req.params.id, userId: target.id } },
      create: { playlistId: req.params.id, userId: target.id, role: body.role },
      update: { role: body.role },
    });
    // Auto-Enable Collaborative falls noch nicht
    if (!existing.isCollaborative) {
      await prisma.playlist.update({ where: { id: existing.id }, data: { isCollaborative: true } });
    }
    return reply.status(201).send({
      id: target.id,
      displayName: target.displayName,
      avatarUrl: target.avatarUrl,
      role: body.role,
    });
  });

  app.delete<{ Params: { id: string; userId: string } }>("/playlists/:id/collaborators/:userId", async (req, reply) => {
    const existing = await prisma.playlist.findUnique({ where: { id: req.params.id } });
    if (!existing) return reply.status(404).send({ error: "not_found" });
    // Owner darf alle removen. Collaborator darf sich selbst removen.
    if (existing.userId !== req.user.sub && req.params.userId !== req.user.sub) {
      return reply.status(403).send({ error: "forbidden" });
    }
    await prisma.playlistCollaborator.delete({
      where: { playlistId_userId: { playlistId: req.params.id, userId: req.params.userId } },
    }).catch(() => void 0);
    return reply.status(204).send();
  });
}
