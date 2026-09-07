from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from models.domain import ActivityEvent
from repositories.in_memory import InMemoryActivityRepository


class EmergencyService:
    """
    Emergency workflow stub.

    Real phone/SMS integrations can replace Notifier later without changing intent routing.
    """

    def __init__(self, activity: InMemoryActivityRepository, notifier: "Notifier | None" = None) -> None:
        self.activity = activity
        self.notifier = notifier or LogOnlyNotifier()

    def trigger(self, reason: str) -> ActivityEvent:
        event = ActivityEvent(
            id=uuid4().hex[:12],
            timestamp_iso=datetime.now().isoformat(timespec="seconds"),
            kind="emergency",
            summary="Emergency assistance requested",
            metadata={"reason": reason, "notify": "pending_integration"},
        )
        self.activity.add(event)
        self.notifier.notify_caregiver(event)
        return event


class Notifier:
    def notify_caregiver(self, event: ActivityEvent) -> None:
        raise NotImplementedError


class LogOnlyNotifier(Notifier):
    def notify_caregiver(self, event: ActivityEvent) -> None:
        print(f"[caregiver-notify-stub] {event.summary} id={event.id}")
