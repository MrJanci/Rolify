-- v0.16: Auto-Playlist-Creation nach Scrape

ALTER TABLE "ScrapeJob" ADD COLUMN "resultPlaylistId" TEXT;
