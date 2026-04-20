import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { env } from "../config.js";

function publicCoverUrl(storedUrl: string): string {
  // Cover-URLs sind als /covers/xxx.jpg in der DB; iOS braucht absolute URL
  if (!storedUrl) return "";
  if (storedUrl.startsWith("http")) return storedUrl;
  const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
  return `${base.replace(/\/$/, "")}${storedUrl}`;
}

export default async function browseRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/browse/home", async () => {
    const tracks = await prisma.track.findMany({
      orderBy: { createdAt: "desc" },
      take: 50,
      select: {
        id: true,
        title: true,
        durationMs: true,
        artist: { select: { name: true } },
        album: { select: { id: true, title: true, coverUrl: true } },
      },
    });
    return {
      tracks: tracks.map((t) => ({
        id: t.id,
        title: t.title,
        artist: t.artist.name,
        album: t.album.title,
        albumId: t.album.id,
        coverUrl: publicCoverUrl(t.album.coverUrl),
        durationMs: t.durationMs,
      })),
    };
  });
}
