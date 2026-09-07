from __future__ import annotations

from uuid import uuid4

from models.domain import Reminder, ReminderKind, ReminderStatus, RoutineActivity
from repositories.in_memory import InMemoryReminderRepository


class ReminderManager:
    """Deterministic reminder mutations. Llama 3 does not call this internally."""

    def __init__(self, repo: InMemoryReminderRepository) -> None:
        self.repo = repo

    def create_from_utterance(self, text: str, duckling_time: str | None) -> Reminder:
        lowered = text.lower()
        kind = ReminderKind.GENERAL
        medication_name = None
        title = text
        if "medicine" in lowered or "medication" in lowered or "tablet" in lowered or "pill" in lowered:
            kind = ReminderKind.MEDICATION
            medication_name = "prescribed tablets"
            title = "Take medication"
        elif "appointment" in lowered or "doctor" in lowered:
            kind = ReminderKind.APPOINTMENT
            title = "Appointment reminder"
        time_iso = duckling_time or "unspecified"
        reminder = Reminder(
            id=uuid4().hex[:12],
            kind=kind,
            title=title,
            time_iso=time_iso,
            frequency="once",
            status=ReminderStatus.PENDING,
            medication_name=medication_name,
            notes=text,
        )
        return self.repo.add(reminder)

    def delete_matching(self, text: str) -> bool:
        lowered = text.lower()
        for reminder in self.repo.list_all():
            hay = f"{reminder.title} {reminder.notes} {reminder.medication_name or ''}".lower()
            if any(token in hay for token in lowered.split() if len(token) > 3):
                return self.repo.delete(reminder.id)
        upcoming = self.repo.upcoming(1)
        if upcoming:
            return self.repo.delete(upcoming[0].id)
        return False

    def mark_next_medication_done(self) -> Reminder | None:
        for reminder in self.repo.upcoming(20):
            if reminder.kind == ReminderKind.MEDICATION:
                reminder.status = ReminderStatus.COMPLETED
                return self.repo.update(reminder)
        return None

    def spoken_list(self) -> str:
        items = self.repo.upcoming(8)
        if not items:
            return "There are no pending reminders."
        lines = [f"{item.title} at {item.time_iso} ({item.kind.value}, {item.status.value})" for item in items]
        return "Pending reminders:\n" + "\n".join(lines)

    def spoken_medication(self) -> str:
        meds = [r for r in self.repo.list_all() if r.kind == ReminderKind.MEDICATION]
        if not meds:
            return "I do not have a medication reminder stored."
        lines = []
        for item in meds:
            name = item.medication_name or item.title
            lines.append(f"{name} at {item.time_iso}, status {item.status.value}.")
        return "Medication:\n" + "\n".join(lines)

    def spoken_daily_routine(self) -> str:
        routine = [r for r in self.repo.list_all() if r.kind == ReminderKind.DAILY_ROUTINE]
        if not routine:
            order = ", ".join(activity.value.replace("_", " ") for activity in RoutineActivity)
            return f"Typical daily routine order: {order}."
        routine.sort(key=lambda r: r.time_iso)
        lines = [f"{item.time_iso} {item.title} ({item.status.value})" for item in routine]
        meds = [r for r in self.repo.list_all() if r.kind == ReminderKind.MEDICATION]
        for med in meds:
            lines.append(f"{med.time_iso} medication ({med.status.value})")
        return "Today's routine:\n" + "\n".join(lines)

    def next_pending(self) -> Reminder | None:
        items = self.repo.upcoming(1)
        return items[0] if items else None
