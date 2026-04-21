import type { FastifyInstance } from "fastify";
import { randomBytes } from "node:crypto";
import { z } from "zod";

// WebSocket readyState constants (vom ws-Package, hardcoded um Import zu vermeiden)
const WS_OPEN = 1;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type WSLike = { readyState: number; send: (data: string) => void; close: (code?: number, reason?: string) => void };
import { prisma } from "../lib/prisma.js";
import { redis } from "../lib/redis.js";

// ============================================================================
// Jam-Protocol (WebSocket)
//
// Messages vom Client:
//   {type: "hello", token: "Bearer xxx"}           — Auth nach upgrade
//   {type: "track_change", trackId, positionMs}    — nur host
//   {type: "control", action: "play"|"pause", positionMs}  — nur host
//   {type: "seek", positionMs}                     — nur host
//   {type: "reaction", emoji: "🔥"}                — alle (broadcast)
//
// Messages vom Server:
//   {type: "state", ...full state}
//   {type: "participants", users: [{id, displayName, avatarUrl}]}
//   {type: "track_change", ...}    (broadcast von host)
//   {type: "control", ...}         (broadcast von host)
//   {type: "seek", ...}            (broadcast von host)
//   {type: "reaction", userId, emoji}
//   {type: "error", message}
// ============================================================================

function generateCode(): string {
  // 6 base36 Zeichen, upper-case, ohne 0/O/1/I fuer Lesbarkeit
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  return Array.from(randomBytes(6))
    .map((b) => alphabet[b % alphabet.length])
    .join("");
}

const HelloMsg = z.object({
  type: z.literal("hello"),
  token: z.string().min(10),
});

const ControlMsg = z.object({
  type: z.literal("control"),
  action: z.enum(["play", "pause"]),
  positionMs: z.number().int().min(0),
});

const TrackChangeMsg = z.object({
  type: z.literal("track_change"),
  trackId: z.string().min(1),
  positionMs: z.number().int().min(0).default(0),
});

const SeekMsg = z.object({
  type: z.literal("seek"),
  positionMs: z.number().int().min(0),
});

const ReactionMsg = z.object({
  type: z.literal("reaction"),
  emoji: z.string().min(1).max(8),
});

const CreateJamBody = z.object({
  name: z.string().min(1).max(60).optional(),
  trackId: z.string().optional(),
});

const JoinJamBody = z.object({
  code: z.string().min(4).max(10),
});

// ============================================================================

interface JamConnection {
  userId: string;
  displayName: string;
  socket: WSLike;
}

// In-memory connections pro jam-code. Fuer Single-Instance-Setup ausreichend.
// Fuer Multi-Worker waere Redis-Pubsub noetig (Fan-Out).
const connections = new Map<string, Set<JamConnection>>();

function getConns(code: string): Set<JamConnection> {
  let set = connections.get(code);
  if (!set) {
    set = new Set();
    connections.set(code, set);
  }
  return set;
}

function broadcast(code: string, msg: object, exclude?: WSLike) {
  const set = connections.get(code);
  if (!set) return;
  const payload = JSON.stringify(msg);
  for (const conn of set) {
    if (conn.socket !== exclude && conn.socket.readyState === WS_OPEN) {
      try { conn.socket.send(payload); } catch { /* ignore */ }
    }
  }
  // Cross-worker pub/sub (falls in Zukunft horizontal scaled)
  void redis.publish(`jam:${code}`, payload);
}

async function getParticipantsPayload(code: string) {
  const session = await prisma.jamSession.findUnique({
    where: { code },
    include: {
      participants: {
        where: { leftAt: null },
        include: { user: { select: { id: true, displayName: true, avatarUrl: true } } },
      },
    },
  });
  if (!session) return { type: "participants", users: [] };
  return {
    type: "participants",
    users: session.participants.map((p) => ({
      id: p.user.id,
      displayName: p.user.displayName,
      avatarUrl: p.user.avatarUrl,
    })),
    hostUserId: session.hostUserId,
  };
}

// ============================================================================

