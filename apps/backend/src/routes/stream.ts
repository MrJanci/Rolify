import type { FastifyInstance } from "fastify";
import { GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { prisma } from "../lib/prisma.js";
import { buckets, s3 } from "../lib/s3.js";
import { env } from "../config.js";

/**
 * MVP-DRM: Single endpoint returns signed ciphertext URL + AES-256-GCM master key
 * (as hex). iOS client reads first 12 bytes of ciphertext as IV, rest is
 * ciphertext+16-byte-tag. Client decrypts via CryptoKit AES.GCM.open.
 *
 * TLS (Cloudflare -> Caddy -> Backend) protects the key in transit. ECIES
 * device-binding comes in a later iteration.
 */
export default async function streamRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get<{ Params: { trackId: string } }>("/stream/:trackId", async (req, reply) => {
    const track = await prisma.track.findUnique({
      where: { id: req.params.trackId },
      select: {
        id: true,
        title: true,
        durationMs: true,
        encryptedBlobKey: true,
        masterKey: true,
        artist: { select: { name: true } },
        album: { select: { coverUrl: true, title: true } },
      },
    });
    if (!track) return reply.status(404).send({ error: "not_found" });

    const cmd = new GetObjectCommand({ Bucket: buckets.tracks, Key: track.encryptedBlobKey });
    const signedCiphertextUrl = await getSignedUrl(s3, cmd, { expiresIn: 300 });

    // MinIO internal URL ist http://minio:9000 — Client braucht public URL
    const publicCiphertextUrl = env.MINIO_PUBLIC_ENDPOINT
      ? signedCiphertextUrl.replace(env.MINIO_ENDPOINT, env.MINIO_PUBLIC_ENDPOINT)
      : signedCiphertextUrl;

    return {
      trackId: track.id,
      title: track.title,
      artist: track.artist.name,
      album: track.album.title,
      coverUrl: track.album.coverUrl,
      durationMs: track.durationMs,
      signedCiphertextUrl: publicCiphertextUrl,
      masterKeyHex: Buffer.from(track.masterKey).toString("hex"),
      expiresInS: 300,
    };
  });
}
