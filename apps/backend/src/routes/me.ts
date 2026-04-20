import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { PutObjectCommand } from "@aws-sdk/client-s3";
import { prisma } from "../lib/prisma.js";
import { hashPassword, verifyPassword } from "../lib/crypto.js";
import { buckets, s3 } from "../lib/s3.js";
import { env } from "../config.js";

const UpdateProfileBody = z.object({
  displayName: z.string().min(2).max(40).optional(),
  bio: z.string().max(500).optional(),
});

const ChangePasswordBody = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8).max(128),
});

export default async function meRoutes(app: FastifyInstance) {
  app.addHook("preHandler", app.requireAuth);

  app.get("/me", async (req) => {
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: req.user.sub },
      select: {
        id: true,
        email: true,
        displayName: true,
        bio: true,
        avatarUrl: true,
        createdAt: true,
        subscriptionStatus: true,
      },
    });
    return user;
  });

  app.patch("/me", async (req) => {
    const body = UpdateProfileBody.parse(req.body);
    return prisma.user.update({
      where: { id: req.user.sub },
      data: body,
      select: { id: true, displayName: true, bio: true, avatarUrl: true },
    });
  });

  app.post("/me/change-password", async (req, reply) => {
    const body = ChangePasswordBody.parse(req.body);
    const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user.sub } });
    if (!(await verifyPassword(user.passwordHash, body.currentPassword))) {
      return reply.status(400).send({ error: "invalid_current_password" });
    }
    await prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: await hashPassword(body.newPassword) },
    });
    // Invalidiere alle anderen Sessions ausser der aktuellen
    await prisma.session.deleteMany({ where: { userId: user.id, NOT: { id: req.user.sid } } });
    return reply.status(204).send();
  });

  app.post("/me/avatar", async (req, reply) => {
    const file = await req.file({ limits: { fileSize: 5_000_000 } });
    if (!file) return reply.status(400).send({ error: "no_file" });

    const allowedMime = ["image/jpeg", "image/png", "image/webp"];
    if (!allowedMime.includes(file.mimetype)) {
      return reply.status(400).send({ error: "unsupported_media_type" });
    }

    const buffer = await file.toBuffer();
    const key = `${req.user.sub}.jpg`;

    await s3.send(
      new PutObjectCommand({
        Bucket: buckets.avatars,
        Key: key,
        Body: buffer,
        ContentType: file.mimetype,
        CacheControl: "public, max-age=31536000, immutable",
      }),
    );

    const base = env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT;
    const avatarUrl = `${base.replace(/\/$/, "")}/${buckets.avatars}/${key}`;

    const updated = await prisma.user.update({
      where: { id: req.user.sub },
      data: { avatarUrl },
      select: { avatarUrl: true },
    });
    return updated;
  });

  app.delete("/me/avatar", async (req, reply) => {
    await prisma.user.update({ where: { id: req.user.sub }, data: { avatarUrl: null } });
    return reply.status(204).send();
  });
}