export default async function jamRoutes(app: FastifyInstance) {
  // REST-Endpoints brauchen Auth. WS-Auth laeuft ueber "hello"-Message.
  app.addHook("preHandler", (req, _reply, done) => {
    if (req.routeOptions.url?.endsWith("/ws")) { done(); return; }
    app.requireAuth(req).then(() => done()).catch(done);
  });

  // POST /jam — Create (host)
  app.post("/jam", async (req) => {
    const body = CreateJamBody.parse(req.body);
    const code = generateCode();
    const session = await prisma.jamSession.create({
      data: {
        hostUserId: req.user.sub,
        code,
        name: body.name,
        currentTrackId: body.trackId ?? null,
      },
    });
    // Host ist auch Participant
    await prisma.jamParticipant.create({
      data: { sessionId: session.id, userId: req.user.sub },
    });
    return {
      code: session.code,
      sessionId: session.id,
      name: session.name,
      hostUserId: session.hostUserId,
    };
  });

  // POST /jam/join — Guest joint via code
  app.post("/jam/join", async (req, reply) => {
    const { code } = JoinJamBody.parse(req.body);
    const session = await prisma.jamSession.findUnique({
      where: { code: code.toUpperCase() },
      include: { host: { select: { id: true, displayName: true, avatarUrl: true } } },
    });
    if (!session || session.endedAt) {
      return reply.status(404).send({ error: "not_found_or_ended" });
    }
    await prisma.jamParticipant
      .upsert({
        where: { sessionId_userId: { sessionId: session.id, userId: req.user.sub } },
        create: { sessionId: session.id, userId: req.user.sub },
        update: { leftAt: null, joinedAt: new Date() },
      })
      .catch(() => void 0);
    return {
      code: session.code,
      sessionId: session.id,
      name: session.name,
      hostUserId: session.hostUserId,
      hostDisplayName: session.host.displayName,
      currentTrackId: session.currentTrackId,
      positionMs: session.positionMs,
      isPaused: session.isPaused,
    };
  });

  // GET /jam/:code — State
  app.get<{ Params: { code: string } }>("/jam/:code", async (req, reply) => {
    const session = await prisma.jamSession.findUnique({
      where: { code: req.params.code.toUpperCase() },
      include: {
        host: { select: { id: true, displayName: true, avatarUrl: true } },
        participants: {
          where: { leftAt: null },
          include: { user: { select: { id: true, displayName: true, avatarUrl: true } } },
        },
        currentTrack: {
          include: {
            artist: { select: { id: true, name: true } },
            album: { select: { id: true, title: true, coverUrl: true } },
          },
        },
      },
    });
    if (!session || session.endedAt) {
      return reply.status(404).send({ error: "not_found_or_ended" });
    }
    return {
      code: session.code,
      sessionId: session.id,
      name: session.name,
      hostUserId: session.hostUserId,
      isPaused: session.isPaused,
      positionMs: session.positionMs,
      currentTrack: session.currentTrack
        ? {
            id: session.currentTrack.id,
            title: session.currentTrack.title,
            artist: session.currentTrack.artist.name,
            albumId: session.currentTrack.album.id,
          }
        : null,
      participants: session.participants.map((p) => ({
        id: p.user.id,
        displayName: p.user.displayName,
        avatarUrl: p.user.avatarUrl,
      })),
    };
  });

  // DELETE /jam/:code — Host endet Session
  app.delete<{ Params: { code: string } }>("/jam/:code", async (req, reply) => {
    const session = await prisma.jamSession.findUnique({
      where: { code: req.params.code.toUpperCase() },
    });
    if (!session || session.hostUserId !== req.user.sub) {
      return reply.status(404).send({ error: "not_found_or_not_host" });
    }
    await prisma.jamSession.update({
      where: { id: session.id },
      data: { endedAt: new Date() },
    });
    broadcast(session.code, { type: "ended" });
    connections.delete(session.code);
    return reply.status(204).send();
  });

  // POST /jam/:code/leave — Participant verlaesst
  app.post<{ Params: { code: string } }>("/jam/:code/leave", async (req, reply) => {
    const session = await prisma.jamSession.findUnique({
      where: { code: req.params.code.toUpperCase() },
    });
    if (!session) return reply.status(404).send({ error: "not_found" });
    await prisma.jamParticipant
      .update({
        where: { sessionId_userId: { sessionId: session.id, userId: req.user.sub } },
        data: { leftAt: new Date() },
      })
      .catch(() => void 0);
    broadcast(session.code, await getParticipantsPayload(session.code));
    return reply.status(204).send();
  });

  // ========================================================================
  // WebSocket /jam/:code/ws
  // ========================================================================

  app.get<{ Params: { code: string } }>("/jam/:code/ws", { websocket: true }, (socket, req) => {
    const code = (req.params as { code: string }).code.toUpperCase();
    let userId: string | null = null;
    let displayName: string | null = null;
    let conn: JamConnection | null = null;

    socket.on("message", async (raw: Buffer) => {
      let msg: unknown;
      try { msg = JSON.parse(raw.toString()); }
      catch { return; }

      // Auth-Handshake: erste Message muss "hello" sein
      if (userId === null) {
        const parsed = HelloMsg.safeParse(msg);
        if (!parsed.success) {
          socket.send(JSON.stringify({ type: "error", message: "auth_required" }));
          socket.close();
          return;
        }
        try {
          const token = parsed.data.token.replace(/^Bearer\s+/i, "");
          const decoded = app.jwt.verify(token) as { sub: string };
          const user = await prisma.user.findUnique({
            where: { id: decoded.sub },
            select: { id: true, displayName: true },
          });
          if (!user) throw new Error("user_not_found");
          userId = user.id;
          displayName = user.displayName;

          // Session existiert?
          const session = await prisma.jamSession.findUnique({
            where: { code },
            include: {
              currentTrack: {
                include: {
                  artist: { select: { id: true, name: true } },
                  album: { select: { id: true, coverUrl: true } },
                },
              },
            },
          });
          if (!session || session.endedAt) {
            socket.send(JSON.stringify({ type: "error", message: "session_ended" }));
            socket.close();
            return;
          }

          // Connection registrieren
          conn = { userId, displayName, socket };
          getConns(code).add(conn);

          // Full-State senden an new-joiner
          socket.send(JSON.stringify({
            type: "state",
            hostUserId: session.hostUserId,
            currentTrackId: session.currentTrackId,
            positionMs: session.positionMs,
            isPaused: session.isPaused,
            positionUpdatedAt: session.positionUpdatedAt.getTime(),
          }));
          // Participants update
          broadcast(code, await getParticipantsPayload(code));
        } catch {
          socket.send(JSON.stringify({ type: "error", message: "auth_failed" }));
          socket.close();
        }
        return;
      }

      // Auth nicht noch einmal verarbeiten
      const session = await prisma.jamSession.findUnique({ where: { code } });
      if (!session) {
        socket.close();
        return;
      }
      const isHost = session.hostUserId === userId;

      // Track-Change
      const trackChange = TrackChangeMsg.safeParse(msg);
      if (trackChange.success) {
        if (!isHost) { socket.send(JSON.stringify({ type: "error", message: "host_only" })); return; }
        await prisma.jamSession.update({
          where: { id: session.id },
          data: {
            currentTrackId: trackChange.data.trackId,
            positionMs: trackChange.data.positionMs,
            positionUpdatedAt: new Date(),
            isPaused: false,
          },
        });
        broadcast(code, {
          type: "track_change",
          trackId: trackChange.data.trackId,
          positionMs: trackChange.data.positionMs,
          serverTs: Date.now(),
        });
        return;
      }

      // Control (play/pause)
      const control = ControlMsg.safeParse(msg);
      if (control.success) {
        if (!isHost) { socket.send(JSON.stringify({ type: "error", message: "host_only" })); return; }
        await prisma.jamSession.update({
          where: { id: session.id },
          data: {
            isPaused: control.data.action === "pause",
            positionMs: control.data.positionMs,
            positionUpdatedAt: new Date(),
          },
        });
        broadcast(code, {
          type: "control",
          action: control.data.action,
          positionMs: control.data.positionMs,
          serverTs: Date.now(),
        });
        return;
      }

      // Seek
      const seek = SeekMsg.safeParse(msg);
      if (seek.success) {
        if (!isHost) { socket.send(JSON.stringify({ type: "error", message: "host_only" })); return; }
        await prisma.jamSession.update({
          where: { id: session.id },
          data: { positionMs: seek.data.positionMs, positionUpdatedAt: new Date() },
        });
        broadcast(code, {
          type: "seek",
          positionMs: seek.data.positionMs,
          serverTs: Date.now(),
        });
        return;
      }

      // Reaction — alle duerfen
      const reaction = ReactionMsg.safeParse(msg);
      if (reaction.success) {
        broadcast(code, {
          type: "reaction",
          userId,
          displayName,
          emoji: reaction.data.emoji,
          ts: Date.now(),
        });
        return;
      }
    });

    socket.on("close", async () => {
      if (!conn) return;
      getConns(code).delete(conn);
      if (userId) {
        await prisma.jamParticipant
          .update({
            where: { sessionId_userId: { sessionId: (await prisma.jamSession.findUnique({ where: { code } }))?.id ?? "", userId } },
            data: { leftAt: new Date() },
          })
          .catch(() => void 0);
        broadcast(code, await getParticipantsPayload(code));
      }
    });
  });
}
