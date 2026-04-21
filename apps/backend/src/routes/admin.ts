import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";

/// Admin-Endpoints — aktuell nur Scrape-Job-Management.
/// Fuer jetzt: authenticated users koennen scrapen (Solo-App-Setup).
/// Spaeter: User.isAdmin Flag + Gate.

const StartScrapeBody = z.object({
  playlistUrl: z.string().min(1).max(500),
});

export default async function adminRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // Neuen Scrape-Job erstellen (queue'd)
  app.post("/admin/scrape", async (req, reply) => {
    const body = StartScrapeBody.parse(req.body);

    // Normalisieren: "https://open.spotify.com/playlist/XYZ" -> "spotify:playlist:XYZ"
    const url = body.playlistUrl.trim();
    let normalized = url;
    const m = url.match(/(?:open\.spotify\.com\/playlist\/|spotify:playlist:)([a-zA-Z0-9]+)/);
    if (m) {
      normalized = `spotify:playlist:${m[1]}`;
    }

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
