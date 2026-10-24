from pathlib import Path

from ai.dialogue.manager import DialogueManager
from ai.memory.chroma_store import NullSemanticMemory
from ai.llm.ollama_llama import patient_facing_speech
from models.intents import Intent
from models.nlu import NLUResult, SpacyDocumentView
from repositories.persistent import PersistentConversationHistory, PersistentRepositoryBundle
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.reminder_manager import ReminderManager

ROOT = Path(__file__).resolve().parent.parent


def test_history_survives_restart_and_is_bounded(tmp_path):
    path = tmp_path / "conversations.json"
    history = PersistentConversationHistory(path, max_turns=3)
    for index in range(5):
        history.add("patient", f"message {index}")
    restored = PersistentConversationHistory(path, max_turns=3)
    assert [turn.text for turn in restored.recent()] == ["message 2", "message 3", "message 4"]


def test_reminder_survives_restart(tmp_path):
    state = tmp_path / "state.json"
    repos = PersistentRepositoryBundle(ROOT / "data" / "seed.json", state)
    created = ReminderManager(repos.reminders).create(title="meeting", time_iso="2030-01-01T11:10:00")
    restored = PersistentRepositoryBundle(ROOT / "data" / "seed.json", state)
    assert any(item.id == created.id and item.title == "meeting" for item in restored.reminders.list_all())


def test_unknown_identity_is_honest(tmp_path):
    repos = PersistentRepositoryBundle(ROOT / "data" / "seed.json", tmp_path / "state.json")
    answer = MemoryService(repos.memory, NullSemanticMemory()).spoken_self()
    assert "name saved" in answer
    assert "home" not in answer.lower()


def test_llm_failure_is_not_generic_unrelated_fallback():
    assert "language service is unavailable" in patient_facing_speech("", "").lower()


def test_greeting_is_deterministic_and_relevant(tmp_path):
    repos = PersistentRepositoryBundle(ROOT / "data" / "seed.json", tmp_path / "state.json")
    manager = DialogueManager(ReminderManager(repos.reminders), AppointmentService(repos.appointments), MemoryService(repos.memory, NullSemanticMemory()), EmergencyService(repos.activity))
    nlu = NLUResult(raw_text="Hello, nice to meet you.", normalized_text="Hello, nice to meet you.", intent=Intent.GENERAL_CONVERSATION, intent_confidence=1, spacy=SpacyDocumentView())
    assert "lovely to meet you" in manager.handle(nlu).facts.lower()
