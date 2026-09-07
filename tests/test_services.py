from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from models.domain import ReminderKind
from repositories.in_memory import load_seed
from services.reminder_manager import ReminderManager
from services.memory_service import MemoryService
from ai.memory.chroma_store import NullSemanticMemory


def test_seed_people_and_appointment():
    repos = load_seed(ROOT / "data" / "seed.json")
    arun = repos.memory.get_person_by_name("Arun")
    assert arun is not None
    assert arun.relationship == "son"
    nxt = repos.appointments.next_appointment()
    assert nxt is not None
    assert "Kumar" in nxt.doctor


def test_create_medication_reminder():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = ReminderManager(repos.reminders)
    reminder = manager.create_from_utterance("Remind me to take my medicine at 8 tonight", "2026-08-31T20:00:00")
    assert reminder.kind == ReminderKind.MEDICATION
    assert reminder.time_iso.endswith("20:00:00") or "20:00" in reminder.time_iso


def test_memory_who_is_arun():
    repos = load_seed(ROOT / "data" / "seed.json")
    memory = MemoryService(repos.memory, NullSemanticMemory())
    from models.intents import Intent
    from models.nlu import NLUResult, SpacyDocumentView

    nlu = NLUResult(
        raw_text="Who is Arun?",
        normalized_text="Who is Arun?",
        intent=Intent.ASK_PERSON_IDENTITY,
        intent_confidence=0.9,
        spacy=SpacyDocumentView(),
        person_mentions=["Arun"],
    )
    answer = memory.identify(nlu)
    assert "son" in answer.lower()
