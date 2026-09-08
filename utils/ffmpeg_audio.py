"""Convert any uploaded/recorded audio into 16 kHz mono WAV for Whisper and speakers."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def to_pcm16_wav(source: Path, sample_rate: int = 16000) -> Path:
    """Write a new 16-bit PCM WAV. Whisper and Linux players both accept this format."""
    if not ffmpeg_available():
        logger.warning("ffmpeg is not on PATH; Whisper may fail on unusual recordings")
        return source
    dest = _temp_path(".pcm16.wav")
    attempts = [
        ["ffmpeg", "-y", "-i", str(source), "-ac", "1", "-ar", str(sample_rate), "-c:a", "pcm_s16le", str(dest)],
        [
            "ffmpeg",
            "-y",
            "-f",
            "s16le",
            "-ar",
            "16000",
            "-ac",
            "1",
            "-i",
            str(source),
            "-ac",
            "1",
            "-ar",
            str(sample_rate),
            "-c:a",
            "pcm_s16le",
            str(dest),
        ],
    ]
    for command in attempts:
        try:
            subprocess.run(command, check=True, capture_output=True)
            if dest.stat().st_size > 44:
                return dest
        except Exception:
            logger.debug("ffmpeg attempt failed for %s", command[:6])
    dest.unlink(missing_ok=True)
    logger.warning("ffmpeg could not convert %s", source)
    return source


def wav_bytes_pcm16(data: bytes, sample_rate: int = 22050) -> bytes:
    """Re-encode TTS bytes so Linux players can play them."""
    if not ffmpeg_available() or len(data) < 45:
        return data
    src = _temp_path(".in.wav")
    converted: Path | None = None
    try:
        src.write_bytes(data)
        converted = to_pcm16_wav(src, sample_rate=sample_rate)
        if converted == src:
            return data
        return converted.read_bytes()
    finally:
        src.unlink(missing_ok=True)
        if converted is not None and converted != src:
            converted.unlink(missing_ok=True)


def _temp_path(suffix: str) -> Path:
    fd, name = tempfile.mkstemp(suffix=suffix)
    os.close(fd)
    return Path(name)
