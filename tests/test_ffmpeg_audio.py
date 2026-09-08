from pathlib import Path

from utils.audio import apology_tone_wav
from utils.ffmpeg_audio import ffmpeg_available, to_pcm16_wav, wav_bytes_pcm16


def test_pcm16_roundtrip(tmp_path: Path):
    if not ffmpeg_available():
        return
    src = tmp_path / "tone.wav"
    src.write_bytes(apology_tone_wav(seconds=0.3))
    converted = to_pcm16_wav(src, sample_rate=16000)
    assert converted.stat().st_size > 44
    assert converted.read_bytes()[:4] == b"RIFF"
    out = wav_bytes_pcm16(src.read_bytes(), sample_rate=22050)
    assert out[:4] == b"RIFF"
