import fp from "fastify-plugin";
import { ZodError } from "zod";
import type { FastifyInstance } from "fastify";

export default fp(async (app: FastifyInstance) => {
  app.setErrorHandler((err, _req, reply) => {
    if (err instanceof ZodError) {
      return reply.status(400).send({ error: "validation_error", details: err.issues });
    }
    // Prisma Unique Constraint
    if ((err as { code?: string }).code === "P2002") {
      return reply.status(409).send({ error: "conflict", message: "resource already exists" });
    }
    const statusCode = err.statusCode ?? 500;
    const logLevel = statusCode >= 500 ? "error" : "warn";
    app.log[logLevel]({ err }, "request_failed");
    return reply.status(statusCode).send({
      error: err.name || "internal_error",
      message: err.message || "something went wrong",
    });
  });
});
