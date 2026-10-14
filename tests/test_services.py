from datetime import datetime
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from models.domain import ReminderKind
from repositories.in_memory import load_seed
from services.activity_service import ConversationHistory
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
    assert "medicine" in reminder.title.lower()
    spoken = manager.spoken_created(reminder)
    assert "I'll remind you to take your medicine" in spoken
    assert "8 PM" in spoken


def test_due_reminder_speaks_the_task():
    repos = load_seed(ROOT / "data" / "seed.json")
    manager = ReminderManager(repos.reminders)
    now = datetime.now().replace(second=0, microsecond=0)
    reminder = manager.create_from_utterance(
        "Remind me to take my evening medicine at 8 PM",
        now.isoformat(timespec="seconds"),
    )
    due = manager.activate_due_if_needed(now)
    assert due is not None
    assert due.id == reminder.id
    message = manager.spoken_due(due)
    assert "This is your reminder to" in message
    assert "evening medicine" in message.lower() or "medicine" in message.lower()


def test_memory_who_is_raju():
    repos = load_seed(ROOT / "data" / "seed.json")
    memory = MemoryService(repos.memory, NullSemanticMemory())
    from models.intents import Intent
    from models.nlu import NLUResult, SpacyDocumentView

    known = memory.identify(
        NLUResult(
            raw_text="Who is Raju?",
            normalized_text="Who is Raju?",
            intent=Intent.ASK_PERSON_IDENTITY,
            intent_confidence=0.9,
            spacy=SpacyDocumentView(),
            person_mentions=["Raju"],
        )
    )
    assert known == "Raju is your son."
    unknown = memory.identify(
        NLUResult(
            raw_text="Who is Lakshmi?",
            normalized_text="Who is Lakshmi?",
            intent=Intent.ASK_PERSON_IDENTITY,
            intent_confidence=0.9,
            spacy=SpacyDocumentView(),
            person_mentions=["Lakshmi"],
        )
    )
    assert unknown == "I don't have information about who Lakshmi is."


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
    assert answer == "Arun is your son."


def test_memory_who_am_i():
    repos = load_seed(ROOT / "data" / "seed.json")
    memory = MemoryService(repos.memory, NullSemanticMemory())
    from models.intents import Intent
    from models.nlu import NLUResult, SpacyDocumentView

    nlu = NLUResult(
        raw_text="Who am I?",
        normalized_text="Who am I?",
        intent=Intent.ASK_PERSON_IDENTITY,
        intent_confidence=0.4,
        spacy=SpacyDocumentView(),
        person_mentions=[],
    )
    answer = memory.identify(nlu)
    assert "helper" in answer.lower()
    assert "Your name is" in answer or "at home" in answer.lower()


def test_memory_family_roles_come_from_stored_people():
    repos = load_seed(ROOT / "data" / "seed.json")
    memory = MemoryService(repos.memory, NullSemanticMemory())
    from models.intents import Intent
    from models.nlu import NLUResult, SpacyDocumentView

    def ask(text: str) -> str:
        return memory.identify(
            NLUResult(
                raw_text=text,
                normalized_text=text,
                intent=Intent.ASK_PERSON_IDENTITY,
                intent_confidence=0.9,
                spacy=SpacyDocumentView(),
                person_mentions=[],
            )
        )

    family = ask("Who are my family members?")
    assert "Arun" in family
    assert "Priya" in family
    assert "Conversation so far" not in family
    assert "son" in ask("Who is my son?").lower()
    assert "daughter" in ask("Who is my daughter?").lower()
    assert "doctor" in ask("Who is my doctor?").lower()


def test_conversation_history_keeps_older_turns_for_the_llm():
    history = ConversationHistory(max_turns=40)
    for i in range(8):
        history.add("patient", f"fact number {i}")
        history.add("assistant", f"ok {i}")
    messages = history.as_llm_messages()
    assert len(messages) == 16
    assert messages[0]["content"] == "fact number 0"
    digest = history.as_digest()
    assert "fact number 0" in digest
    assert "fact number 7" in digest


def test_patient_facing_speech_does_not_read_history_aloud():
    from ai.llm.ollama_llama import patient_facing_speech

    leaked = "The patient's name is Rota. Conversation so far: Patient: Then is my next appointment."
    spoken = patient_facing_speech(leaked, "Your next appointment is with Dr. Kumar tomorrow at 10:00.")
    assert "Conversation so far" not in spoken
    assert "The patient's name is" not in spoken
    assert "Patient:" not in spoken
    assert "Kumar" in spoken or "here with you" in spoken.lower()


def test_whisper_reliability_uses_whisper_metrics():
    from ai.stt.whisper_stt import _from_whisper_result

    empty = _from_whisper_result({"text": "   ", "segments": []})
    assert empty.reliable is False
    noisy = _from_whisper_result(
        {"text": "mm", "segments": [{"avg_logprob": -0.2, "no_speech_prob": 0.9}]}
    )
    assert noisy.reliable is False
    good = _from_whisper_result(
        {
            "text": "Who is my daughter?",
            "segments": [{"avg_logprob": -0.3, "no_speech_prob": 0.1}],
        }
    )
    assert good.reliable is True
    assert good.text.startswith("Who is")
