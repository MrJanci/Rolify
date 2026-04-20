import type { FastifyInstance } from "fastify";
import { GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { prisma } from "../lib/prisma.js";
import { buckets, s3 } from "../lib/s3.js";

// Skeleton fuer Woche 6. Die Key-Wrap-Logik (ECIES mit devicePubKey) kommt dann.

export default async function streamRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { trackId: string } }>("/stream/:trackId/manifest", async (req, reply) => {
    const track = await prisma.track.findUnique({
      where: { id: req.params.trackId },
      select: { id: true, encryptedBlobKey: true, durationMs: true },
    });
    if (!track) return reply.status(404).send({ error: "not_found" });

    // TODO [Phase 2]: subscription check (ACTIVE | GRACE)

    const cmd = new GetObjectCommand({ Bucket: buckets.tracks, Key: track.encryptedBlobKey });
    const signedCiphertextUrl = await getSignedUrl(s3, cmd, { expiresIn: 300 });

    return {
      trackId: track.id,
      durationMs: track.durationMs,
      signedCiphertextUrl,
      keyUrl: `/stream/${track.id}/key`,
      expiresInS: 300,
    };
  });

  app.get<{ Params: { trackId: string }; Querystring: { deviceId: string } }>(
    "/stream/:trackId/key",
    async (req, reply) => {
      // Skeleton: in Woche 6 wird hier masterKey mit devicePubKey (ECIES) wrapped
      // und als signed JWT zurueckgegeben. Aktuell: 501 Not Implemented.
      return reply.status(501).send({ error: "not_implemented", todo: "week-6-DRM-key-wrap" });
    },
  );
}
