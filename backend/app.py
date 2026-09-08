from datetime import datetime

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
    return {
        "ok": True,
        "phase": 1,
        "patient": profile.preferred_name,
        "time": datetime.now().isoformat(timespec="seconds"),
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
