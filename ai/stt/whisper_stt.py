"""Whisper speech-to-text. This is the only STT engine in the project."""

from __future__ import annotations

from pathlib import Path

from utils.config import Settings


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
        result = self._model.transcribe(str(audio_path), fp16=False)
        text = (result.get("text") or "").strip()
        return text
