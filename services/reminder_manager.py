from __future__ import annotations

import re
from datetime import datetime, timedelta
from uuid import uuid4

from models.domain import Reminder, ReminderKind, ReminderStatus, RoutineActivity
from repositories.in_memory import InMemoryReminderRepository

_DUE_WINDOW = timedelta(minutes=30)


class ReminderManager:
    """Deterministic reminder mutations. Llama 3 does not call this internally."""

    def __init__(self, repo: InMemoryReminderRepository) -> None:
        self.repo = repo
        self._active_id: str | None = None
        self._announced_keys: set[str] = set()
        self._speech_sent: set[str] = set()

    def create(
        self,
        *,
        title: str,
        time_iso: str,
        kind: ReminderKind | str = ReminderKind.GENERAL,
        frequency: str = "once",
        medication_name: str | None = None,
        notes: str = "",
    ) -> Reminder:
        resolved_kind = kind if isinstance(kind, ReminderKind) else ReminderKind(kind)
        reminder = Reminder(
            id=uuid4().hex[:12],
            kind=resolved_kind,
            title=title.strip() or "your reminder",
            time_iso=time_iso.strip() or "unspecified",
            frequency=frequency.strip() or "once",
            status=ReminderStatus.PENDING,
            medication_name=medication_name.strip() if medication_name else None,
            notes=notes.strip(),
        )
        return self.repo.add(reminder)

    def create_from_utterance(self, text: str, duckling_time: str | None) -> Reminder:
        lowered = text.lower()
        kind = ReminderKind.GENERAL
        medication_name = None
        task = _extract_task(text)
        if "medicine" in lowered or "medication" in lowered or "tablet" in lowered or "pill" in lowered:
            kind = ReminderKind.MEDICATION
            medication_name = "prescribed tablets"
        elif "appointment" in lowered or "doctor" in lowered:
            kind = ReminderKind.APPOINTMENT
        time_iso = duckling_time or _clock_from_text(text) or "unspecified"
        reminder = Reminder(
            id=uuid4().hex[:12],
            kind=kind,
            title=task,
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

    def complete(self, reminder_id: str) -> Reminder | None:
        for reminder in self.repo.list_all():
            if reminder.id == reminder_id:
                reminder.status = ReminderStatus.COMPLETED
                if self._active_id == reminder_id:
                    self._active_id = None
                return self.repo.update(reminder)
        return None

    def complete_active(self) -> Reminder | None:
        if self._active_id:
            done = self.complete(self._active_id)
            if done:
                return done
        return self.mark_next_medication_done()

    def snooze_active(self, minutes: int, now: datetime | None = None) -> Reminder | None:
        reminder = self.active_reminder()
        if reminder is None:
            return None
        when = now or datetime.now()
        reminder.time_iso = (when + timedelta(minutes=max(1, minutes))).isoformat(timespec="seconds")
        reminder.status = ReminderStatus.PENDING
        reminder.frequency = "once"
        self._announced_keys = {key for key in self._announced_keys if not key.startswith(f"{reminder.id}:")}
        self._speech_sent.discard(reminder.id)
        self._active_id = None
        return self.repo.update(reminder)

    def spoken_created(self, reminder: Reminder) -> str:
        task = _spoken_task(reminder)
        clock = spoken_clock(reminder.time_iso)
        if clock:
            return f"Okay, I'll remind you to {task} at {clock}."
        return f"Okay, I'll remind you to {task}."

    def spoken_due(self, reminder: Reminder) -> str:
        clock = spoken_clock(reminder.time_iso) or "now"
        task = _spoken_task(reminder)
        return f"It's {clock}. This is your reminder to {task}."

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

    def set_active(self, reminder_id: str) -> None:
        self._active_id = reminder_id

    def active_reminder(self) -> Reminder | None:
        if not self._active_id:
            return None
        for reminder in self.repo.list_all():
            if reminder.id == self._active_id and reminder.status == ReminderStatus.PENDING:
                return reminder
        return None

    def activate_due_if_needed(self, now: datetime | None = None) -> Reminder | None:
        active = self.active_reminder()
        if active:
            return active
        when = now or datetime.now()
        for reminder in self.repo.list_all():
            if reminder.status != ReminderStatus.PENDING:
                continue
            if not self._is_due(reminder, when):
                continue
            key = self._announce_key(reminder, when)
            if key in self._announced_keys:
                continue
            self._announced_keys.add(key)
            self._active_id = reminder.id
            return reminder
        return None

    def needs_speech(self, reminder_id: str) -> bool:
        return reminder_id not in self._speech_sent

    def mark_speech_sent(self, reminder_id: str) -> None:
        self._speech_sent.add(reminder_id)

    def _announce_key(self, reminder: Reminder, now: datetime) -> str:
        return f"{reminder.id}:{now.date().isoformat()}"

    def _is_due(self, reminder: Reminder, now: datetime) -> bool:
        due = parse_reminder_datetime(reminder.time_iso, now)
        if due is None:
            return False
        time_only = _is_time_only(reminder.time_iso) or reminder.frequency == "daily"
        if time_only:
            due = now.replace(hour=due.hour, minute=due.minute, second=0, microsecond=0)
        return due <= now <= due + _DUE_WINDOW


def spoken_clock(time_iso: str) -> str:
    parsed = parse_reminder_datetime(time_iso, datetime.now())
    if parsed is None:
        return ""
    if parsed.minute == 0:
        return parsed.strftime("%I %p").lstrip("0")
    return parsed.strftime("%I:%M %p").lstrip("0")


def parse_reminder_datetime(time_iso: str, now: datetime) -> datetime | None:
    raw = (time_iso or "").strip()
    if not raw or raw.lower() == "unspecified":
        return None
    if _is_time_only(raw):
        parts = raw.split(":")
        try:
            hour = int(parts[0])
            minute = int(parts[1]) if len(parts) > 1 else 0
            return now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        except ValueError:
            return None
    trimmed = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(trimmed)
        if parsed.tzinfo is not None:
            parsed = parsed.replace(tzinfo=None)
        return parsed
    except ValueError:
        return None


def _is_time_only(time_iso: str) -> bool:
    raw = time_iso.strip()
    return bool(re.fullmatch(r"\d{1,2}:\d{2}(:\d{2})?", raw))


def _extract_task(text: str) -> str:
    cleaned = " ".join(text.strip().split())
    cleaned = re.sub(r"^(please\s+)?(can you\s+|could you\s+)?", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^(set\s+(an?\s+)?(alarm\s+)?reminder\s+(for|to)\s+)", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^(create\s+(a\s+)?reminder\s+(for|to)\s+)", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^(i need\s+(a\s+)?reminder\s+to\s+)", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^remind me\s+(to\s+)?", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(
        r"\b(at|on|around)\s+\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)?\b",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )
    cleaned = re.sub(
        r"\b(tonight|tomorrow morning|tomorrow|today|in the morning|in the evening|at night)\b",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return cleaned or "your reminder"


def _spoken_task(reminder: Reminder) -> str:
    source = reminder.title.strip() or reminder.notes.strip() or "your reminder"
    if source.lower().startswith("remind"):
        source = _extract_task(source)
    task = re.sub(r"\bmy\b", "your", source, flags=re.IGNORECASE).strip(" .")
    task = re.sub(r"\bmedication\b", "medicine", task, flags=re.IGNORECASE)
    lowered = task.lower()
    if reminder.kind == ReminderKind.MEDICATION and not lowered.startswith("take"):
        if "medic" in lowered or "tablet" in lowered or "pill" in lowered:
            return f"take your {task.lower()}"
        return f"take {task.lower()}"
    return task[0].lower() + task[1:] if task else "your reminder"


def _clock_from_text(text: str) -> str | None:
    match = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b", text, flags=re.IGNORECASE)
    hour: int | None = None
    minute = 0
    if match:
        hour = int(match.group(1))
        minute = int(match.group(2) or 0)
        ampm = match.group(3).lower().replace(".", "")
        if ampm.startswith("p") and hour != 12:
            hour += 12
        if ampm.startswith("a") and hour == 12:
            hour = 0
    else:
        loose = re.search(r"\bat\s+(\d{1,2})(?::(\d{2}))?\b", text, flags=re.IGNORECASE)
        if loose:
            hour = int(loose.group(1))
            minute = int(loose.group(2) or 0)
            lowered = text.lower()
            if any(token in lowered for token in ("pm", "p.m", "tonight", "evening", "night")) and hour < 12:
                hour += 12
    if hour is None:
        return None
    when = datetime.now().replace(hour=hour, minute=minute, second=0, microsecond=0)
    if when < datetime.now() - timedelta(minutes=1):
        when += timedelta(days=1)
    return when.isoformat(timespec="seconds")
