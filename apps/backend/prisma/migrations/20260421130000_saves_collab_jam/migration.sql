-- v0.14: Saves (Albums/Artists), Collab-Playlists, Jam-Protocol-Erweiterungen

-- Playlist erweitern
ALTER TABLE "Playlist" ADD COLUMN "isCollaborative" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Playlist" ADD COLUMN "isMixed"         BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Playlist" ADD COLUMN "mixSeedId"       TEXT;

-- SavedAlbum
CREATE TABLE "SavedAlbum" (
  "userId"  TEXT      NOT NULL,
  "albumId" TEXT      NOT NULL,
  "savedAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SavedAlbum_pkey" PRIMARY KEY ("userId", "albumId")
);
CREATE INDEX "SavedAlbum_userId_savedAt_idx" ON "SavedAlbum" ("userId", "savedAt");
ALTER TABLE "SavedAlbum" ADD CONSTRAINT "SavedAlbum_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE;
ALTER TABLE "SavedAlbum" ADD CONSTRAINT "SavedAlbum_albumId_fkey"
  FOREIGN KEY ("albumId") REFERENCES "Album"("id") ON DELETE CASCADE;

-- SavedArtist
CREATE TABLE "SavedArtist" (
  "userId"   TEXT      NOT NULL,
  "artistId" TEXT      NOT NULL,
  "savedAt"  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SavedArtist_pkey" PRIMARY KEY ("userId", "artistId")
);
CREATE INDEX "SavedArtist_userId_savedAt_idx" ON "SavedArtist" ("userId", "savedAt");
ALTER TABLE "SavedArtist" ADD CONSTRAINT "SavedArtist_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE;
ALTER TABLE "SavedArtist" ADD CONSTRAINT "SavedArtist_artistId_fkey"
  FOREIGN KEY ("artistId") REFERENCES "Artist"("id") ON DELETE CASCADE;

-- PlaylistCollaborator
CREATE TYPE "CollabRole" AS ENUM ('EDITOR', 'VIEWER');
CREATE TABLE "PlaylistCollaborator" (
  "playlistId" TEXT         NOT NULL,
  "userId"     TEXT         NOT NULL,
  "role"       "CollabRole" NOT NULL DEFAULT 'EDITOR',
  "addedAt"    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PlaylistCollaborator_pkey" PRIMARY KEY ("playlistId", "userId")
);
CREATE INDEX "PlaylistCollaborator_userId_idx" ON "PlaylistCollaborator" ("userId");
ALTER TABLE "PlaylistCollaborator" ADD CONSTRAINT "PlaylistCollaborator_playlistId_fkey"
  FOREIGN KEY ("playlistId") REFERENCES "Playlist"("id") ON DELETE CASCADE;
ALTER TABLE "PlaylistCollaborator" ADD CONSTRAINT "PlaylistCollaborator_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE;

-- JamSession erweitern
ALTER TABLE "JamSession" ADD COLUMN "name"              TEXT;
ALTER TABLE "JamSession" ADD COLUMN "currentTrackId"    TEXT;
ALTER TABLE "JamSession" ADD COLUMN "isPaused"          BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "JamSession" ADD COLUMN "positionMs"        INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "JamSession" ADD COLUMN "positionUpdatedAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "JamSession" ADD CONSTRAINT "JamSession_currentTrackId_fkey"
  FOREIGN KEY ("currentTrackId") REFERENCES "Track"("id") ON DELETE SET NULL;

-- JamParticipant
CREATE TABLE "JamParticipant" (
  "sessionId" TEXT      NOT NULL,
  "userId"    TEXT      NOT NULL,
  "joinedAt"  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "leftAt"    TIMESTAMP,
  CONSTRAINT "JamParticipant_pkey" PRIMARY KEY ("sessionId", "userId")
);
CREATE INDEX "JamParticipant_sessionId_idx" ON "JamParticipant" ("sessionId");
ALTER TABLE "JamParticipant" ADD CONSTRAINT "JamParticipant_sessionId_fkey"
  FOREIGN KEY ("sessionId") REFERENCES "JamSession"("id") ON DELETE CASCADE;
ALTER TABLE "JamParticipant" ADD CONSTRAINT "JamParticipant_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE;
