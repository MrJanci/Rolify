import type { FastifyInstance } from "fastify";
import { randomBytes } from "node:crypto";
import { prisma } from "../lib/prisma.js";
import { redis } from "../lib/redis.js";

// Skeleton fuer Woche 9. WebSocket-Broadcast-Logik kommt dort dazu.

function generateCode(): string {
  // 6 base36 Zeichen, upper-case, ohne 0/O/1/I fuer Lesbarkeit
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  return Array.from(randomBytes(6))
    .map((b) => alphabet[b % alphabet.length])
    .join("");
}

export default async function jamRoutes(app: FastifyInstance) {
  app.addHook("preHandler", (req, _reply, done) => {
    // WS upgrade kommt vor preHandler — nur POST /jam braucht Auth.
    if (req.routeOptions.url === "/jam" && req.method === "POST") {
      return app.requireAuth(req).then(() => done()).catch(done);
    }
    done();
  });

  app.post("/jam", async (req) => {
    const code = generateCode();
    const session = await prisma.jamSession.create({
      data: { hostUserId: req.user.sub, code },
    });
    return { code: session.code, sessionId: session.id };
  });

  app.get<{ Params: { code: string } }>("/jam/:code", { websocket: true }, (socket, req) => {
    const { code } = req.params;
    const channel = `jam:${code}`;
    // TODO [Woche 9]: Redis pub/sub fuer cross-worker broadcast
    socket.send(JSON.stringify({ type: "hello", code, ts: Date.now() }));
    socket.on("message", (raw) => {
      // Echo-Skeleton — Woche 9 macht richtiges Protocol (track_change, control_play, etc.)
      void redis.publish(channel, raw.toString());
    });
  });
}
