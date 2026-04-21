import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

/// Admin-Endpoints — aktuell nur Scrape-Job-Management.
/// Fuer jetzt: authenticated users koennen scrapen (Solo-App-Setup).
/// Spaeter: User.isAdmin Flag + Gate.

const StartScrapeBody = z.object({
  playlistUrl: z.string().min(1).max(500),
});

const BulkScrapeBody = z.object({
  urls: z.array(z.string().min(1).max(500)).min(1).max(50),
});

/// Normalisiert Spotify-URLs zu canonischem Format fuer den Worker.
/// Unterstuetzt: playlists, user-liked-collection, einzelne Tracks.
function normalizeSpotifyUrl(raw: string): string {
  const url = raw.trim();
  if (/open\.spotify\.com\/collection\/tracks/i.test(url)) {
    return "spotify:collection:tracks";
  }
  const m = url.match(/(?:open\.spotify\.com\/playlist\/|spotify:playlist:)([a-zA-Z0-9]+)/);
  if (m) return `spotify:playlist:${m[1]}`;
  const t = url.match(/(?:open\.spotify\.com\/track\/|spotify:track:)([a-zA-Z0-9]+)/);
  if (t) return `spotify:track:${t[1]}`;
  return url;
}

export default async function adminRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // Neuen Scrape-Job erstellen (queue'd)
  app.post("/admin/scrape", async (req, reply) => {
    const body = StartScrapeBody.parse(req.body);
    const normalized = normalizeSpotifyUrl(body.playlistUrl);

    const job = await prisma.scrapeJob.create({
      data: {
        playlistUrl: normalized,
        createdBy: req.user.sub,
      },
    });
    return reply.status(201).send({
      id: job.id,
      playlistUrl: job.playlistUrl,
      status: job.status,
      createdAt: job.createdAt,
    });
  });

  // Bulk-Scrape: mehrere URLs auf einmal enqueue'en (dedup'd auf existing Jobs)
  app.post("/admin/scrape/bulk", async (req, reply) => {
    const body = BulkScrapeBody.parse(req.body);
    const normalized = body.urls.map(normalizeSpotifyUrl);

    // Dedupe: pruefe welche URLs schon aktive/queued Jobs haben
    const existing = await prisma.scrapeJob.findMany({
      where: {
        playlistUrl: { in: normalized },
        status: { in: ["QUEUED", "RUNNING", "PAUSED"] },
      },
      select: { playlistUrl: true },
    });
    const existingSet = new Set(existing.map((e) => e.playlistUrl));
    const toCreate = normalized.filter((u) => !existingSet.has(u));

    if (toCreate.length === 0) {
      return reply.status(200).send({ enqueued: 0, skipped: body.urls.length });
    }

    const jobs = await prisma.$transaction(
      toCreate.map((url) =>
        prisma.scrapeJob.create({
          data: { playlistUrl: url, createdBy: req.user.sub },
        })
      )
    );

    return reply.status(201).send({
      enqueued: jobs.length,
      skipped: body.urls.length - jobs.length,
      jobs: jobs.map((j) => ({ id: j.id, playlistUrl: j.playlistUrl, status: j.status })),
    });
  });

  // Alle Scrape-Jobs (juengste zuerst)
  app.get("/admin/scrape/jobs", async () => {
    const jobs = await prisma.scrapeJob.findMany({
      orderBy: { createdAt: "desc" },
      take: 50,
    });
    return {
      jobs: jobs.map((j) => ({
        id: j.id,
        playlistUrl: j.playlistUrl,
        status: j.status,
        totalTracks: j.totalTracks,
        processedTracks: j.processedTracks,
        failedTracks: j.failedTracks,
        errorMessage: j.errorMessage,
        resultPlaylistId: j.resultPlaylistId,
        createdAt: j.createdAt,
        startedAt: j.startedAt,
        completedAt: j.completedAt,
      })),
    };
  });

  // Einzelner Job (fuer Polling)
  app.get<{ Params: { id: string } }>("/admin/scrape/jobs/:id", async (req, reply) => {
    const job = await prisma.scrapeJob.findUnique({ where: { id: req.params.id } });
    if (!job) return reply.status(404).send({ error: "not_found" });
    return {
      id: job.id,
      playlistUrl: job.playlistUrl,
      status: job.status,
      totalTracks: job.totalTracks,
      processedTracks: job.processedTracks,
      failedTracks: job.failedTracks,
      errorMessage: job.errorMessage,
      createdAt: job.createdAt,
      startedAt: job.startedAt,
      completedAt: job.completedAt,
    };
  });

  // Job stornieren (queued oder paused)
  app.delete<{ Params: { id: string } }>("/admin/scrape/jobs/:id", async (req, reply) => {
    const job = await prisma.scrapeJob.findUnique({ where: { id: req.params.id } });
    if (!job) return reply.status(404).send({ error: "not_found" });
    if (job.status !== "QUEUED" && job.status !== "PAUSED") {
      return reply.status(409).send({ error: "cannot_cancel", message: `job is ${job.status.toLowerCase()}` });
    }
    await prisma.scrapeJob.delete({ where: { id: job.id } });
    return reply.status(204).send();
  });

  // Job pausieren (nur wenn RUNNING oder QUEUED - worker checkt state vor jedem track)
  app.post<{ Params: { id: string } }>("/admin/scrape/jobs/:id/pause", async (req, reply) => {
    const job = await prisma.scrapeJob.findUnique({ where: { id: req.params.id } });
    if (!job) return reply.status(404).send({ error: "not_found" });
    if (job.status !== "RUNNING" && job.status !== "QUEUED") {
      return reply.status(409).send({ error: "cannot_pause", message: `job is ${job.status.toLowerCase()}` });
    }
    const updated = await prisma.scrapeJob.update({
      where: { id: job.id },
      data: { status: "PAUSED" },
    });
    return { status: updated.status };
  });

  // Job wieder aufnehmen
  app.post<{ Params: { id: string } }>("/admin/scrape/jobs/:id/resume", async (req, reply) => {
    const job = await prisma.scrapeJob.findUnique({ where: { id: req.params.id } });
    if (!job) return reply.status(404).send({ error: "not_found" });
    if (job.status !== "PAUSED") {
      return reply.status(409).send({ error: "cannot_resume", message: `job is ${job.status.toLowerCase()}` });
    }
    // Zurueck in Queue stellen (Worker pickt es als RUNNING wieder auf)
    const updated = await prisma.scrapeJob.update({
      where: { id: job.id },
      data: { status: "QUEUED" },
    });
    return { status: updated.status };
  });
}
