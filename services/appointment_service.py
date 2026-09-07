from __future__ import annotations

from uuid import uuid4

from models.domain import Appointment
from repositories.in_memory import InMemoryAppointmentRepository


class AppointmentService:
    def __init__(self, repo: InMemoryAppointmentRepository) -> None:
        self.repo = repo

    def spoken_next(self) -> str:
        nxt = self.repo.next_appointment()
        if nxt is None:
            return "There is no appointment stored."
        return (
            f"Next appointment: {nxt.doctor} on {nxt.date_iso} at {nxt.time_iso}. "
            f"Location: {nxt.location or 'not stored'}. Purpose: {nxt.purpose or 'not stored'}."
        )

    def create_from_utterance(self, text: str, duckling_time: str | None) -> Appointment:
        doctor = "Dr. Kumar" if "kumar" in text.lower() else "your doctor"
        appointment = Appointment(
            id=uuid4().hex[:12],
            doctor=doctor,
            date_iso=str(duckling_time or "unspecified"),
            time_iso=str(duckling_time or "unspecified"),
            location="",
            purpose=text,
        )
        return self.repo.add(appointment)
