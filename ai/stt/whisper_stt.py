"""Whisper speech-to-text. This is the only STT engine in the project."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from pathlib import Path

from utils.config import Settings
from utils.ffmpeg_audio import to_pcm16_wav

logger = logging.getLogger(__name__)

# Whisper's own metrics (not an invented scale):
# avg_logprob is typically near 0 when confident and more negative when unsure.
# no_speech_prob is 0–1 from Whisper's no-speech detector.
_MIN_AVG_LOGPROB = -1.0
_MAX_NO_SPEECH_PROB = 0.55
_MIN_LETTERS = 2


@dataclass
class TranscriptResult:
    text: str
    reliable: bool
    avg_logprob: float
    no_speech_prob: float


class WhisperSTT:
    def __init__(self, settings: Settings) -> None:
        self._model_name = settings.whisper_model
        self._model = None

    def load(self) -> None:
        if self._model is not None:
            return
        import whisper

        self._model = whisper.load_model(self._model_name)

    def transcribe_file(self, audio_path: Path, vocabulary_hints: list[str] | None = None) -> TranscriptResult:
        empty = TranscriptResult("", False, -99.0, 1.0)
        self.load()
        assert self._model is not None
        if not audio_path.exists() or audio_path.stat().st_size < 44:
            logger.warning("Audio file missing or too small: %s", audio_path)
            return empty
        wav_path = to_pcm16_wav(audio_path, sample_rate=16000)
        try:
            logger.info("Transcribing %s (%s bytes)", wav_path, wav_path.stat().st_size)
            result = self._decode(wav_path, no_speech_threshold=0.45, vocabulary_hints=vocabulary_hints)
            if not result.text:
                result = self._decode(wav_path, no_speech_threshold=0.30, vocabulary_hints=vocabulary_hints)
            logger.info(
                "Whisper transcript=%r reliable=%s logprob=%.3f no_speech=%.3f",
                result.text,
                result.reliable,
                result.avg_logprob,
                result.no_speech_prob,
            )
            return result
        except Exception:
            logger.exception("Whisper transcription failed")
            return empty
        finally:
            if wav_path != audio_path:
                wav_path.unlink(missing_ok=True)

    def _decode(
        self,
        wav_path: Path,
        no_speech_threshold: float,
        vocabulary_hints: list[str] | None,
    ) -> TranscriptResult:
        assert self._model is not None
        options = dict(
            fp16=False,
            language="en",
            task="transcribe",
            condition_on_previous_text=False,
            temperature=0.0,
            no_speech_threshold=no_speech_threshold,
            logprob_threshold=_MIN_AVG_LOGPROB,
            compression_ratio_threshold=2.4,
        )
        prompt = _initial_prompt(vocabulary_hints)
        if prompt:
            options["initial_prompt"] = prompt
        try:
            raw = self._model.transcribe(str(wav_path), without_timestamps=True, **options)
        except TypeError:
            raw = self._model.transcribe(str(wav_path), **options)
        return _from_whisper_result(raw)


def _initial_prompt(hints: list[str] | None) -> str:
    if not hints:
        return ""
    cleaned: list[str] = []
    seen: set[str] = set()
    for hint in hints:
        token = " ".join(str(hint).split())
        key = token.lower()
        if len(token) < 2 or key in seen:
            continue
        seen.add(key)
        cleaned.append(token)
        if len(cleaned) >= 16:
            break
    if not cleaned:
        return ""
    return "English speech. Words that may appear: " + ", ".join(cleaned) + "."


def _from_whisper_result(raw: dict) -> TranscriptResult:
    text = re.sub(r"\s+", " ", (raw.get("text") or "")).strip()
    text = text.strip(" .,-")
    segments = raw.get("segments") or []
    logprobs = [float(seg.get("avg_logprob", -99.0)) for seg in segments]
    no_speech = [float(seg.get("no_speech_prob", 1.0)) for seg in segments]
    avg_logprob = sum(logprobs) / len(logprobs) if logprobs else -99.0
    no_speech_prob = max(no_speech) if no_speech else 1.0
    letters = sum(1 for ch in text if ch.isalpha())
    reliable = bool(text) and letters >= _MIN_LETTERS
    if segments:
        if avg_logprob < _MIN_AVG_LOGPROB:
            reliable = False
        if no_speech_prob > _MAX_NO_SPEECH_PROB and letters < 12:
            reliable = False
    elif not text:
        reliable = False
    return TranscriptResult(text=text, reliable=reliable, avg_logprob=avg_logprob, no_speech_prob=no_speech_prob)
