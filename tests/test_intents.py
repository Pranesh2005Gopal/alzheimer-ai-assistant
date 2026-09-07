from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from models.intents import INTENT_LABELS, Intent


def test_intent_enum_matches_spec():
    expected = {
        "CREATE_REMINDER",
        "DELETE_REMINDER",
        "CHECK_REMINDER",
        "CHECK_MEDICATION",
        "CHECK_APPOINTMENT",
        "CREATE_APPOINTMENT",
        "ASK_PERSON_IDENTITY",
        "ASK_MEMORY",
        "STORE_MEMORY",
        "ASK_DAILY_ROUTINE",
        "CHECK_TIME",
        "CHECK_DATE",
        "MAKE_CALL",
        "EMERGENCY",
        "GENERAL_CONVERSATION",
        "UNKNOWN",
    }
    assert set(INTENT_LABELS) == expected
    assert Intent.EMERGENCY.value == "EMERGENCY"


def test_training_examples_cover_every_intent():
    payload = json.loads((ROOT / "data" / "intent_examples.json").read_text(encoding="utf-8"))
    assert set(payload) == set(INTENT_LABELS)
    for label, rows in payload.items():
        assert len(rows) >= 8, label
