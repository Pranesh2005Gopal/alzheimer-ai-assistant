from pathlib import Path

from models.domain import Person, Reminder, ReminderKind
from repositories.postgres import PostgresRepositoryBundle, link_legacy_patient
from services.reminder_manager import ReminderManager


def test_legacy_link_moves_records_once_and_keeps_other_patients_isolated(tmp_path):
    url = f"sqlite+pysqlite:///{tmp_path / 'care.db'}"
    seed = Path(__file__).resolve().parent.parent / "data" / "seed.json"
    legacy = PostgresRepositoryBundle(url, "patient-1", seed)
    legacy.memory.add_person(Person(id="legacy-person", name="Legacy", relationship="friend"))
    reminder = ReminderManager(legacy.reminders).create(title="legacy reminder", time_iso="2030-01-01T09:00:00", kind=ReminderKind.GENERAL)
    other = PostgresRepositoryBundle(url, "patient-b", seed)
    other.memory.add_person(Person(id="other-person", name="Other", relationship="friend"))

    result = link_legacy_patient(legacy.factory, "patient-1", "patient-a")
    assert result["status"] == "linked"
    linked = PostgresRepositoryBundle(url, "patient-a", seed)
    assert [person.name for person in linked.memory.list_people()] == ["Legacy"]
    assert [item.id for item in linked.reminders.list_all()] == [reminder.id]
    assert [person.name for person in other.memory.list_people()] == ["Other"]
    assert link_legacy_patient(legacy.factory, "patient-1", "patient-a")["status"] == "already_linked"
