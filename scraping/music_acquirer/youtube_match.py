"""Track-zu-YouTube-Matcher.

Sucht fuer jeden Spotify-Track den besten YouTube-Match, primaer ueber
YouTube Music Topic-Channels (hoechste Audioqualitaet). Validiert ueber
Duration-Diff und Title-Similarity.
"""
from __future__ import annotations

from dataclasses import dataclass

import Levenshtein
import yt_dlp

from .spotify_meta import TrackMeta


@dataclass(slots=True)
class YouTubeMatch:
    video_id: str
    url: str
    title: str
    duration_s: int
    score: float


DURATION_TOLERANCE_S = 5
MIN_TITLE_SIMILARITY = 0.6


def match_track(meta: TrackMeta) -> YouTubeMatch | None:
    """Sucht den besten YouTube-Video-Match fuer einen Spotify-Track.

    Queries sortiert damit wir zuerst Topic-Channels (keine Age-Restriction)
    und Audio-Uploads (selten age-gated) probieren, als Last Resort Musikvideo.
    Age-gated Kandidaten werden geskippt weil yt-dlp ohne Cookies sie eh nicht
    downloaden kann.
    """
    queries = [
        f"{meta.artist} - {meta.title} topic",         # YT Music Topic-Channel (Auto-Generated, never age-gated)
        f"{meta.artist} {meta.title} audio",           # Lyrics/Audio-only uploads (selten age-gated)
        f"{meta.artist} {meta.title} lyrics",          # Lyrics-Videos (selten age-gated)
        f"{meta.artist} - {meta.title}",               # Standard (Musikvideos, oft age-gated)
    ]
    spotify_duration_s = meta.duration_ms // 1000
    best_restricted: YouTubeMatch | None = None

    for q in queries:
        candidates = _search(q, limit=5)
        for c in candidates:
            score = _score_candidate(meta, c, spotify_duration_s)
            if score <= 0.7:
                continue
            age_limit = c.get("age_limit") or 0
            match = YouTubeMatch(
                video_id=c["id"],
                url=c["webpage_url"],
                title=c["title"],
                duration_s=c.get("duration") or 0,
                score=score,
            )
            if age_limit > 0:
                # Merken als Fallback falls sonst nix gefunden wird
                if best_restricted is None or match.score > best_restricted.score:
                    best_restricted = match
                continue
            return match

    # Kein non-age-restricted Match — fallback zu age-restricted (wird wahrscheinlich
    # failen beim Download aber besser als gar kein Versuch)
    return best_restricted


def _search(query: str, limit: int = 5) -> list[dict]:
    opts = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
        "default_search": f"ytsearch{limit}",
        "skip_download": True,
    }
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(query, download=False)
        return info.get("entries", []) if info else []


def _score_candidate(meta: TrackMeta, candidate: dict, target_duration_s: int) -> float:
    cand_duration = candidate.get("duration") or 0
    duration_diff = abs(cand_duration - target_duration_s)
    if duration_diff > DURATION_TOLERANCE_S:
        return 0.0

    title = (candidate.get("title") or "").lower()
    expected = f"{meta.artist} {meta.title}".lower()
    similarity = Levenshtein.ratio(title, expected)
    if similarity < MIN_TITLE_SIMILARITY:
        return 0.0

    duration_score = 1.0 - (duration_diff / DURATION_TOLERANCE_S)
    return 0.6 * similarity + 0.4 * duration_score
