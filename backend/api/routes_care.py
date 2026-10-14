from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from backend.container import get_container
from models.domain import ReminderKind

router = APIRouter(tags=["care"])


class CreateReminderRequest(BaseModel):
    title: str
    time_iso: str
    kind: str = ReminderKind.GENERAL.value
    frequency: str = "once"
    medication_name: Optional[str] = None
    notes: str = ""


class PreferredNameRequest(BaseModel):
    preferred_name: str = Field(min_length=1)


class MemoryNoteRequest(BaseModel):
    text: str = Field(min_length=1)


class CreateAppointmentRequest(BaseModel):
    doctor: str = Field(min_length=1)
    date_iso: str = Field(min_length=1)
    time_iso: str = Field(min_length=1)
    location: str = ""
    purpose: str = ""


class CareNoteRequest(BaseModel):
    note: str = Field(min_length=1)
    category: str = "observation"


def _reminder_payload(reminder) -> dict:
    return {
        "id": reminder.id,
        "kind": reminder.kind.value,
        "title": reminder.title,
        "time": reminder.time_iso,
        "frequency": reminder.frequency,
        "status": reminder.status.value,
        "medication_name": reminder.medication_name,
        "notes": reminder.notes,
    }


def _appointment_payload(appointment) -> dict:
    return {
        "id": appointment.id,
        "doctor": appointment.doctor,
        "date": appointment.date_iso,
        "time": appointment.time_iso,
        "location": appointment.location,
        "purpose": appointment.purpose,
    }


@router.get("/reminders")
def list_reminders() -> dict:
    container = get_container()
    items = [_reminder_payload(item) for item in container.repos.reminders.list_all()]
    items.sort(key=lambda row: row["time"])
    return {"reminders": items}


@router.post("/reminders")
def create_reminder(body: CreateReminderRequest) -> dict:
    container = get_container()
    try:
        kind = ReminderKind(body.kind)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Unknown reminder kind.") from exc
    reminder = container.reminders.create(
        title=body.title,
        time_iso=body.time_iso,
        kind=kind,
        frequency=body.frequency,
        medication_name=body.medication_name,
        notes=body.notes,
    )
    container.activity.log(
        "reminder",
        f"Reminder created: {reminder.title}",
        {"reminder_id": reminder.id, "kind": reminder.kind.value},
    )
    return {"reminder": _reminder_payload(reminder)}


@router.post("/reminders/{reminder_id}/complete")
def complete_reminder(reminder_id: str) -> dict:
    container = get_container()
    reminder = container.reminders.complete(reminder_id)
    if reminder is None:
        raise HTTPException(status_code=404, detail="Reminder not found.")
    container.activity.log(
        "reminder",
        f"Reminder completed: {reminder.title}",
        {"reminder_id": reminder.id},
    )
    return {"reminder": _reminder_payload(reminder)}


@router.delete("/reminders/{reminder_id}")
def delete_reminder(reminder_id: str) -> dict:
    container = get_container()
    deleted = container.reminders.repo.delete(reminder_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Reminder not found.")
    container.activity.log("reminder", f"Reminder removed: {reminder_id}", {"reminder_id": reminder_id})
    return {"ok": True, "reminder_id": reminder_id}


@router.get("/appointments")
def list_appointments() -> dict:
    container = get_container()
    items = [_appointment_payload(item) for item in container.repos.appointments.list_all()]
    items.sort(key=lambda row: (row["date"], row["time"]))
    return {"appointments": items}


@router.post("/appointments")
def create_appointment(body: CreateAppointmentRequest) -> dict:
    container = get_container()
    appointment = container.appointments.create(
        doctor=body.doctor,
        date_iso=body.date_iso,
        time_iso=body.time_iso,
        location=body.location,
        purpose=body.purpose,
    )
    container.activity.log(
        "appointment",
        f"Appointment scheduled with {appointment.doctor} on {appointment.date_iso} at {appointment.time_iso}",
        {"appointment_id": appointment.id},
    )
    return {"appointment": _appointment_payload(appointment)}


@router.post("/care/notes")
def add_care_note(body: CareNoteRequest) -> dict:
    container = get_container()
    event = container.activity.log(
        "care_note",
        body.note.strip(),
        {"category": body.category},
    )
    return {"ok": True, "event_id": event.id, "summary": event.summary, "time": event.timestamp_iso}


@router.get("/memory")
def memory_overview() -> dict:
    container = get_container()
    repo = container.repos.memory
    return {
        "patient_name": container.memory.patient_display_name()
        or container.repos.patient.get_profile().preferred_name,
        "people": [
            {
                "id": person.id,
                "name": person.name,
                "relationship": person.relationship,
                "notes": person.notes,
                "has_face_profile": bool(person.face_embedding),
            }
            for person in repo.list_people()
        ],
        "important_dates": [
            {
                "id": item.id,
                "title": item.title,
                "date": item.date_iso,
                "kind": item.kind,
                "notes": item.notes,
            }
            for item in repo.list_important_dates()
        ],
        "preferences": [
            {"id": pref.id, "subject": pref.subject, "key": pref.key, "value": pref.value}
            for pref in repo.list_preferences()
        ],
    }


@router.post("/memory/notes")
def add_memory_note(body: MemoryNoteRequest) -> dict:
    container = get_container()
    stored = container.memory.store_from_utterance(body.text.strip())
    container.activity.log("memory", stored, {})
    return {"message": stored}


@router.get("/activity")
def recent_activity(limit: int = 50) -> dict:
    container = get_container()
    events = container.repos.activity.recent(max(1, min(limit, 200)))
    return {
        "events": [
            {"id": event.id, "kind": event.kind, "summary": event.summary, "time": event.timestamp_iso}
            for event in events
        ]
    }


@router.get("/conversation")
def conversation_history() -> dict:
    container = get_container()
    turns = container.history.recent(40)
    return {
        "turns": [
            {
                "role": turn.role,
                "text": turn.text,
                "intent": turn.intent,
                "time": turn.timestamp_iso,
            }
            for turn in turns
        ]
    }


@router.post("/profile/name")
def set_preferred_name(body: PreferredNameRequest) -> dict:
    container = get_container()
    message = container.memory.set_preferred_name(body.preferred_name)
    if not message:
        raise HTTPException(status_code=400, detail="A name is required.")
    container.activity.log("memory", message, {"key": "preferred_name"})
    return {"message": message, "preferred_name": body.preferred_name.strip()}
