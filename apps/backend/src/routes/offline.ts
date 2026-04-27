import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { prisma } from "../lib/prisma.js";
import { buckets, s3Public } from "../lib/s3.js";

/// Offline-Download Endpoints.
///
/// Flow:
///   1. iOS: POST /offline/licenses { trackId, deviceId } → license + 30d-signed-URL
///   2. iOS: download .enc-File mit der URL → speichere in ~/Library/Caches/rolify-offline/
///   3. iOS: bei Play, check OfflineCache.localPath(trackId) → wenn vorhanden, decrypt-on-play
///           ohne Re-Download
///   4. iOS: POST /offline/licenses/:trackId/revoke → loescht local + license
///
/// Quota: max 100 Tracks pro Device. Backend enforced via DB-Count.
/// Expiry: 30 Tage, danach muss neu requested werden.

const RequestBody = z.object({
  trackId: z.string().min(1),
  deviceId: z.string().min(8).max(128),
});

const QUOTA_PER_DEVICE = 100;
const LICENSE_EXPIRY_DAYS = 30;
const SIGNED_URL_EXPIRY_S = 30 * 24 * 60 * 60; // 30d

export default async function offlineRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  // POST /offline/licenses — neue License + signed-URL fuer download
  app.post("/offline/licenses", async (req, reply) => {
    const body = RequestBody.parse(req.body);

    // Quota-Check: aktuelle aktive licenses fuer diesen device
    const activeLicenses = await prisma.offlineLicense.count({
      where: {
        userId: req.user.sub,
        deviceId: body.deviceId,
        expiresAt: { gt: new Date() },
      },
    });
    if (activeLicenses >= QUOTA_PER_DEVICE) {
      return reply.status(429).send({
        error: "quota_exceeded",
        message: `Max ${QUOTA_PER_DEVICE} Offline-Tracks pro Device. Loesche zuerst alte.`,
        quota: QUOTA_PER_DEVICE,
        used: activeLicenses,
      });
    }

    const track = await prisma.track.findUnique({
      where: { id: body.trackId },
      select: {
        id: true,
        encryptedBlobKey: true,
        masterKey: true,
      },
    });
    if (!track) return reply.status(404).send({ error: "track_not_found" });

    const expiresAt = new Date(Date.now() + LICENSE_EXPIRY_DAYS * 24 * 60 * 60 * 1000);

    // Upsert license (re-request fuer gleiches Track auf gleichem Device → refresh expiry)
    await prisma.offlineLicense.upsert({
      where: {
        userId_trackId_deviceId: {
          userId: req.user.sub,
          trackId: body.trackId,
          deviceId: body.deviceId,
        },
      },
      create: {
        userId: req.user.sub,
        trackId: body.trackId,
        deviceId: body.deviceId,
        encryptedKey: track.masterKey, // direkt re-store (vereinfacht; ECIES kommt spaeter)
        expiresAt,
      },
      update: { expiresAt, encryptedKey: track.masterKey },
    });

    // Signed URL fuer den .enc-Download (30d expiry)
    const cmd = new GetObjectCommand({
      Bucket: buckets.tracks,
      Key: track.encryptedBlobKey,
    });
    const downloadUrl = await getSignedUrl(s3Public, cmd, { expiresIn: SIGNED_URL_EXPIRY_S });

    return reply.status(201).send({
      trackId: track.id,
      downloadUrl,
      masterKeyHex: Buffer.from(track.masterKey).toString("hex"),
      expiresAt: expiresAt.toISOString(),
      quotaUsed: activeLicenses + 1,
      quotaTotal: QUOTA_PER_DEVICE,
    });
  });

  // GET /offline/licenses?deviceId=… — Liste aktive licenses (fuer iOS-Sync)
  app.get<{ Querystring: { deviceId?: string } }>("/offline/licenses", async (req) => {
    const deviceId = req.query.deviceId;
    const where = {
      userId: req.user.sub,
      expiresAt: { gt: new Date() },
      ...(deviceId ? { deviceId } : {}),
    };
    const licenses = await prisma.offlineLicense.findMany({
      where,
      select: {
        trackId: true,
        deviceId: true,
        expiresAt: true,
        issuedAt: true,
      },
    });
    return {
      licenses: licenses.map((l) => ({
        trackId: l.trackId,
        deviceId: l.deviceId,
        expiresAt: l.expiresAt.toISOString(),
        issuedAt: l.issuedAt.toISOString(),
      })),
      quota: QUOTA_PER_DEVICE,
    };
  });

  // DELETE /offline/licenses/:trackId — revoke (single device)
  app.delete<{ Params: { trackId: string }; Querystring: { deviceId: string } }>(
    "/offline/licenses/:trackId",
    async (req, reply) => {
      const deviceId = req.query.deviceId;
      if (!deviceId) return reply.status(400).send({ error: "deviceId_required" });
      await prisma.offlineLicense
        .delete({
          where: {
            userId_trackId_deviceId: {
              userId: req.user.sub,
              trackId: req.params.trackId,
              deviceId,
            },
          },
        })
        .catch(() => void 0);
      return reply.status(204).send();
    },
  );
}
