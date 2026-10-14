from datetime import datetime

import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.api.router import api_router
from backend.container import get_container

app = FastAPI(
    title="Alzheimer Voice Assistant API",
    description="Local AI assistant for Alzheimer's patients. Flutter is the only UI client.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.get("/")
def root() -> dict:
    return {
        "ok": True,
        "name": "Alzheimer Voice Assistant API",
        "hint": "This is the backend, not the patient screen. Use Flutter for the app.",
        "health": "/health",
        "docs": "/docs",
        "overview": "/v1/patient/overview",
        "voice": "POST /v1/voice/turn",
        "text_test": "POST /v1/text/turn",
    }


@app.get("/health")
def health() -> dict:
    container = get_container()
    profile = container.repos.patient.get_profile()
    llm_status = _ollama_status(container.settings.ollama_host)
    assistant_status = "ready" if llm_status == "online" else "degraded"
    return {
        "ok": True,
        "status": assistant_status,
        "phase": 1,
        "patient": container.memory.patient_display_name() or profile.preferred_name,
        "time": datetime.now().isoformat(timespec="seconds"),
        "services": {
            "api": "online",
            "llm": llm_status,
            "stt": "configured",
            "tts": "configured",
            "nlu": "configured",
            "vision": "configured",
        },
        "stack": {
            "stt": "Whisper",
            "nlp": "spaCy",
            "intent": "DistilBERT",
            "temporal": "Duckling",
            "dialogue": "DialogueManager",
            "llm": "Llama 3 via Ollama",
            "tts": "Coqui TTS",
        },
    }


def _ollama_status(host: str) -> str:
    try:
        response = httpx.get(f"{host.rstrip('/')}/api/tags", timeout=1.5)
        if response.status_code == 200:
            return "online"
        return "unavailable"
    except Exception:
        return "unavailable"
