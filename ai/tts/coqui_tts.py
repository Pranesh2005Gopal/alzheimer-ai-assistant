"""Coqui TTS. Every patient-facing reply is synthesized here."""

from __future__ import annotations

import logging
import tempfile
from pathlib import Path

from utils.audio import apology_tone_wav, numpy_pcm_to_wav
from utils.config import Settings

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
        spoken = text.strip() or "I am here."
        try:
            self.load()
            assert self._tts is not None
            wav = self._tts.tts(text=spoken)
            return numpy_pcm_to_wav(wav, self._sample_rate)
        except Exception as exc:
            logger.exception("Coqui TTS failed, writing file fallback: %s", exc)
            try:
                self.load()
                assert self._tts is not None
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as handle:
                    path = Path(handle.name)
                    self._tts.tts_to_file(text=spoken, file_path=str(path))
                    return path.read_bytes()
            except Exception:
                logger.exception("Coqui TTS file fallback also failed")
                return apology_tone_wav()
