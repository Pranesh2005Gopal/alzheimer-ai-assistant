"""Coqui TTS. Every patient-facing reply is synthesized here."""

from __future__ import annotations

import logging
import re
import tempfile
from pathlib import Path

from utils.audio import apology_tone_wav, numpy_pcm_to_wav
from utils.config import Settings
from utils.ffmpeg_audio import wav_bytes_pcm16

logger = logging.getLogger(__name__)


class CoquiTTS:
    def __init__(self, settings: Settings) -> None:
        self._model_name = settings.coqui_model
        self._tts = None
        self._sample_rate = 22050

    def load(self) -> None:
        if self._tts is not None:
            return
        from TTS.api import TTS

        self._tts = TTS(self._model_name)
        if getattr(self._tts, "synthesizer", None) is not None:
            output_sr = getattr(self._tts.synthesizer, "output_sample_rate", None)
            if output_sr:
                self._sample_rate = int(output_sr)

    def speak(self, text: str) -> bytes:
        spoken = _for_speech(text)
        try:
            self.load()
            assert self._tts is not None
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as handle:
                path = Path(handle.name)
            try:
                self._tts.tts_to_file(text=spoken, file_path=str(path))
                data = path.read_bytes()
                if len(data) > 44:
                    return wav_bytes_pcm16(data, sample_rate=self._sample_rate)
            finally:
                path.unlink(missing_ok=True)
            wav = self._tts.tts(text=spoken)
            return wav_bytes_pcm16(numpy_pcm_to_wav(wav, self._sample_rate), sample_rate=self._sample_rate)
        except Exception:
            logger.exception("Coqui TTS failed")
            return wav_bytes_pcm16(apology_tone_wav(), sample_rate=22050)


def _for_speech(text: str) -> str:
    cleaned = re.sub(r"[*_`#]+", "", text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if len(cleaned) > 400:
        cleaned = cleaned[:400].rsplit(" ", 1)[0]
    return cleaned or "I am here with you."
