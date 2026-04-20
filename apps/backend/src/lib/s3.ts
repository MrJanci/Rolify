import { S3Client } from "@aws-sdk/client-s3";
import { env } from "../config.js";

// Internal client: fuer Uploads + Bucket-Ops vom Backend aus (minio:9000)
export const s3 = new S3Client({
  endpoint: env.MINIO_ENDPOINT,
  region: "us-east-1",
  forcePathStyle: true,
  credentials: {
    accessKeyId: env.MINIO_USER,
    secretAccessKey: env.MINIO_PASSWORD,
  },
});

// Public-Signing client: generiert Presigned-URLs fuer die public CDN-Domain.
// Signature wird fuer Host=cdn.rolify.rolak.ch erzeugt -> MinIO validiert gegen
// den gleichen Host-Header den Caddy durchreicht.
export const s3Public = new S3Client({
  endpoint: env.MINIO_PUBLIC_ENDPOINT ?? env.MINIO_ENDPOINT,
  region: "us-east-1",
  forcePathStyle: true,
  credentials: {
    accessKeyId: env.MINIO_USER,
    secretAccessKey: env.MINIO_PASSWORD,
  },
});

export const buckets = {
  tracks: env.MINIO_BUCKET_TRACKS,
  covers: env.MINIO_BUCKET_COVERS,
  avatars: env.MINIO_BUCKET_AVATARS,
} as const;
