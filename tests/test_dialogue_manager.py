from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from ai.dialogue.manager import DialogueManager
from ai.memory.chroma_store import NullSemanticMemory
from models.domain import ReminderKind
from models.intents import Intent
from models.nlu import NLUResult, SpacyDocumentView
from repositories.in_memory import load_seed
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.reminder_manager import ReminderManager


def _manager():
    repos = load_seed(ROOT / "data" / "seed.json")
    return (
        DialogueManager(
            reminders=ReminderManager(repos.reminders),
            appointments=AppointmentService(repos.appointments),
            memory=MemoryService(repos.memory, NullSemanticMemory()),
            emergency=EmergencyService(repos.activity),
        ),
        repos,
    )


def _nlu(text: str, intent: Intent, people: list[str] | None = None) -> NLUResult:
    mentions = people
    if mentions is None:
        mentions = ["Arun"] if "Arun" in text else []
    return NLUResult(
        raw_text=text,
        normalized_text=text,
        intent=intent,
        intent_confidence=0.9,
        spacy=SpacyDocumentView(),
        person_mentions=mentions,
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
    assert "I'll remind you" in decision.facts
    assert "medicine" in decision.facts.lower()


def test_compound_who_am_i_and_appointment_uses_real_facts():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = DialogueManager(
        reminders=ReminderManager(repos.reminders),
        appointments=AppointmentService(repos.appointments),
        memory=MemoryService(repos.memory, NullSemanticMemory()),
        emergency=EmergencyService(repos.activity),
    )
    text = "Who am I? And do I have my next appointment to the doctor?"
    decision = manager.handle(_nlu(text, Intent.UNKNOWN))
    assert "UNKNOWN" not in decision.facts
    assert "helper" in decision.facts.lower() or "Priya" in decision.facts
    assert "Kumar" in decision.facts or "appointment" in decision.facts.lower()


def test_spoken_name_is_remembered_across_later_turns():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = DialogueManager(
        reminders=ReminderManager(repos.reminders),
        appointments=AppointmentService(repos.appointments),
        memory=MemoryService(repos.memory, NullSemanticMemory()),
        emergency=EmergencyService(repos.activity),
    )
    manager.handle(_nlu("Hi, my name is Rohan", Intent.GENERAL_CONVERSATION))
    assert manager.memory.patient_display_name() == "Rohan"
    later = manager.handle(_nlu("What is my name?", Intent.ASK_PERSON_IDENTITY))
    assert "Rohan" in later.facts


def test_family_question_uses_stored_people():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = DialogueManager(
        reminders=ReminderManager(repos.reminders),
        appointments=AppointmentService(repos.appointments),
        memory=MemoryService(repos.memory, NullSemanticMemory()),
        emergency=EmergencyService(repos.activity),
    )
    decision = manager.handle(_nlu("Who are my family members?", Intent.UNKNOWN))
    assert "Arun" in decision.facts
    assert "Priya" in decision.facts
    assert "Conversation so far" not in decision.facts
    doctor = manager.handle(_nlu("Who is my doctor?", Intent.UNKNOWN))
    assert "Kumar" in doctor.facts or "doctor" in doctor.facts.lower()
    assert "appointment" not in doctor.facts.lower()


def test_i_am_tired_is_not_stored_as_a_name():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = DialogueManager(
        reminders=ReminderManager(repos.reminders),
        appointments=AppointmentService(repos.appointments),
        memory=MemoryService(repos.memory, NullSemanticMemory()),
        emergency=EmergencyService(repos.activity),
    )
    manager.handle(_nlu("I am tired", Intent.GENERAL_CONVERSATION))
    assert manager.memory.patient_display_name() is None


def test_who_is_person_uses_memory_relationship():
    manager, _repos = _manager()
    raju = manager.handle(_nlu("Who is Raju?", Intent.GENERAL_CONVERSATION, people=["Raju"]))
    assert raju.facts == "Raju is your son."
    ram = manager.handle(_nlu("Who is Ram?", Intent.ASK_MEMORY, people=[]))
    assert ram.facts == "Ram is your brother."
    unknown = manager.handle(_nlu("Who is Lakshmi?", Intent.ASK_PERSON_IDENTITY, people=["Lakshmi"]))
    assert unknown.facts == "I don't have information about who Lakshmi is."


def test_reminder_ack_and_snooze_use_existing_reminder():
    manager, _repos = _manager()
    created = manager.handle(_nlu("Remind me to take my medicine at 8 PM", Intent.CREATE_REMINDER))
    assert created.facts == "Okay, I'll remind you to take your medicine at 8 PM."
    reminder = [item for item in manager.reminders.repo.list_all() if "medicine" in item.title.lower()][-1]
    assert reminder.kind == ReminderKind.MEDICATION
    manager.note_reminder_alert(reminder.id)
    snooze = manager.handle(_nlu("Remind me again in 10 minutes.", Intent.CREATE_REMINDER))
    assert snooze.facts == "Okay, I'll remind you again in 10 minutes."
    snoozed = manager.reminders.repo.list_all()
    matching = [item for item in snoozed if item.id == reminder.id][0]
    assert matching.status.value == "pending"
    manager.note_reminder_alert(matching.id)
    done = manager.handle(_nlu("Done.", Intent.GENERAL_CONVERSATION))
    assert done.facts == "Okay. I've marked your reminder as completed."
    assert matching.status.value == "completed"
