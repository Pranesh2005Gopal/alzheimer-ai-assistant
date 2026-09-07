"""Llama 3 via Ollama. Generates wording only — never mutates patient data."""

from __future__ import annotations

import logging

import httpx

from utils.config import Settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a calm, patient voice assistant for a person living with Alzheimer's disease.
Speak in short, simple sentences. Be warm. Never diagnose medical conditions.
Never invent medications, appointments, people, or times.
If structured facts are provided, use only those facts.
Do not tell the user to look at the screen. This conversation is spoken.
"""


class OllamaLlama:
    def __init__(self, settings: Settings) -> None:
        self._host = settings.ollama_host.rstrip("/")
        self._model = settings.ollama_model

    def generate(self, user_text: str, facts: str, conversation: list[dict[str, str]]) -> str:
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]
        if facts.strip():
            messages.append(
                {
                    "role": "system",
                    "content": "Structured facts from the application (do not contradict these):\n" + facts,
                }
            )
        messages.extend(conversation[-6:])
        messages.append({"role": "user", "content": user_text})
        try:
            response = httpx.post(
                f"{self._host}/api/chat",
                json={"model": self._model, "messages": messages, "stream": False},
                timeout=120.0,
            )
            response.raise_for_status()
            content = response.json()["message"]["content"].strip()
            return content or "I am here with you."
        except Exception as exc:
            logger.warning("Ollama/Llama 3 failed: %s", exc)
            if facts.strip():
                return facts.split("\n")[0]
            return "I am having a little trouble thinking right now. Please say that again."
