-- CreateEnum
CREATE TYPE "ScrapeStatus" AS ENUM ('QUEUED', 'RUNNING', 'DONE', 'FAILED');

-- CreateTable
CREATE TABLE "ScrapeJob" (
    "id" TEXT NOT NULL,
    "playlistUrl" TEXT NOT NULL,
    "status" "ScrapeStatus" NOT NULL DEFAULT 'QUEUED',
    "totalTracks" INTEGER NOT NULL DEFAULT 0,
    "processedTracks" INTEGER NOT NULL DEFAULT 0,
    "failedTracks" INTEGER NOT NULL DEFAULT 0,
    "errorMessage" TEXT,
    "createdBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "startedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "ScrapeJob_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ScrapeJob_status_createdAt_idx" ON "ScrapeJob"("status", "createdAt");
