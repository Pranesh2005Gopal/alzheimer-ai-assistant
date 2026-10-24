"""Live patient-context tests using records created through supported stores/services."""
from pathlib import Path
from uuid import uuid4

import pytest

from ai.dialogue.manager import DialogueManager
from ai.memory.chroma_store import NullSemanticMemory
from models.intents import Intent
from models.nlu import NLUResult, SpacyDocumentView
from repositories.in_memory import load_seed
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.patient_context import PatientContextService
from services.reminder_manager import ReminderManager

ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture
def patient_store(monkeypatch, tmp_path):
    import backend.auth.store as store
    monkeypatch.setattr(store, "_STORE_PATH", tmp_path / "users.json")
    monkeypatch.setattr(store, "_SESSIONS_PATH", tmp_path / "sessions.json")
    monkeypatch.setattr(store, "_SESSIONS", {})
    return store


def test_profile_edits_are_live_and_replace_deleted_values(patient_store):
    unique = uuid4().hex
    patient = patient_store.create_user(f"{unique}@example.test", "safe-password", full_name=f"Full {unique}")
    patient_store.update_profile(patient["id"], {"preferred_name": f"First {unique}", "hobbies": [f"hobby-{unique}"]})
    context = PatientContextService(patient["id"], load_seed(ROOT / "data" / "seed.json"))
    assert f"hobby-{unique}" in context.answer("What are my hobbies?").text
    assert f"First {unique}" in context.answer("What should you call me?").text

    # Same persistence operation used by PATCH /v1/profile.
    patient_store.update_profile(patient["id"], {"preferred_name": f"Second {unique}", "hobbies": [f"updated-{unique}"]})
    assert f"updated-{unique}" in context.answer("What are my hobbies?").text
    assert f"hobby-{unique}" not in context.answer("What are my hobbies?").text
    assert f"Second {unique}" in context.answer("What should you call me?").text

    patient_store.update_profile(patient["id"], {"hobbies": []})
    assert "not have hobbies or interests saved" in context.answer("What are my hobbies?").text


def test_profile_memories_and_repository_notes_are_retrieved_live(patient_store):
    unique = uuid4().hex
    patient = patient_store.create_user(f"{unique}@example.test", "safe-password")
    patient_store.update_profile(patient["id"], {"personal_memories": [f"memory-{unique}"]})
    repos = load_seed(ROOT / "data" / "seed.json")
    memory = MemoryService(repos.memory, NullSemanticMemory())
    memory.store_from_utterance(f"note-{unique}")
    reply = PatientContextService(patient["id"], repos).answer("What do you remember about me?").text
    assert f"memory-{unique}" in reply and f"note-{unique}" in reply


def test_patient_context_isolation_and_dialogue_verbatim(patient_store):
    first = patient_store.create_user(f"{uuid4().hex}@example.test", "safe-password")
    second = patient_store.create_user(f"{uuid4().hex}@example.test", "safe-password")
    first_hobby, second_hobby = f"hobby-{uuid4().hex}", f"hobby-{uuid4().hex}"
    patient_store.update_profile(first["id"], {"hobbies": [first_hobby]})
    patient_store.update_profile(second["id"], {"hobbies": [second_hobby]})
    repos = load_seed(ROOT / "data" / "seed.json")
    context = PatientContextService(first["id"], repos)
    assert first_hobby in context.answer("What are my hobbies?").text
    assert second_hobby not in context.answer("What are my hobbies?").text
    manager = DialogueManager(ReminderManager(repos.reminders), AppointmentService(repos.appointments), MemoryService(repos.memory, NullSemanticMemory()), EmergencyService(repos.activity), patient_context=context)
    nlu = NLUResult(raw_text="What are my hobbies?", normalized_text="What are my hobbies?", intent=Intent.GENERAL_CONVERSATION, intent_confidence=.4, spacy=SpacyDocumentView())
    decision = manager.handle(nlu)
    assert decision.extras["verbatim"] and first_hobby in decision.facts
