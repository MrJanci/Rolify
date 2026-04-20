"""AES-256-GCM Verschluesselung der Audio-Files.

Layout der .enc Datei:
    [12 bytes IV][ciphertext][16 bytes GCM tag]

Key-Handling:
- Pro Track ein zufaelliger 32-Byte Master-Key.
- Master-Key wird von Pipeline in Postgres `Track.masterKey` gespeichert.
- IV ist pro Datei zufaellig (nicht wiederverwenden!).
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


@dataclass(slots=True)
class EncryptedTrack:
    enc_path: Path
    master_key: bytes   # 32 bytes
    iv: bytes           # 12 bytes
    size_bytes: int


def encrypt_file(plaintext_path: Path, track_id: str) -> EncryptedTrack:
    master_key = AESGCM.generate_key(bit_length=256)
    iv = os.urandom(12)
    aesgcm = AESGCM(master_key)

    plaintext = plaintext_path.read_bytes()
    # Kein associated_data — Datei-Integritaet reicht fuer unseren Threat-Model
    ciphertext = aesgcm.encrypt(iv, plaintext, associated_data=None)

    enc_path = plaintext_path.parent / f"{track_id}.enc"
    # ciphertext von AESGCM.encrypt enthaelt bereits das 16-Byte-Tag am Ende
    enc_path.write_bytes(iv + ciphertext)

    plaintext_path.unlink(missing_ok=True)

    return EncryptedTrack(
        enc_path=enc_path,
        master_key=master_key,
        iv=iv,
        size_bytes=enc_path.stat().st_size,
    )
