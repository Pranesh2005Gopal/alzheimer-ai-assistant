"""Tiny WAV helpers so the API can always return playable audio bytes."""

from __future__ import annotations

import io
import math
import struct
import wave


def numpy_pcm_to_wav(samples, sample_rate: int) -> bytes:
    import numpy as np

    audio = np.asarray(samples, dtype=np.float32)
    clipped = np.clip(audio, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm.tobytes())
    return buffer.getvalue()


def apology_tone_wav(seconds: float = 0.4, sample_rate: int = 22050) -> bytes:
    """Last-resort playable WAV if Coqui TTS cannot run. Not a substitute for speech."""
    n = int(seconds * sample_rate)
    frames = bytearray()
    for i in range(n):
        value = int(8000 * math.sin(2 * math.pi * 440 * (i / sample_rate)))
        frames.extend(struct.pack("<h", value))
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(bytes(frames))
    return buffer.getvalue()
