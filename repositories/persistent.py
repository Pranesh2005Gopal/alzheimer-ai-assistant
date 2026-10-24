"""Small durable JSON repositories used by the local single-patient deployment.

The application deliberately keeps the service interfaces used by the in-memory
test doubles.  This adapter persists the same records atomically after each
mutation, so a restart cannot lose conversations, memories, or reminders.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from models.domain import Appointment, ConversationTurn, ImportantDate, Person, Preference, Reminder, ReminderKind, ReminderStatus
from repositories.in_memory import RepositoryBundle, load_seed


class PersistentRepositoryBundle(RepositoryBundle):
    def __init__(self, seed_path: Path, state_path: Path) -> None:
        self._state_path = state_path
        base = load_seed(seed_path)
        if state_path.exists():
            raw = json.loads(state_path.read_text(encoding="utf-8"))
            # A state file is an overlay: seed data remains the safe first-run default.
            for row in raw.get("people", []): base.memory.add_person(Person(**row))
            for row in raw.get("preferences", []): base.memory.add_preference(Preference(**row))
            for row in raw.get("important_dates", []): base.memory.add_important_date(ImportantDate(**row))
            for row in raw.get("reminders", []):
                value = dict(row); value["kind"] = ReminderKind(value["kind"]); value["status"] = ReminderStatus(value["status"])
                base.reminders.add(Reminder(**value))
            for row in raw.get("appointments", []): base.appointments.add(Appointment(**row))
        super().__init__(base.memory, base.reminders, base.appointments, base.patient, base.activity)
        self._wrap_mutators()

    def _wrap_mutators(self) -> None:
        for repo, names in ((self.memory, ("add_person", "update_person", "delete_person", "add_important_date", "add_preference", "delete_preference")),
                            (self.reminders, ("add", "update", "delete")),
                            (self.appointments, ("add",)),
                            (self.activity, ("add",))):
            for name in names:
                original = getattr(repo, name)
                def wrapped(*args, _original=original, **kwargs):
                    result = _original(*args, **kwargs)
                    self.save()
                    return result
                setattr(repo, name, wrapped)

    def save(self) -> None:
        payload = {
            "people": [item.model_dump() for item in self.memory.list_people()],
            "preferences": [item.model_dump() for item in self.memory.list_preferences()],
            "important_dates": [item.model_dump() for item in self.memory.list_important_dates()],
            "reminders": [item.model_dump(mode="json") for item in self.reminders.list_all()],
            "appointments": [item.model_dump() for item in self.appointments.list_all()],
        }
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self._state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        os.replace(temporary, self._state_path)


class PersistentConversationHistory:
    """Bounded, append-safe conversation storage independent of personal facts."""
    def __init__(self, path: Path, max_turns: int = 50) -> None:
        self.path, self.max_turns = path, max_turns
        self._turns: list[ConversationTurn] = []
        if path.exists():
            try:
                self._turns = [ConversationTurn(**row) for row in json.loads(path.read_text(encoding="utf-8"))][-max_turns:]
            except (json.JSONDecodeError, TypeError, ValueError):
                self._turns = []

    def add(self, role: str, text: str, intent: str | None = None) -> None:
        from datetime import datetime
        # Avoid duplicate submits from a retried HTTP request.
        if self._turns and self._turns[-1].role == role and self._turns[-1].text == text:
            return
        self._turns.append(ConversationTurn(timestamp_iso=datetime.now().isoformat(timespec="seconds"), role=role, text=text, intent=intent))
        self._turns = self._turns[-self.max_turns:]
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps([turn.model_dump() for turn in self._turns], indent=2), encoding="utf-8")
        os.replace(temporary, self.path)

    def as_llm_messages(self) -> list[dict[str, str]]:
        role_map = {"patient": "user", "assistant": "assistant"}
        return [{"role": role_map.get(turn.role, turn.role), "content": turn.text} for turn in self._turns]

    def recent(self, limit: int = 50) -> list[ConversationTurn]:
        return list(self._turns[-max(0, limit):])
