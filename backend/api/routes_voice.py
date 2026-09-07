from __future__ import annotations

import base64
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile

from backend.container import get_container

router = APIRouter(tags=["voice"])


@router.post("/voice/turn")
async def voice_turn(audio: UploadFile = File(...)) -> dict:
    """
    Full spoken turn:
    Whisper → spaCy + DistilBERT + Duckling → Dialogue Manager → Llama 3 → Coqui TTS
    """
    suffix = Path(audio.filename or "speech.wav").suffix or ".wav"
    data = await audio.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty audio upload")
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=True) as handle:
        handle.write(data)
        handle.flush()
        result = get_container().pipeline.run_audio_file(Path(handle.name))
    return {
        "transcript": result.transcript,
        "intent": result.intent,
        "reply_text": result.reply_text,
        "status": result.status,
        "facts": result.facts,
        "audio_wav_base64": base64.b64encode(result.audio_wav).decode("ascii"),
    }
