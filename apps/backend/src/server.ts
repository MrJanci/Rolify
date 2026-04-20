import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import multipart from "@fastify/multipart";
import websocket from "@fastify/websocket";

import { env } from "./config.js";
import { prisma } from "./lib/prisma.js";
import { redis } from "./lib/redis.js";

import authPlugin from "./plugins/auth.js";
import errorHandler from "./plugins/errorHandler.js";

import healthRoutes from "./routes/health.js";
import authRoutes from "./routes/auth.js";
import meRoutes from "./routes/me.js";
import userRoutes from "./routes/users.js";
import playlistRoutes from "./routes/playlists.js";
import trackRoutes from "./routes/tracks.js";
import libraryRoutes from "./routes/library.js";
import searchRoutes from "./routes/search.js";
import browseRoutes from "./routes/browse.js";
import streamRoutes from "./routes/stream.js";
import jamRoutes from "./routes/jam.js";

async function buildServer() {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === "development" ? "debug" : "info",
      transport:
        env.NODE_ENV === "development"
          ? { target: "pino-pretty", options: { translateTime: "HH:MM:ss", ignore: "pid,hostname" } }
          : undefined,
    },
    trustProxy: true,
    bodyLimit: 16 * 1024 * 1024,
  });

  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, { origin: env.CORS_ORIGIN.split(",").map((s) => s.trim()) });
  await app.register(rateLimit, {
    max: 300,
    timeWindow: "1 minute",
    // Reverse-Proxy setzt CF-Connecting-IP / X-Real-IP; fastify trustProxy=true respektiert das.
    keyGenerator: (req) => req.ip,
  });
  await app.register(multipart, { limits: { fileSize: 16 * 1024 * 1024 } });
  await app.register(websocket);

  // Defense-in-Depth: Root und unbekannte Paths geben nur 404 (kein Branding, keine Version)
  app.setNotFoundHandler((_req, reply) => {
    reply.status(404).send();
  });

  await app.register(errorHandler);
  await app.register(authPlugin);

  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(meRoutes);
  await app.register(userRoutes);
  await app.register(playlistRoutes);
  await app.register(trackRoutes);
  await app.register(libraryRoutes);
  await app.register(searchRoutes);
  await app.register(browseRoutes);
  await app.register(streamRoutes);
  await app.register(jamRoutes);

  app.addHook("onClose", async () => {
    await prisma.$disconnect();
    await redis.quit();
  });

  return app;
}

async function main() {
  const app = await buildServer();
  try {
    await app.listen({ host: "0.0.0.0", port: env.PORT });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

void main();
