"""Structured records used by application services. Independent of any database."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class ReminderKind(str, Enum):
    MEDICATION = "medication"
    APPOINTMENT = "appointment"
    DAILY_ROUTINE = "daily_routine"
    GENERAL = "general"


class ReminderStatus(str, Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    MISSED = "missed"


class RoutineActivity(str, Enum):
    WAKE_UP = "wake_up"
    BREAKFAST = "breakfast"
    MEDICATION = "medication"
    EXERCISE = "exercise"
    LUNCH = "lunch"
    REST = "rest"
    DINNER = "dinner"
    SLEEP = "sleep"


class Person(BaseModel):
    id: str
    name: str
    relationship: str
    notes: str = ""
    # FaceNet embedding stored later; empty until Phase 4 registration.
    face_embedding: list[float] = Field(default_factory=list)


class ImportantDate(BaseModel):
    id: str
    title: str
    date_iso: str
    kind: str  # birthday, anniversary, doctor, family, other
    notes: str = ""


class Preference(BaseModel):
    id: str
    subject: str  # patient or a person name
    key: str  # food, music, activity, preferred_name, daily
    value: str


class Reminder(BaseModel):
    id: str
    kind: ReminderKind
    title: str
    time_iso: str
    frequency: str = "once"
    status: ReminderStatus = ReminderStatus.PENDING
    medication_name: Optional[str] = None
    notes: str = ""


class Appointment(BaseModel):
    id: str
    doctor: str
    date_iso: str
    time_iso: str
    location: str = ""
    purpose: str = ""


class ActivityEvent(BaseModel):
    id: str
    timestamp_iso: str
    kind: str
    summary: str
    metadata: dict = Field(default_factory=dict)


class ConversationTurn(BaseModel):
    timestamp_iso: str
    role: str  # patient | assistant
    text: str
    intent: Optional[str] = None


class PatientProfile(BaseModel):
    id: str
    preferred_name: str
    caregiver_name: str = "caregiver"
    timezone: str = "local"


class VoiceTurnResult(BaseModel):
    transcript: str
    intent: str
    reply_text: str
    status: str
    facts: dict = Field(default_factory=dict)
    audio_wav: bytes = b""
    created_at: datetime = Field(default_factory=datetime.now)
