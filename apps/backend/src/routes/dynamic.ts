import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

/// Dynamic Auto-Playlists: global per source (1x "TikTok Trending DE" fuer alle).
/// Per-User Toggle entscheidet ob in deiner Library sichtbar ist (UserPlaylistSettings).
///
/// Sources werden im scraping/scripts/refresh_dynamic_playlists.py gecronned, dieser
/// Endpoint exposed nur read+toggle.

const ToggleBody = z.object({
  enabled: z.boolean(),
});

const UpdateBody = z.object({
  rotationMode: z.enum(["rotate", "accumulate"]).optional(),
  refreshIntervalH: z.number().int().min(1).max(168).optional(),
});

export default async function dynamicRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // GET /dynamic/sources — Liste aller globalen dyn-Playlists + per-user-enabled-State
  app.get("/dynamic/sources", async (req) => {
    const playlists = await prisma.playlist.findMany({
      where: { isDynamic: true },
      orderBy: { name: "asc" },
      select: {
        id: true,
        name: true,
        description: true,
        coverUrl: true,
        dynamicSource: true,
        rotationMode: true,
        refreshIntervalH: true,
        lastRefreshedAt: true,
        _count: { select: { tracks: true } },
      },
    });
    const settings = await prisma.userPlaylistSettings.findMany({
      where: { userId: req.user.sub },
    });
    const settingsMap = new Map(settings.map((s) => [s.source, s.enabled]));

    return {
      sources: playlists.map((p) => ({
        id: p.id,
        name: p.name,
        description: p.description,
        coverUrl: p.coverUrl,
        source: p.dynamicSource ?? "",
        rotationMode: p.rotationMode,
        refreshIntervalH: p.refreshIntervalH,
        lastRefreshedAt: p.lastRefreshedAt,
        trackCount: p._count.tracks,
        // Default: enabled wenn kein expliziter Eintrag (opt-out statt opt-in)
        enabled: settingsMap.get(p.dynamicSource ?? "") ?? true,
      })),
    };
  });

  // POST /dynamic/sources/:source/toggle — User toggled Sichtbarkeit
  app.post<{ Params: { source: string } }>("/dynamic/sources/:source/toggle", async (req, reply) => {
    const body = ToggleBody.parse(req.body);
    const decoded = decodeURIComponent(req.params.source);
    await prisma.userPlaylistSettings.upsert({
      where: { userId_source: { userId: req.user.sub, source: decoded } },
      create: { userId: req.user.sub, source: decoded, enabled: body.enabled },
      update: { enabled: body.enabled },
    });
    return reply.status(200).send({ source: decoded, enabled: body.enabled });
  });

  // PATCH /dynamic/sources/:source — rotation-mode oder interval aendern (admin-style, alle koennen)
  app.patch<{ Params: { source: string } }>("/dynamic/sources/:source", async (req, reply) => {
    const body = UpdateBody.parse(req.body);
    const decoded = decodeURIComponent(req.params.source);
    const updated = await prisma.playlist.updateMany({
      where: { dynamicSource: decoded },
      data: body,
    });
    if (updated.count === 0) return reply.status(404).send({ error: "source_not_found" });
    return { source: decoded, ...body };
  });
}
