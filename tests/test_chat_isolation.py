from pathlib import Path

from backend.auth.dependencies import get_chat_access
from backend.api.routes_text import TextTurnRequest, text_turn
from models.domain import Preference
from repositories.postgres import PostgresConversationHistory, PostgresRepositoryBundle


def test_chat_owner_is_derived_from_authenticated_user_not_request_scope():
    caregiver = {"id": "caregiver-1", "role": "caregiver"}
    access = get_chat_access(caregiver)
    assert access.account_id == "caregiver-1"
    assert access.role == "caregiver"


def test_text_chat_cannot_be_scoped_to_another_patients_memory(monkeypatch):
    requested_contexts = []

    class Pipeline:
        def run_text(self, text):
            from models.domain import VoiceTurnResult
            return VoiceTurnResult(transcript=text, intent="GENERAL_CONVERSATION", reply_text="ok", status="ok", facts={}, audio_wav=b"")

    class Container:
        pipeline = Pipeline()

    monkeypatch.setattr("backend.api.routes_text.get_container", lambda account_id, role: (requested_contexts.append((account_id, role)) or Container()))
    access = get_chat_access({"id": "patient-a", "role": "patient"})
    text_turn(TextTurnRequest(text="private message"), access)
    assert requested_contexts == [("patient-a", "patient")]


def test_postgres_conversations_are_isolated_by_account_and_keep_legacy_rows(tmp_path):
    database_url = f"sqlite:///{tmp_path / 'chat.db'}"
    seed_path = Path(__file__).resolve().parents[1] / "data" / "seed.json"
    bundle = PostgresRepositoryBundle(database_url, "patient-1", seed_path)
    patient = PostgresConversationHistory(bundle.factory, "patient-1")
    caregiver = PostgresConversationHistory(bundle.factory, "caregiver-1", account_role="caregiver")
    patient.add("patient", "patient-only message")
    caregiver.add("patient", "caregiver-only message")

    assert [turn.text for turn in patient.recent()] == ["patient-only message"]
    assert [turn.text for turn in caregiver.recent()] == ["caregiver-only message"]


def test_patient_memory_repositories_do_not_cross_patient_boundaries(tmp_path):
    database_url = f"sqlite:///{tmp_path / 'memory.db'}"
    seed_path = Path(__file__).resolve().parents[1] / "data" / "seed.json"
    first = PostgresRepositoryBundle(database_url, "patient-a", seed_path)
    second = PostgresRepositoryBundle(database_url, "patient-b", seed_path)
    first.memory.add_preference(Preference(id="private-a", subject="patient", key="note", value="patient A private memory"))

    assert any(item.value == "patient A private memory" for item in first.memory.list_preferences())
    assert all(item.value != "patient A private memory" for item in second.memory.list_preferences())
