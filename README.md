# Rolify

Self-hosted Spotify-Klon. Native iOS App, eigenes Backend, automatisierte Music-Acquisition-Pipeline, Custom-DRM für Offline-Songs, Lyrics, Crossfade, Jam, Auto-Playlists.

> ⚠️ **Rechtlicher Hinweis:** Dieses Projekt scrapet Audio-Inhalte von YouTube/Spotify ohne Lizenz. Das ist **nur für privaten Eigenbedarf** zulässig. Verkauf, kommerzielle Nutzung oder Verbreitung außerhalb des engsten Freundeskreises ist in vielen Ländern (CH/DE/EU) **strafbar** nach Urheberrechtsgesetz. Selber tragen.

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-login.png" width="22%" alt="Login" />
  <img src="docs/screenshots/02-home.png" width="22%" alt="Home" />
  <img src="docs/screenshots/03-library.png" width="22%" alt="Library" />
  <img src="docs/screenshots/04-search.png" width="22%" alt="Search + Create" />
</p>

---

## Features

- 🎵 Native iOS-App im Spotify-Look (SwiftUI, iOS 18+, Pure-Black)
- 🔐 Eigene AES-256-GCM-DRM für Tracks
- 📥 Auto-Scraping von Spotify-Playlists & YouTube-Searches
- 📝 Time-Synced Lyrics via LRClib (gratis)
- 🎚 Crossfade zwischen Tracks (0-12s einstellbar)
- 💾 Offline-Download (encrypted Cache)
- 🎉 Jam-Sessions (live zusammen hören) — Online (WebSocket) + lokal (Bluetooth via MultipeerConnectivity)
- ⚡ Dynamic Auto-Playlists (Last.fm Top-Charts + TikTok Trending, daily refresh)
- 👥 Collab-Playlists (mehrere User editieren gleiche Playlist)
- 🚗 Bluetooth-Auto-Display ("Rolify"-Brand im Album-Feld)
- 🔒 Email-Whitelist + JWT + Rate-Limiting

---

## Architektur

```
┌────────────┐         HTTPS              ┌──────────────────────┐
│  iOS App   │ ◄─────────────────────────►│   Caddy + Cloudflare │
│ (SwiftUI)  │                            │  rolify.deine-tld    │
└─────┬──────┘                            └──────────┬───────────┘
      │ WebSocket (Jam)                              │
      │ MultipeerConnectivity (BT-Jam)               │
      ▼                                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Raspberry Pi 5 (oder VPS)                       │
│  ┌─────────┐  ┌────────┐  ┌─────────┐  ┌──────────┐  ┌───────┐ │
│  │ Backend │◄─│Postgres│  │  Redis  │  │  MinIO   │  │Anisette│ │
│  │ Fastify │  │   16   │  │    7    │  │ (S3)     │  │ (Side- │ │
│  │ + Prisma│  └────────┘  └─────────┘  │ Tracks   │  │ Store) │ │
│  └────┬────┘                            └──────────┘  └────────┘ │
│       │                                                           │
│  ┌────▼────────────────────────────────┐                          │
│  │  Scraper (Python)                    │                          │
│  │  • spotipy (Spotify metadata)        │                          │
│  │  • yt-dlp (YouTube download)         │                          │
│  │  • ffmpeg (transcode m4a)            │                          │
│  │  • AES-256-GCM encrypt → MinIO       │                          │
│  └──────────────────────────────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

**Stack:**
- **iOS:** Swift + SwiftUI (iOS 18+), Build via GitHub Actions macOS-Runner, Sideload via SideStore
- **Backend:** Node.js 22 + Fastify + TypeScript + Prisma
- **DB:** PostgreSQL 16, Redis 7
- **Storage:** MinIO (S3-kompatibel, self-hosted)
- **Scraping:** Python 3.13, yt-dlp, ffmpeg, spotipy
- **Reverse-Proxy:** Caddy (auto-TLS via Cloudflare DNS-01)
- **CDN/DNS:** Cloudflare (gratis)
- **iOS-Distribution:** SideStore + eigener Anisette-Server

---

## Setup für dich selbst (von Null)

### Voraussetzungen

- **Hardware:** Raspberry Pi 5 (8 GB RAM empfohlen) oder VPS (mind. 4 GB RAM, 50 GB SSD)
- **Domain:** eine eigene Domain (z.B. via Cloudflare, gratis)
- **iPhone:** mit iOS 18+ und SideStore (oder Android-Port falls vorhanden)
- **Mac/PC:** für SideStore Pairing-File (einmalig)
- **Spotify-Account:** für Scraping-OAuth (kann normaler Free-Account sein)
- **Last.fm-Account:** für Auto-Playlists (kostenloser API-Key)
- **YouTube-Account:** mit Altersverifikation für age-gated Videos (optional aber empfohlen)

---

### 1. Repo klonen + Pi vorbereiten

```bash
ssh pi@<deine-pi-ip>
sudo apt update && sudo apt install -y docker.io docker-compose-v2 git caddy
sudo systemctl enable docker
sudo usermod -aG docker $USER
# logout + login

