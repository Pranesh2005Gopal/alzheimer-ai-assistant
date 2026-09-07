from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from models.domain import ActivityEvent, ConversationTurn
from repositories.in_memory import InMemoryActivityRepository


class ConversationHistory:
    """Short-lived turns. Not the same as long-term MemoryRepository / Chroma."""

    def __init__(self, max_turns: int = 12) -> None:
        self.max_turns = max_turns
        self._turns: list[ConversationTurn] = []

    def add(self, role: str, text: str, intent: str | None = None) -> None:
        self._turns.append(
            ConversationTurn(
                timestamp_iso=datetime.now().isoformat(timespec="seconds"),
                role=role,
                text=text,
                intent=intent,
            )
        )
        self._turns = self._turns[-self.max_turns :]

    def as_llm_messages(self) -> list[dict[str, str]]:
        role_map = {"patient": "user", "assistant": "assistant"}
        return [{"role": role_map.get(t.role, t.role), "content": t.text} for t in self._turns]


class ActivityLogger:
    def __init__(self, repo: InMemoryActivityRepository) -> None:
        self.repo = repo

    def log(self, kind: str, summary: str, metadata: dict | None = None) -> ActivityEvent:
        event = ActivityEvent(
            id=uuid4().hex[:12],
            timestamp_iso=datetime.now().isoformat(timespec="seconds"),
            kind=kind,
            summary=summary,
            metadata=metadata or {},
        )
        return self.repo.add(event)
