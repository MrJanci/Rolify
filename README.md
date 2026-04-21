# Rolify

Self-hosted Spotify-Klon. Native iOS App, eigenes Backend, automatisierte Music-Acquisition-Pipeline, Custom-DRM fuer Offline-Songs, Jam-Feature.

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-login.png" width="22%" alt="Login" />
  <img src="docs/screenshots/02-home.png" width="22%" alt="Home" />
  <img src="docs/screenshots/03-library.png" width="22%" alt="Library" />
  <img src="docs/screenshots/04-search.png" width="22%" alt="Search + Create" />
</p>

## Struktur

```
apps/
  backend/       Node.js Fastify API + Prisma
  ios/           Swift / SwiftUI Xcode Projekt
scraping/
  ui_scraper/    Parallel async Agents fuer Design-Token-Extraktion
  music_acquirer/ Spotify-Meta + yt-dlp + ffmpeg + AES-Encryption
design-tokens/   Output der UI-Scraping-Pipeline (committed)
infra/           Docker-Compose, Nginx-Config, Certs
.github/
  workflows/     CI fuer iOS-Build + Backend-Deploy + Scraping-Cron
```

## Stack

- **iOS:** Swift + SwiftUI (iOS 17+), Build via GitHub Actions macOS-Runner, Deploy via SideStore
- **Backend:** Node.js 22 + Fastify + TypeScript + Prisma
- **DB / Cache:** PostgreSQL 16, Redis 7
- **Storage:** MinIO (S3-kompatibel, selfhosted)
- **Scraping:** Python 3.12, Playwright, yt-dlp, ffmpeg
- **CDN:** Cloudflare (Free Tier)
- **Payments:** Stripe (Phase 2, nach MVP)

## Quickstart

```bash
cp infra/.env.example infra/.env
cd infra && docker compose up -d
cd ../apps/backend && pnpm install && pnpm prisma migrate dev && pnpm dev
cd ../../scraping && pip install -r requirements.txt
```

## MVP-Scope

Account / Profile / Catalog / Playlists / Library / Playback (online + offline mit DRM) / Jam.
Payments + Paywall + Grace-Period erst **Phase 2** nach MVP.
