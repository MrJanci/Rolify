import "dotenv/config";
import { z } from "zod";

// Zentrale Env-Validierung. Failt beim Start, falls Env-Vars fehlen.
const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  PORT: z.coerce.number().default(3000),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),

  MINIO_ENDPOINT: z.string().url(),
  MINIO_PUBLIC_ENDPOINT: z.string().url().optional(),
  MINIO_USER: z.string().min(1),
  MINIO_PASSWORD: z.string().min(1),
  MINIO_BUCKET_TRACKS: z.string().default("tracks"),
  MINIO_BUCKET_COVERS: z.string().default("covers"),
  MINIO_BUCKET_AVATARS: z.string().default("avatars"),

  JWT_SECRET: z.string().min(32, "JWT_SECRET muss >= 32 Zeichen sein"),
  JWT_ACCESS_TTL: z.string().default("15m"),
  JWT_REFRESH_TTL: z.string().default("30d"),
  CORS_ORIGIN: z.string().default("*"),

  SPOTIFY_CLIENT_ID: z.string().optional(),
  SPOTIFY_CLIENT_SECRET: z.string().optional(),

  // Email-Whitelist (comma-separated). Leer = alle erlaubt.
  ALLOWED_EMAILS: z.string().default(""),
});

// Helper: ist email in der Allowlist?
export function isEmailAllowed(email: string): boolean {
  const raw = process.env.ALLOWED_EMAILS?.trim() ?? "";
  if (!raw) return true;   // keine Liste -> alle erlaubt
  const list = raw.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  return list.includes(email.trim().toLowerCase());
}

export type Env = z.infer<typeof EnvSchema>;

export const env: Env = EnvSchema.parse(process.env);
