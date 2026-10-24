import base64
from datetime import datetime

from fastapi import APIRouter, Depends

from backend.container import get_container
from backend.auth.dependencies import PatientAccess, get_patient_access

router = APIRouter(tags=["overview"])


@router.get("/patient/overview")
def patient_overview(access: PatientAccess = Depends(get_patient_access)) -> dict:
    """Elderly home-screen data. Full dashboards land in Phases 5–6."""
    container = get_container(access.patient_id)
    now = datetime.now()
    nxt_reminder = container.reminders.next_pending()
    nxt_appointment = container.repos.appointments.next_appointment()
    people = container.repos.memory.list_people()
    due = container.reminders.activate_due_if_needed(now)
    active_reminder = None
    if due is not None:
        container.dialogue.note_reminder_alert(due.id)
        message = container.reminders.spoken_due(due)
        needs_speech = container.reminders.needs_speech(due.id)
        active_reminder = {
            "id": due.id,
            "title": due.title,
            "time": due.time_iso,
            "kind": due.kind.value,
            "message": message,
            "needs_speech": needs_speech,
            "audio_wav_base64": "",
        }
        if needs_speech:
            audio = container.pipeline.tts.speak(message)
            active_reminder["audio_wav_base64"] = base64.b64encode(audio).decode("ascii")
            container.reminders.mark_speech_sent(due.id)
            container.activity.log("reminder", message, {"reminder_id": due.id})
    profile = container.repos.patient.get_profile()
    # The authenticated profile is the source edited by the Profile screen.
    # Do not show a seed/default name after a patient has changed it.
    auth_profile = access.user.get("profile", {})
    patient_name = auth_profile.get("preferred_name") or auth_profile.get("full_name") or container.memory.patient_display_name() or profile.preferred_name
    reminders = [_reminder_summary(item) for item in container.repos.reminders.list_all()]
    reminders.sort(key=lambda row: row["time"])
    appointments = [
        {
            "id": item.id,
            "doctor": item.doctor,
            "date": item.date_iso,
            "time": item.time_iso,
            "location": item.location,
            "purpose": item.purpose,
        }
        for item in container.repos.appointments.list_all()
    ]
    dates = container.repos.memory.list_important_dates()
    prefs = container.repos.memory.list_preferences()
    return {
        "greeting": _greeting(now),
        "patient_name": patient_name,
        "caregiver_name": profile.caregiver_name,
        "date_label": now.strftime("%A, %b %d"),
        "time_label": now.strftime("%I:%M %p").lstrip("0"),
        "prompt": "How can I help?",
        "next_reminder": None
        if nxt_reminder is None
        else {
            "id": nxt_reminder.id,
            "title": nxt_reminder.title,
            "time": nxt_reminder.time_iso,
            "kind": nxt_reminder.kind.value,
            "status": nxt_reminder.status.value,
        },
        "active_reminder": active_reminder,
        "reminders": reminders,
        "next_appointment": None
        if nxt_appointment is None
        else {
            "id": nxt_appointment.id,
            "doctor": nxt_appointment.doctor,
            "date": nxt_appointment.date_iso,
            "time": nxt_appointment.time_iso,
            "location": nxt_appointment.location,
            "purpose": nxt_appointment.purpose,
        },
        "appointments": appointments,
        "family": [
            {"id": p.id, "name": p.name, "relationship": p.relationship, "notes": p.notes}
            for p in people
        ],
        "memory": {
            "people_count": len(people),
            "dates_count": len(dates),
            "preferences_count": len(prefs),
            "important_dates": [
                {"title": item.title, "date": item.date_iso, "kind": item.kind}
                for item in dates[:4]
            ],
            "preferences": [
                {"subject": pref.subject, "key": pref.key, "value": pref.value}
                for pref in prefs[:4]
            ],
        },
        "recent_activity": [
            {"kind": e.kind, "summary": e.summary, "time": e.timestamp_iso}
            for e in container.repos.activity.recent(8)
        ],
    }


def _reminder_summary(reminder) -> dict:
    return {
        "id": reminder.id,
        "kind": reminder.kind.value,
        "title": reminder.title,
        "time": reminder.time_iso,
        "frequency": reminder.frequency,
        "status": reminder.status.value,
        "medication_name": reminder.medication_name,
    }


def _greeting(now: datetime) -> str:
    hour = now.hour
    if hour < 12:
        return "Good morning"
    if hour < 17:
        return "Good afternoon"
    return "Good evening"
