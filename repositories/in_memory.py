"""In-memory mock implementations. Not referenced by name in business logic — only via interfaces."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import uuid4

from models.domain import (
    ActivityEvent,
    Appointment,
    ImportantDate,
    PatientProfile,
    Person,
    Preference,
    Reminder,
    ReminderKind,
    ReminderStatus,
)


def _new_id() -> str:
    return uuid4().hex[:12]


class InMemoryMemoryRepository:
    def __init__(self) -> None:
        self._people: dict[str, Person] = {}
        self._dates: dict[str, ImportantDate] = {}
        self._prefs: dict[str, Preference] = {}

    def list_people(self) -> list[Person]:
        return list(self._people.values())

    def get_person_by_name(self, name: str) -> Optional[Person]:
        needle = name.strip().lower().replace("dr.", "").strip()
        for person in self._people.values():
            hay = person.name.lower()
            if hay == needle or needle in hay or hay in needle:
                return person
        return None

    def add_person(self, person: Person) -> Person:
        self._people[person.id] = person
        return person

    def list_important_dates(self) -> list[ImportantDate]:
        return list(self._dates.values())

    def add_important_date(self, item: ImportantDate) -> ImportantDate:
        self._dates[item.id] = item
        return item

    def list_preferences(self, subject: Optional[str] = None) -> list[Preference]:
        values = list(self._prefs.values())
        if subject is None:
            return values
        needle = subject.lower()
        return [p for p in values if p.subject.lower() == needle]

    def add_preference(self, item: Preference) -> Preference:
        self._prefs[item.id] = item
        return item

    def search_facts(self, query: str) -> list[str]:
        """Keyword fallback used until Chroma RAG is wired in Phase 3."""
        q = query.lower()
        facts: list[str] = []
        for person in self._people.values():
            blob = f"{person.name} {person.relationship} {person.notes}".lower()
            if any(token in blob for token in q.split()):
                facts.append(f"{person.name} is your {person.relationship}. {person.notes}".strip())
        for pref in self._prefs.values():
            blob = f"{pref.subject} {pref.key} {pref.value}".lower()
            if any(token in blob for token in q.split()):
                facts.append(f"{pref.subject} {pref.key}: {pref.value}")
        for item in self._dates.values():
            blob = f"{item.title} {item.kind} {item.notes}".lower()
            if any(token in blob for token in q.split()):
                facts.append(f"{item.title} on {item.date_iso} ({item.kind})")
        return facts[:8]


class InMemoryReminderRepository:
    def __init__(self) -> None:
        self._items: dict[str, Reminder] = {}

    def list_all(self) -> list[Reminder]:
        return list(self._items.values())

    def add(self, reminder: Reminder) -> Reminder:
        self._items[reminder.id] = reminder
        return reminder

    def delete(self, reminder_id: str) -> bool:
        return self._items.pop(reminder_id, None) is not None

    def update(self, reminder: Reminder) -> Reminder:
        self._items[reminder.id] = reminder
        return reminder

    def upcoming(self, limit: int = 5) -> list[Reminder]:
        pending = [r for r in self._items.values() if r.status == ReminderStatus.PENDING]
        pending.sort(key=lambda r: r.time_iso)
        return pending[:limit]


class InMemoryAppointmentRepository:
    def __init__(self) -> None:
        self._items: dict[str, Appointment] = {}

    def list_all(self) -> list[Appointment]:
        return list(self._items.values())

    def add(self, appointment: Appointment) -> Appointment:
        self._items[appointment.id] = appointment
        return appointment

    def next_appointment(self) -> Optional[Appointment]:
        items = sorted(self._items.values(), key=lambda a: (a.date_iso, a.time_iso))
        return items[0] if items else None


class InMemoryPatientRepository:
    def __init__(self, profile: PatientProfile) -> None:
        self._profile = profile

    def get_profile(self) -> PatientProfile:
        return self._profile


class InMemoryActivityRepository:
    def __init__(self) -> None:
        self._events: list[ActivityEvent] = []

    def add(self, event: ActivityEvent) -> ActivityEvent:
        self._events.append(event)
        return event

    def recent(self, limit: int = 50) -> list[ActivityEvent]:
        return list(reversed(self._events[-limit:]))


class RepositoryBundle:
    def __init__(
        self,
        memory: InMemoryMemoryRepository,
        reminders: InMemoryReminderRepository,
        appointments: InMemoryAppointmentRepository,
        patient: InMemoryPatientRepository,
        activity: InMemoryActivityRepository,
    ) -> None:
        self.memory = memory
        self.reminders = reminders
        self.appointments = appointments
        self.patient = patient
        self.activity = activity


def load_seed(path: Path) -> RepositoryBundle:
    raw = json.loads(path.read_text(encoding="utf-8"))
    memory = InMemoryMemoryRepository()
    reminders = InMemoryReminderRepository()
    appointments = InMemoryAppointmentRepository()
    activity = InMemoryActivityRepository()

    for row in raw.get("people", []):
        memory.add_person(Person(**row))
    for row in raw.get("important_dates", []):
        memory.add_important_date(ImportantDate(**row))
    for row in raw.get("preferences", []):
        memory.add_preference(Preference(**row))
    for row in raw.get("reminders", []):
        row = dict(row)
        row["kind"] = ReminderKind(row["kind"])
        row["status"] = ReminderStatus(row["status"])
        reminders.add(Reminder(**row))
    for row in raw.get("appointments", []):
        appointments.add(Appointment(**row))

    profile = PatientProfile(**raw["patient"])
    patient = InMemoryPatientRepository(profile)

    activity.add(
        ActivityEvent(
            id=_new_id(),
            timestamp_iso=datetime.now().isoformat(timespec="seconds"),
            kind="system",
            summary="Seed data loaded into in-memory repositories",
        )
    )
    return RepositoryBundle(memory, reminders, appointments, patient, activity)
