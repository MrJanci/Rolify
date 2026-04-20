import fp from "fastify-plugin";
import jwt from "@fastify/jwt";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { env } from "../config.js";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: { sub: string; sid: string };
    user: { sub: string; sid: string };
  }
}

declare module "fastify" {
  interface FastifyInstance {
    requireAuth: (req: FastifyRequest) => Promise<void>;
  }
}

// Registriert JWT-Plugin + dekoriert fastify mit `requireAuth` Middleware.
export default fp(async (app: FastifyInstance) => {
  await app.register(jwt, {
    secret: env.JWT_SECRET,
    sign: { expiresIn: env.JWT_ACCESS_TTL },
  });

  app.decorate("requireAuth", async (req: FastifyRequest) => {
    try {
      await req.jwtVerify();
    } catch {
      throw app.httpErrors?.unauthorized?.("invalid or missing token") ?? new Error("unauthorized");
    }
  });
});
