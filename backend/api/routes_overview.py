from datetime import datetime

from fastapi import APIRouter

from backend.container import get_container

router = APIRouter(tags=["overview"])


@router.get("/patient/overview")
def patient_overview() -> dict:
    """Elderly home-screen data. Full dashboards land in Phases 5–6."""
    container = get_container()
    now = datetime.now()
    nxt_reminder = container.reminders.next_pending()
    nxt_appointment = container.repos.appointments.next_appointment()
    people = container.repos.memory.list_people()
    return {
        "greeting": _greeting(now),
        "date_label": now.strftime("%A, %b %d"),
        "time_label": now.strftime("%I:%M %p").lstrip("0"),
        "prompt": "How can I help?",
        "next_reminder": None
        if nxt_reminder is None
        else {
            "title": nxt_reminder.title,
            "time": nxt_reminder.time_iso,
            "kind": nxt_reminder.kind.value,
        },
        "next_appointment": None
        if nxt_appointment is None
        else {
            "doctor": nxt_appointment.doctor,
            "date": nxt_appointment.date_iso,
            "time": nxt_appointment.time_iso,
        },
        "family": [{"name": p.name, "relationship": p.relationship} for p in people],
        "recent_activity": [
            {"kind": e.kind, "summary": e.summary, "time": e.timestamp_iso}
            for e in container.repos.activity.recent(8)
        ],
    }


def _greeting(now: datetime) -> str:
    hour = now.hour
    if hour < 12:
        return "Good morning"
    if hour < 17:
        return "Good afternoon"
    return "Good evening"
