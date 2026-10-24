from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from backend.container import get_container
from backend.auth.dependencies import PatientAccess, get_patient_access
from backend.auth.store import update_profile
from models.domain import ReminderKind

router = APIRouter(tags=["care"])


class CreateReminderRequest(BaseModel):
    title: str
    time_iso: str
    kind: str = ReminderKind.GENERAL.value
    frequency: str = "once"
    medication_name: Optional[str] = None
    notes: str = ""


class UpdateReminderRequest(BaseModel):
    title: Optional[str] = None
    time_iso: Optional[str] = None
    frequency: Optional[str] = None


class PreferredNameRequest(BaseModel):
    preferred_name: str = Field(min_length=1)


class MemoryNoteRequest(BaseModel):
    text: str = Field(min_length=1)


class UpdateMemoryNoteRequest(BaseModel):
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
def list_reminders(access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    items = [_reminder_payload(item) for item in container.repos.reminders.list_all()]
    items.sort(key=lambda row: row["time"])
    return {"reminders": items}


@router.post("/reminders")
def create_reminder(body: CreateReminderRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
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
def complete_reminder(reminder_id: str, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    reminder = container.reminders.complete(reminder_id)
    if reminder is None:
        raise HTTPException(status_code=404, detail="Reminder not found.")
    container.activity.log(
        "reminder",
        f"Reminder completed: {reminder.title}",
        {"reminder_id": reminder.id},
    )
    return {"reminder": _reminder_payload(reminder)}


@router.patch("/reminders/{reminder_id}")
def update_reminder(reminder_id: str, body: UpdateReminderRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    reminder = next((item for item in container.repos.reminders.list_all() if item.id == reminder_id), None)
    if reminder is None:
        raise HTTPException(status_code=404, detail="Reminder not found.")
    if body.title is not None:
        reminder.title = body.title.strip() or reminder.title
    if body.time_iso is not None:
        if not body.time_iso.strip():
            raise HTTPException(status_code=400, detail="A reminder time is required.")
        reminder.time_iso = body.time_iso.strip()
    if body.frequency is not None:
        reminder.frequency = body.frequency.strip() or reminder.frequency
    return {"reminder": _reminder_payload(container.repos.reminders.update(reminder))}


@router.delete("/reminders/{reminder_id}")
def delete_reminder(reminder_id: str, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    deleted = container.reminders.repo.delete(reminder_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Reminder not found.")
    container.activity.log("reminder", f"Reminder removed: {reminder_id}", {"reminder_id": reminder_id})
    return {"ok": True, "reminder_id": reminder_id}


@router.get("/appointments")
def list_appointments(access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    items = [_appointment_payload(item) for item in container.repos.appointments.list_all()]
    items.sort(key=lambda row: (row["date"], row["time"]))
    return {"appointments": items}


@router.post("/appointments")
def create_appointment(body: CreateAppointmentRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
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
def add_care_note(body: CareNoteRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    event = container.activity.log(
        "care_note",
        body.note.strip(),
        {"category": body.category},
    )
    return {"ok": True, "event_id": event.id, "summary": event.summary, "time": event.timestamp_iso}


@router.get("/memory")
def memory_overview(access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    repo = container.repos.memory
    return {
        "patient_name": access.user.get("profile", {}).get("preferred_name")
        or access.user.get("profile", {}).get("full_name")
        or container.memory.patient_display_name()
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
def add_memory_note(body: MemoryNoteRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    stored = container.memory.store_from_utterance(body.text.strip())
    container.activity.log("memory", stored, {})
    return {"message": stored}


@router.patch("/memory/notes/{memory_id}")
def update_memory_note(memory_id: str, body: UpdateMemoryNoteRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    note = next((item for item in container.repos.memory.list_preferences() if item.id == memory_id and item.key == "note"), None)
    if note is None:
        raise HTTPException(status_code=404, detail="Memory note not found.")
    note.value = body.text.strip()
    container.repos.memory.add_preference(note)
    container.memory.semantic.upsert(note.id, note.value, {"kind": "long_term_note"})
    return {"id": note.id, "text": note.value}


@router.delete("/memory/notes/{memory_id}")
def delete_memory_note(memory_id: str, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    note = next((item for item in container.repos.memory.list_preferences() if item.id == memory_id and item.key == "note"), None)
    if note is None or not container.repos.memory.delete_preference(memory_id):
        raise HTTPException(status_code=404, detail="Memory note not found.")
    container.memory.semantic.delete(memory_id)
    return {"ok": True, "memory_id": memory_id}


@router.get("/activity")
def recent_activity(limit: int = 50, access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
    events = container.repos.activity.recent(max(1, min(limit, 200)))
    return {
        "events": [
            {"id": event.id, "kind": event.kind, "summary": event.summary, "time": event.timestamp_iso}
            for event in events
        ]
    }


@router.get("/conversation")
def conversation_history(access: PatientAccess = Depends(get_patient_access)) -> dict:
    container = get_container(access.patient_id)
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
def set_preferred_name(body: PreferredNameRequest, access: PatientAccess = Depends(get_patient_access)) -> dict:
    # Keep this legacy settings endpoint on the same authoritative profile
    # record as the Profile screen and PatientContextService.
    preferred_name = body.preferred_name.strip()
    updated = update_profile(access.patient_id, {"preferred_name": preferred_name})
    container = get_container(access.patient_id)
    container.activity.log("profile", "Preferred name updated", {"key": "preferred_name"})
    return {"message": "Preferred name updated.", "preferred_name": updated["profile"]["preferred_name"]}
