"""Whisper speech-to-text. This is the only STT engine in the project."""

from __future__ import annotations

import logging
from pathlib import Path

from utils.config import Settings
from utils.ffmpeg_audio import to_pcm16_wav

logger = logging.getLogger(__name__)


class WhisperSTT:
    def __init__(self, settings: Settings) -> None:
        self._model_name = settings.whisper_model
        self._model = None

    def load(self) -> None:
        if self._model is not None:
            return
        import whisper

        self._model = whisper.load_model(self._model_name)

    def transcribe_file(self, audio_path: Path) -> str:
        self.load()
        assert self._model is not None
        if not audio_path.exists() or audio_path.stat().st_size < 1000:
            logger.warning("Audio file missing or too small: %s", audio_path)
            return ""
        wav_path = to_pcm16_wav(audio_path, sample_rate=16000)
        try:
            logger.info("Transcribing %s (%s bytes)", wav_path, wav_path.stat().st_size)
            result = self._model.transcribe(
                str(wav_path),
                fp16=False,
                language="en",
                condition_on_previous_text=False,
            )
            return (result.get("text") or "").strip()
        finally:
            if wav_path != audio_path:
                wav_path.unlink(missing_ok=True)
