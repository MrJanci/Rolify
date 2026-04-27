-- v0.17: Dynamic Auto-Playlists + Lyrics-Cache

-- 1. Playlist erweitern fuer Dynamic-Sources
ALTER TABLE "Playlist" ADD COLUMN "isDynamic"        BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Playlist" ADD COLUMN "dynamicSource"    TEXT;
ALTER TABLE "Playlist" ADD COLUMN "rotationMode"     TEXT NOT NULL DEFAULT 'rotate';
ALTER TABLE "Playlist" ADD COLUMN "refreshIntervalH" INTEGER NOT NULL DEFAULT 24;
ALTER TABLE "Playlist" ADD COLUMN "lastRefreshedAt"  TIMESTAMP;
CREATE UNIQUE INDEX "Playlist_dynamicSource_key" ON "Playlist" ("dynamicSource");
CREATE INDEX "Playlist_isDynamic_idx" ON "Playlist" ("isDynamic");

-- 2. UserPlaylistSettings (per-user toggle fuer dyn-Playlist-Sichtbarkeit)
CREATE TABLE "UserPlaylistSettings" (
  "userId"  TEXT    NOT NULL,
  "source"  TEXT    NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT "UserPlaylistSettings_pkey" PRIMARY KEY ("userId", "source")
);
CREATE INDEX "UserPlaylistSettings_source_idx" ON "UserPlaylistSettings" ("source");
ALTER TABLE "UserPlaylistSettings" ADD CONSTRAINT "UserPlaylistSettings_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE;

-- 3. Lyrics-Cache (1:1 mit Track)
CREATE TABLE "Lyrics" (
  "trackId"   TEXT      NOT NULL PRIMARY KEY,
  "lrcSynced" TEXT,
  "plain"     TEXT,
  "source"    TEXT      NOT NULL DEFAULT 'lrclib',
  "cachedAt"  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "Lyrics_cachedAt_idx" ON "Lyrics" ("cachedAt");
ALTER TABLE "Lyrics" ADD CONSTRAINT "Lyrics_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id") ON DELETE CASCADE;
