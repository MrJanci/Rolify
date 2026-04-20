import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { prisma } from "../lib/prisma.js";
import { generateRefreshToken, hashPassword, hashRefreshToken, verifyPassword } from "../lib/crypto.js";
import { env, isEmailAllowed } from "../config.js";

const RegisterBody = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(8).max(128),
  displayName: z.string().min(2).max(40),
  deviceId: z.string().min(8).max(128),
});

const LoginBody = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(1).max(128),
  deviceId: z.string().min(8).max(128),
});

const RefreshBody = z.object({
  refreshToken: z.string().min(1),
});

// Strenge Rate-Limits fuer Auth-Endpoints (anti-brute-force, anti-enumeration)
const strictAuthLimit = { config: { rateLimit: { max: 5, timeWindow: "5 minutes" } } };
const mediumAuthLimit = { config: { rateLimit: { max: 20, timeWindow: "5 minutes" } } };

export default async function authRoutes(app: FastifyInstance) {
  app.post("/auth/register", strictAuthLimit, async (req, reply) => {
    const body = RegisterBody.parse(req.body);

    // Email-Whitelist: unauthorisierte Emails kriegen generic 401 (kein enumeration-leak)
    if (!isEmailAllowed(body.email)) {
      return reply.status(401).send({ error: "invalid_credentials" });
    }

    const existing = await prisma.user.findUnique({ where: { email: body.email } });
    // Same response-shape on conflict to avoid user enumeration timing leak
    if (existing) return reply.status(409).send({ error: "email_in_use" });

    const user = await prisma.user.create({
      data: {
        email: body.email,
        displayName: body.displayName,
        passwordHash: await hashPassword(body.password),
      },
    });

    return reply.status(201).send(await issueTokens(app, user.id, body.deviceId, req.headers["user-agent"]));
  });

  app.post("/auth/login", strictAuthLimit, async (req, reply) => {
    const body = LoginBody.parse(req.body);

    // Email-Whitelist: unauthorisierte Emails kriegen generic 401 (gleicher Error wie wrong-password)
    if (!isEmailAllowed(body.email)) {
      return reply.status(401).send({ error: "invalid_credentials" });
    }

    const user = await prisma.user.findUnique({ where: { email: body.email } });
    if (!user || !(await verifyPassword(user.passwordHash, body.password))) {
      // Same error for "user doesn't exist" and "wrong password" -> no enumeration
      return reply.status(401).send({ error: "invalid_credentials" });
    }
    return reply.send(await issueTokens(app, user.id, body.deviceId, req.headers["user-agent"]));
  });

  app.post("/auth/refresh", mediumAuthLimit, async (req, reply) => {
    const { refreshToken } = RefreshBody.parse(req.body);
    const session = await prisma.session.findUnique({
      where: { refreshTokenHash: hashRefreshToken(refreshToken) },
    });
    if (!session) return reply.status(401).send({ error: "invalid_refresh" });

    // Rotiere Refresh-Token (single-use).
    const newRaw = generateRefreshToken();
    await prisma.session.update({
      where: { id: session.id },
      data: { refreshTokenHash: hashRefreshToken(newRaw), lastSeenAt: new Date() },
    });

    const access = app.jwt.sign({ sub: session.userId, sid: session.id });
    return reply.send({ accessToken: access, refreshToken: newRaw });
  });

  app.post("/auth/logout", { preHandler: app.requireAuth }, async (req, reply) => {
    const sid = req.user.sid;
    await prisma.session.delete({ where: { id: sid } }).catch(() => void 0);
    return reply.status(204).send();
  });
}

async function issueTokens(app: FastifyInstance, userId: string, deviceId: string, userAgent?: string) {
  const refresh = generateRefreshToken();
  const session = await prisma.session.create({
    data: {
      userId,
      deviceId,
      refreshTokenHash: hashRefreshToken(refresh),
      userAgent: userAgent?.slice(0, 255),
    },
  });
  const access = app.jwt.sign({ sub: userId, sid: session.id });
  return {
    accessToken: access,
    refreshToken: refresh,
    accessTokenTtl: env.JWT_ACCESS_TTL,
  };
}
