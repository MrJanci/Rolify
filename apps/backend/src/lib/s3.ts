import { S3Client } from "@aws-sdk/client-s3";
import { env } from "../config.js";

export const s3 = new S3Client({
  endpoint: env.MINIO_ENDPOINT,
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