git clone git@github.com:DEIN-FORK/Rolify.git ~/rolify
cd ~/rolify
```

### 2. Cloudflare DNS

In Cloudflare:
- A-Record `rolify.deine-domain.tld` → IP deines Routers (Public-WAN-IP)
- A-Record `rolify-cdn.deine-domain.tld` → gleiche IP
- A-Record `anisette.deine-domain.tld` → gleiche IP (für SideStore-Refresh)
- A-Record `wireguard.deine-domain.tld` → gleiche IP (optional, für VPN)

Router-Port-Forward `443/tcp` → Pi-LAN-IP:443.

### 3. Caddy konfigurieren

`/etc/caddy/Caddyfile` (auf dem Pi):

```caddy
{
    email deine@email.tld
    acme_dns cloudflare {env.CF_API_TOKEN}
}

rolify.deine-domain.tld {
    @api path /health* /auth/* /me* /users/* /playlists* /tracks/* /albums/* /artists/* /library/* /search* /browse/* /stream/* /offline/* /jam* /admin/* /dynamic/*
    handle @api {
        reverse_proxy 127.0.0.1:3000 {
            header_up X-Real-IP {http.request.header.CF-Connecting-IP}
            header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
        }
    }
    handle { respond "" 404 }
}

rolify-cdn.deine-domain.tld {
    @buckets path /covers/* /avatars/* /tracks/*
    handle @buckets {
        reverse_proxy 127.0.0.1:9000
    }
    handle { respond "" 404 }
}

anisette.deine-domain.tld {
    reverse_proxy 127.0.0.1:6969
}
```

`CF_API_TOKEN` als env-var setzen (Cloudflare → My Profile → API Tokens → "Edit Zone DNS"-Permission).

```bash
sudo systemctl restart caddy
```

### 4. Spotify Developer App

1. https://developer.spotify.com/dashboard → "Create app"
2. Name: "Rolify Scraper", Description: irgendwas, Redirect URI: `http://127.0.0.1:3000/callback`
3. APIs: nur "Web API" anklicken
4. Speichern → **Client ID** + **Client Secret** kopieren

### 5. Last.fm API-Key

1. https://www.last.fm/api/account/create
2. Application name: "Rolify Personal"
3. Description: "Personal music app"
4. → "Create" → **API key** kopieren

### 6. YouTube Cookies (für age-gated Videos, optional)

Am PC im Browser bei YouTube einloggen:
1. Extension "Get cookies.txt LOCALLY" installieren
2. Auf youtube.com → Extension öffnen → "Export"
3. `.youtube-cookies.txt` Datei aufs Pi kopieren:

```bash
scp ~/Downloads/www.youtube.com_cookies.txt pi@<pi-ip>:~/rolify/scraping/.youtube-cookies.txt
chmod 600 ~/rolify/scraping/.youtube-cookies.txt
```

### 7. Backend `.env`

```bash
cd ~/rolify/infra
cp .env.example .env
nano .env
```

Fülle aus:

```env
# Postgres / Redis / MinIO — generiere zufällige Passwörter
PG_PASSWORD=$(openssl rand -hex 24)
REDIS_PASSWORD=$(openssl rand -hex 24)
MINIO_USER=minioadmin
MINIO_PASSWORD=$(openssl rand -hex 24)

# JWT — MUSS >=32 Zeichen sein
JWT_SECRET=$(openssl rand -hex 32)

# Public URLs
MINIO_PUBLIC_ENDPOINT=https://rolify-cdn.deine-domain.tld
CORS_ORIGIN=https://rolify.deine-domain.tld

# Spotify (von Schritt 4)
SPOTIFY_CLIENT_ID=dein_client_id
SPOTIFY_CLIENT_SECRET=dein_client_secret

# Last.fm (von Schritt 5)
LASTFM_API_KEY=dein_lastfm_key

# Email-Whitelist (komma-separiert) — nur diese können sich registrieren
ALLOWED_EMAILS=deine@email.tld,freund1@email.tld
```

> ⚠️ Niemals `.env` committen — `.gitignore` sorgt dafür.

### 8. Spotify-OAuth einmalig durchlaufen

```bash
cd ~/rolify/scraping
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -c "from music_acquirer.spotify_meta import _client; _client().current_user()"
# Browser öffnet → Spotify-Login → "Authorize" → Token wird in scraping/.spotify-token.json gecacht
```

### 9. Docker-Stack starten

```bash
cd ~/rolify/infra
docker compose up -d
docker exec rolify-backend npx prisma migrate deploy
```

Verify:
```bash
curl https://rolify.deine-domain.tld/health
# Erwarte: {"ok":true}
```

### 10. SideStore + iOS-App

Komplette Anleitung: siehe internes Setup (nicht in Repo aus Privacy-Gründen).

Kurzfassung:
1. SideStore auf iPhone installieren (https://sidestore.io)
2. Pairing-File einmalig am PC mit `jitterbugpair` erstellen
3. SideStore Settings → Anisette-Server: `https://anisette.deine-domain.tld`
4. GitHub Actions für `ios-build.yml` enabled → `.ipa` aus Releases laden
5. SideStore → Install

### 11. Cron für Auto-Playlists

```bash
crontab -e
# Add line:
0 4 * * * docker exec rolify-scraper python -m scripts.refresh_dynamic_playlists >> /var/log/rolify-cron.log 2>&1
```

---

## Backup-Strategie (Production)

Tägliches Postgres-Backup auf S3 / Backblaze:

```bash
# In crontab
0 3 * * * docker exec rolify-postgres pg_dump -U postgres rolify | gzip > /backup/rolify-$(date +\%Y\%m\%d).sql.gz
0 5 * * * find /backup -mtime +30 -delete
# Optional: rsync nach S3 / Backblaze B2
```

MinIO-Daten sind ~5-10 GB pro 1000 Tracks — separat snapshotten oder MinIO-Bucket-Replication aktivieren.

---

## Update-Workflow

Wenn neue Version released:

```bash
ssh pi@<pi-ip>
cd ~/rolify
git fetch && git reset --hard origin/main
cd infra
docker compose up -d --build backend scraper
docker exec rolify-backend npx prisma migrate deploy
```

iOS: GitHub-Releases → neueste `.ipa` → in SideStore drüber installieren.

---

## Monitoring (empfohlen)

- **Uptime:** https://uptimerobot.com (gratis 5 monitors) auf `/health`-Endpoint
- **Errors:** Sentry self-hosted (https://github.com/getsentry/self-hosted) oder Sentry-Cloud Free-Tier
- **Disk:** `docker exec rolify-postgres df -h` regelmäßig

---

## Häufige Probleme

| Problem | Lösung |
|---------|--------|
| 401 in App | Logout im Profil → Re-Login (Sessions widerrufen) |
| Auto-Playlists leer | `LASTFM_API_KEY` in `.env` korrekt? Cron lief? `docker exec rolify-scraper python -m scripts.refresh_dynamic_playlists` |
| Age-gated YT-Videos failen | YouTube-Cookies nicht hinterlegt (Schritt 6) |
| Caddy 502 | Container down? `docker compose ps` |
| MinIO 403 bei Stream | `MINIO_PUBLIC_ENDPOINT` zeigt auf falsche Domain |
| SideStore Refresh failed | Anisette-Server nicht erreichbar — VPN check |

---

## Lizenz

Personal use only. NICHT FÜR KOMMERZIELLE NUTZUNG.
Code is MIT-licensed, aber das **Scraping von Drittanbieter-Audio ist potentiell illegal**.
Keine Gewährleistung. Du verwendest auf eigenes Risiko.

## Beitragen

Pull-Requests willkommen für:
- Bugfixes
- Code-Refactoring
- Neue Features (Lyrics-Translation, Apple Watch App, etc.)
- Android-Port (Compose)

Nicht-erwünscht:
- "Wie kann ich es verkaufen" Issues — siehe Lizenz oben
- Distribution von gescrapten Tracks
