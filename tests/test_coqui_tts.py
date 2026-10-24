from pathlib import Path

from ai.tts.coqui_tts import CoquiTTS
from utils.config import Settings
from utils.audio import apology_tone_wav


def test_synthesis_failure_returns_no_audio_for_spoken_fallback(monkeypatch):
    tts = CoquiTTS(Settings())

    def fail_to_load():
        raise RuntimeError("TTS engine unavailable")

    monkeypatch.setattr(tts, "load", fail_to_load)

    assert tts.speak("This is a spoken reminder.") == b""


def test_successful_synthesis_returns_playable_wav(tmp_path):
    class FakeEngine:
        def tts_to_file(self, *, text, file_path):
            assert text == "Please take your medicine."
            Path(file_path).write_bytes(apology_tone_wav())

    tts = CoquiTTS(Settings())
    tts._tts = FakeEngine()

    audio = tts.speak("Please take your medicine.")

    assert audio[:4] == b"RIFF"
    assert len(audio) > 44
