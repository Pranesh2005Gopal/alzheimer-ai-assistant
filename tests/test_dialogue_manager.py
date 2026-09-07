from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from ai.dialogue.manager import DialogueManager
from ai.memory.chroma_store import NullSemanticMemory
from models.intents import Intent
from models.nlu import NLUResult, SpacyDocumentView
from repositories.in_memory import load_seed
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.reminder_manager import ReminderManager


def _nlu(text: str, intent: Intent) -> NLUResult:
    return NLUResult(
        raw_text=text,
        normalized_text=text,
        intent=intent,
        intent_confidence=0.9,
        spacy=SpacyDocumentView(),
        person_mentions=["Arun"] if "Arun" in text else [],
    )


def test_dialogue_does_not_use_llm_to_mutate_reminders():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = DialogueManager(
        reminders=ReminderManager(repos.reminders),
        appointments=AppointmentService(repos.appointments),
        memory=MemoryService(repos.memory, NullSemanticMemory()),
        emergency=EmergencyService(repos.activity),
    )
    before = len(repos.reminders.list_all())
    decision = manager.handle(_nlu("Remind me to take my medicine at 8 tonight", Intent.CREATE_REMINDER))
    assert decision.mutated is True
    assert len(repos.reminders.list_all()) == before + 1
    assert "Reminder created" in decision.facts
