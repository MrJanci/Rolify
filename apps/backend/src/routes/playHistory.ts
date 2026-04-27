import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

/**
 * PlayHistory-Tracking fuer "Jump back in" Home-Shelf.
 * - POST /play-history wird vom iOS-Player aufgerufen sobald ein Track >= 5s laeuft
 * - Auto-Cleanup: pro User max 200 Entries (oldest werden geloescht via Trigger nach insert)
 */

const TrackBody = z.object({
  trackId: z.string().min(1),
  contextType: z.enum(["album", "playlist", "artist", "search", "queue", "liked", "discover"]).optional(),
  contextId: z.string().optional(),
});

const MAX_HISTORY_PER_USER = 200;

export default async function playHistoryRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  /// Track-Start melden. Idempotent insofern als zwei rasche Calls fuer denselben
  /// trackId innerhalb 30 Sekunden zusammengelegt werden (kein doppelter Eintrag bei
  /// kurz-skip-back).
  app.post("/play-history", async (req, reply) => {
    const userId = req.user.sub;
    const { trackId, contextType, contextId } = TrackBody.parse(req.body);

    // Verify track exists (avoid foreign-key error on stale clients)
    const exists = await prisma.track.findUnique({ where: { id: trackId }, select: { id: true } });
    if (!exists) return reply.status(404).send({ error: "track_not_found" });

    // Dedupe: gleicher Track in den letzten 30s -> kein neuer Eintrag
    const recent = await prisma.playHistory.findFirst({
      where: { userId, trackId, playedAt: { gte: new Date(Date.now() - 30_000) } },
      select: { id: true },
    });
    if (recent) return { status: "deduped", id: recent.id };

    const entry = await prisma.playHistory.create({
      data: { userId, trackId, contextType, contextId },
    });

    // Auto-Cleanup: behalte max 200 pro User. Async fire-and-forget damit Response schnell ist.
    void cleanupOldHistory(userId);

    return reply.status(201).send({ status: "logged", id: entry.id });
  });

  /// GET /play-history — letzte N Tracks fuer Debug / "Wiederholen"-Use-Cases.
  app.get("/play-history", async (req) => {
    const userId = req.user.sub;
    const rows = await prisma.playHistory.findMany({
      where: { userId },
      orderBy: { playedAt: "desc" },
      take: 50,
      include: {
        track: {
          select: {
            id: true, title: true,
            artist: { select: { name: true } },
            album: { select: { id: true, title: true, coverUrl: true } },
          },
        },
      },
    });
    return rows.map((r) => ({
      id: r.id,
      trackId: r.trackId,
      title: r.track.title,
      artist: r.track.artist.name,
      album: r.track.album.title,
      albumId: r.track.album.id,
      contextType: r.contextType,
      contextId: r.contextId,
      playedAt: r.playedAt.toISOString(),
    }));
  });
}

async function cleanupOldHistory(userId: string): Promise<void> {
  try {
    // Hole id of the (MAX+1)-th newest entry → alles aelter wird geloescht
    const cutoff = await prisma.playHistory.findMany({
      where: { userId },
      orderBy: { playedAt: "desc" },
      skip: MAX_HISTORY_PER_USER,
      take: 1,
      select: { playedAt: true },
    });
    if (cutoff.length === 0) return;
    await prisma.playHistory.deleteMany({
      where: { userId, playedAt: { lt: cutoff[0]!.playedAt } },
    });
  } catch {
    // Cleanup-failures sind nicht kritisch
  }
}
