"""Text turn for tests and demos when a microphone is unavailable. Still goes through Coqui TTS."""

from __future__ import annotations

import base64

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from backend.container import get_container
from backend.auth.dependencies import ChatAccess, get_chat_access

router = APIRouter(tags=["text"])


class TextTurnRequest(BaseModel):
    text: str


@router.post("/text/turn")
def text_turn(body: TextTurnRequest, access: ChatAccess = Depends(get_chat_access)) -> dict:
    # Private chat is always owned by the authenticated account, never by a
    # caregiver-selected patient. Patient-care access remains on care routes.
    result = get_container(access.account_id, access.role).pipeline.run_text(body.text)
    return {
        "transcript": result.transcript,
        "intent": result.intent,
        "reply_text": result.reply_text,
        "status": result.status,
        "facts": result.facts,
        "audio_wav_base64": base64.b64encode(result.audio_wav).decode("ascii"),
    }
