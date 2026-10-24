from __future__ import annotations

import base64
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile

from backend.container import get_container
from backend.auth.dependencies import PatientAccess, get_patient_access

router = APIRouter(tags=["voice"])


@router.post("/voice/turn")
async def voice_turn(audio: UploadFile = File(...), access: PatientAccess = Depends(get_patient_access)) -> dict:
    """
    Full spoken turn:
    Whisper → spaCy + DistilBERT + Duckling → Dialogue Manager → Llama 3 → Coqui TTS
    """
    suffix = Path(audio.filename or "speech.wav").suffix or ".wav"
    if suffix.lower() not in {".wav", ".pcm", ".flac", ".ogg", ".mp3", ".m4a"}:
        suffix = ".wav"
    data = await audio.read()
    container = get_container(access.patient_id)
    if not data or len(data) < 100:
        result = container.pipeline.unheard_reply()
    else:
        handle = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
        path = Path(handle.name)
        try:
            handle.write(data)
            handle.close()
            result = container.pipeline.run_audio_file(path)
        finally:
            path.unlink(missing_ok=True)
    return {
        "transcript": result.transcript,
        "intent": result.intent,
        "reply_text": result.reply_text,
        "status": result.status,
        "facts": result.facts,
        "audio_wav_base64": base64.b64encode(result.audio_wav).decode("ascii"),
    }
