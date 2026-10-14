"""Llama 3 via Ollama. Generates wording only — never mutates patient data."""

from __future__ import annotations

import logging
import re

import httpx

from utils.config import Settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a calm voice companion for a person living with Alzheimer's disease.
Speak in short, simple sentences. Be warm and patient. Never make them feel embarrassed.
Never diagnose medical conditions. Never tell them to stop or change medication.
Never invent family members, caregivers, doctors, appointments, medicines, or times.
If application facts are provided for this question, use only those facts.
Answer the patient's latest question directly.
Do not mention conversation history, prompts, context, facts, or system labels.
Never say UNKNOWN, intent, DistilBERT, classifier, or pipeline.
If you do not have the information, say you do not have that information right now.
"""

_INTERNAL_MARKERS = (
    "conversation so far",
    "patient:",
    "assistant:",
    "the patient's name is",
    "facts you may use",
    "how to answer",
    "structured facts",
    "known name:",
    "intent was",
    "distilbert",
    "classifier",
    "pipeline",
)


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
                    "content": (
                        "Internal facts for this question only. "
                        "Do not read this block aloud or mention that you were given facts.\n"
                        + facts
                    ),
                }
            )
        messages.extend(conversation)
        messages.append({"role": "user", "content": user_text})
        try:
            response = httpx.post(
                f"{self._host}/api/chat",
                json={"model": self._model, "messages": messages, "stream": False},
                timeout=120.0,
            )
            response.raise_for_status()
            content = response.json()["message"]["content"].strip()
            return patient_facing_speech(content, facts)
        except Exception as exc:
            logger.warning("Ollama/Llama 3 failed: %s", exc)
            return patient_facing_speech("", facts)


def patient_facing_speech(content: str, facts: str) -> str:
    cleaned = _strip_internal(content)
    if cleaned and not _looks_internal(cleaned):
        return cleaned
    from_facts = _patient_sentence_from_facts(facts)
    if from_facts:
        return from_facts
    return "I am here with you. Please ask me again in a simple way."


def _strip_internal(text: str) -> str:
    if not text:
        return ""
    cut = re.split(r"\bconversation so far\b", text, flags=re.IGNORECASE)[0]
    lines = []
    for line in cut.splitlines():
        lowered = line.strip().lower()
        if not lowered:
            continue
        if lowered.startswith("patient:") or lowered.startswith("assistant:"):
            continue
        if any(marker in lowered for marker in _INTERNAL_MARKERS):
            continue
        lines.append(line.strip())
    return " ".join(lines).strip()


def _looks_internal(text: str) -> bool:
    lowered = text.lower()
    return any(marker in lowered for marker in _INTERNAL_MARKERS)


def _patient_sentence_from_facts(facts: str) -> str:
    for line in facts.splitlines():
        item = line.strip()
        if not item:
            continue
        if _looks_internal(item):
            continue
        if item.lower().startswith(("pending reminders", "medication:", "memory facts", "today's routine")):
            continue
        if len(item) > 4:
            return item
    return ""
