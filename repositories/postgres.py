"""PostgreSQL repositories for the care assistant.

All queries are scoped to one patient id.  The services continue to use the
same small repository interfaces as the JSON/in-memory implementation.
"""
from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

from sqlalchemy import JSON, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, create_engine, select, update
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from models.domain import ActivityEvent, Appointment, ImportantDate, PatientProfile, Person, Preference, Reminder, ReminderKind, ReminderStatus
from repositories.in_memory import RepositoryBundle, load_seed


class Base(DeclarativeBase): pass
class PatientRow(Base):
    __tablename__ = "patients"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    preferred_name: Mapped[str] = mapped_column(String(200), default="")
    caregiver_name: Mapped[str] = mapped_column(String(200), default="caregiver")
    timezone: Mapped[str] = mapped_column(String(80), default="local")
class CaregiverProfileRow(Base):
    """Professional details for an authenticated caregiver.

    Authentication identities remain owned by the auth store; this row uses
    that stable identity as its key and intentionally contains no credentials.
    """
    __tablename__ = "caregiver_profiles"
    caregiver_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    designation: Mapped[str | None] = mapped_column(String(200), nullable=True)
    specialization: Mapped[str | None] = mapped_column(String(300), nullable=True)
    organization: Mapped[str | None] = mapped_column(String(300), nullable=True)
    qualifications: Mapped[str | None] = mapped_column(Text, nullable=True)
    professional_phone: Mapped[str | None] = mapped_column(String(80), nullable=True)
    professional_email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
class CaregiverPatientAssignmentRow(Base):
    __tablename__ = "caregiver_patient_assignments"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    caregiver_id: Mapped[str] = mapped_column(ForeignKey("caregiver_profiles.caregiver_id", ondelete="CASCADE"), index=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id", ondelete="CASCADE"), index=True)
    permissions: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    __table_args__ = (UniqueConstraint("caregiver_id", "patient_id", name="uq_caregiver_patient_assignment"),)
Index("ix_caregiver_assignment_patient_caregiver", CaregiverPatientAssignmentRow.patient_id, CaregiverPatientAssignmentRow.caregiver_id)
class PersonRow(Base):
    __tablename__ = "people"; id: Mapped[str] = mapped_column(String(64), primary_key=True); patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True); name: Mapped[str] = mapped_column(String(200)); relationship: Mapped[str] = mapped_column(String(100)); notes: Mapped[str] = mapped_column(Text, default=""); face_embedding: Mapped[list] = mapped_column(JSON, default=list)
class PreferenceRow(Base):
    __tablename__ = "personal_memories"; id: Mapped[str] = mapped_column(String(64), primary_key=True); patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True); subject: Mapped[str] = mapped_column(String(200)); key: Mapped[str] = mapped_column(String(100)); value: Mapped[str] = mapped_column(Text); created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
class ImportantDateRow(Base):
    __tablename__ = "important_dates"; id: Mapped[str] = mapped_column(String(64), primary_key=True); patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True); title: Mapped[str] = mapped_column(String(200)); date_iso: Mapped[str] = mapped_column(String(64)); kind: Mapped[str] = mapped_column(String(80)); notes: Mapped[str] = mapped_column(Text, default="")
class ReminderRow(Base):
    __tablename__ = "reminders"; id: Mapped[str] = mapped_column(String(64), primary_key=True); patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True); kind: Mapped[str] = mapped_column(String(40)); title: Mapped[str] = mapped_column(String(300)); time_iso: Mapped[str] = mapped_column(String(80), index=True); frequency: Mapped[str] = mapped_column(String(80)); status: Mapped[str] = mapped_column(String(40), index=True); medication_name: Mapped[str | None] = mapped_column(String(300), nullable=True); notes: Mapped[str] = mapped_column(Text, default="")
class AppointmentRow(Base):
    __tablename__ = "appointments"; id: Mapped[str] = mapped_column(String(64), primary_key=True); patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True); doctor: Mapped[str] = mapped_column(String(200)); date_iso: Mapped[str] = mapped_column(String(64)); time_iso: Mapped[str] = mapped_column(String(64)); location: Mapped[str] = mapped_column(String(300), default=""); purpose: Mapped[str] = mapped_column(Text, default="")
class ActivityRow(Base):
    __tablename__ = "activity_logs"; id: Mapped[str] = mapped_column(String(64), primary_key=True); patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True); timestamp_iso: Mapped[str] = mapped_column(String(64), index=True); kind: Mapped[str] = mapped_column(String(80)); summary: Mapped[str] = mapped_column(Text); metadata_json: Mapped[dict] = mapped_column(JSON, default=dict)
class ConversationRow(Base):
    __tablename__ = "conversation_messages"; id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True); patient_id: Mapped[str | None] = mapped_column(ForeignKey("patients.id"), index=True, nullable=True); conversation_id: Mapped[str] = mapped_column(String(64), default="default", index=True); timestamp_iso: Mapped[str] = mapped_column(String(64), index=True); role: Mapped[str] = mapped_column(String(20)); text: Mapped[str] = mapped_column(Text); intent: Mapped[str | None] = mapped_column(String(80), nullable=True)
    # Added after the original patient-only schema. Legacy rows intentionally
    # remain NULL and are not attributed to any account without evidence.
    account_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    account_role: Mapped[str | None] = mapped_column(String(20), nullable=True)
Index("ix_conversation_patient_time", ConversationRow.patient_id, ConversationRow.timestamp_iso)

class _Repo:
    def __init__(self, factory, patient_id): self.factory, self.patient_id = factory, patient_id
    def _all(self, row):
        with self.factory() as s: return list(s.scalars(select(row).where(row.patient_id == self.patient_id)))
class MemoryRepo(_Repo):
    def list_people(self): return [Person(id=x.id,name=x.name,relationship=x.relationship,notes=x.notes,face_embedding=x.face_embedding or []) for x in self._all(PersonRow)]
    def get_person_by_name(self,name): return next((x for x in self.list_people() if name.lower().replace('dr.','').strip() in x.name.lower().replace('dr.','')),None)
    def add_person(self,x):
        with self.factory.begin() as s: s.merge(PersonRow(id=x.id,patient_id=self.patient_id,name=x.name,relationship=x.relationship,notes=x.notes,face_embedding=x.face_embedding))
        return x
    update_person=add_person
    def delete_person(self,id):
        with self.factory.begin() as s:
            x=s.get(PersonRow,id)
            if not x or x.patient_id!=self.patient_id:return False
            s.delete(x); return True
    def list_preferences(self,subject=None):
        result=[Preference(id=x.id,subject=x.subject,key=x.key,value=x.value) for x in self._all(PreferenceRow)]
        return [x for x in result if not subject or x.subject.lower()==subject.lower()]
    def add_preference(self,x):
        with self.factory.begin() as s: s.merge(PreferenceRow(id=x.id,patient_id=self.patient_id,subject=x.subject,key=x.key,value=x.value))
        return x
    def delete_preference(self,id):
        with self.factory.begin() as s:
            x=s.get(PreferenceRow,id)
            if not x or x.patient_id!=self.patient_id:return False
            s.delete(x); return True
    def list_important_dates(self): return [ImportantDate(id=x.id,title=x.title,date_iso=x.date_iso,kind=x.kind,notes=x.notes) for x in self._all(ImportantDateRow)]
    def add_important_date(self,x):
        with self.factory.begin() as s: s.merge(ImportantDateRow(id=x.id,patient_id=self.patient_id,title=x.title,date_iso=x.date_iso,kind=x.kind,notes=x.notes))
        return x
    def search_facts(self,q):
        words={x.lower() for x in q.split() if len(x)>2}; return [f"{x.name} is your {x.relationship}. {x.notes}" for x in self.list_people() if words & set(f'{x.name} {x.relationship} {x.notes}'.lower().split())] + [f"{x.subject} {x.key}: {x.value}" for x in self.list_preferences() if words & set(x.value.lower().split())]
class ReminderRepo(_Repo):
    def _model(self,x): return Reminder(id=x.id,kind=ReminderKind(x.kind),title=x.title,time_iso=x.time_iso,frequency=x.frequency,status=ReminderStatus(x.status),medication_name=x.medication_name,notes=x.notes)
    def list_all(self): return [self._model(x) for x in self._all(ReminderRow)]
    def add(self,x): return self.update(x)
    def update(self,x):
        with self.factory.begin() as s: s.merge(ReminderRow(id=x.id,patient_id=self.patient_id,kind=x.kind.value,title=x.title,time_iso=x.time_iso,frequency=x.frequency,status=x.status.value,medication_name=x.medication_name,notes=x.notes))
        return x
    def delete(self,id):
        with self.factory.begin() as s:
            x=s.get(ReminderRow,id)
            if not x or x.patient_id!=self.patient_id:return False
            s.delete(x);return True
    def upcoming(self,limit=5): return sorted([x for x in self.list_all() if x.status==ReminderStatus.PENDING],key=lambda x:x.time_iso)[:limit]
class AppointmentRepo(_Repo):
    def list_all(self): return [Appointment(id=x.id,doctor=x.doctor,date_iso=x.date_iso,time_iso=x.time_iso,location=x.location,purpose=x.purpose) for x in self._all(AppointmentRow)]
    def add(self,x):
        with self.factory.begin() as s:s.merge(AppointmentRow(id=x.id,patient_id=self.patient_id,doctor=x.doctor,date_iso=x.date_iso,time_iso=x.time_iso,location=x.location,purpose=x.purpose))
        return x
    def next_appointment(self): return next(iter(sorted(self.list_all(),key=lambda x:(x.date_iso,x.time_iso))),None)
class ActivityRepo(_Repo):
    def add(self,x):
        with self.factory.begin() as s:s.merge(ActivityRow(id=x.id,patient_id=self.patient_id,timestamp_iso=x.timestamp_iso,kind=x.kind,summary=x.summary,metadata_json=x.metadata))
        return x
    def recent(self,limit=50): return [ActivityEvent(id=x.id,timestamp_iso=x.timestamp_iso,kind=x.kind,summary=x.summary,metadata=x.metadata_json or {}) for x in sorted(self._all(ActivityRow),key=lambda x:x.timestamp_iso,reverse=True)[:limit]]
class PatientRepo:
    def __init__(self,factory,id):self.factory,self.id=factory,id
    def get_profile(self):
        with self.factory() as s:
            x=s.get(PatientRow,self.id); return PatientProfile(id=x.id,preferred_name=x.preferred_name,caregiver_name=x.caregiver_name,timezone=x.timezone)
class PostgresConversationHistory:
    def __init__(self,factory,account_id,max_turns=50,account_role="patient"):self.factory,self.account_id,self.max_turns,self.account_role=factory,account_id,max_turns,account_role
    def add(self,role,text,intent=None):
        with self.factory.begin() as s:
            last=s.scalars(select(ConversationRow).where(ConversationRow.account_id==self.account_id).order_by(ConversationRow.id.desc()).limit(1)).first()
            if not last or last.role!=role or last.text!=text:s.add(ConversationRow(patient_id=self.account_id if self.account_role == "patient" else None,timestamp_iso=datetime.now().isoformat(timespec='seconds'),role=role,text=text,intent=intent,account_id=self.account_id,account_role=self.account_role))
    def recent(self,limit=50):
        with self.factory() as s: rows=list(s.scalars(select(ConversationRow).where(ConversationRow.account_id==self.account_id).order_by(ConversationRow.id.desc()).limit(min(limit,self.max_turns))))
        from models.domain import ConversationTurn; return [ConversationTurn(timestamp_iso=x.timestamp_iso,role=x.role,text=x.text,intent=x.intent) for x in reversed(rows)]
    def as_llm_messages(self): return [{"role":"user" if x.role=="patient" else "assistant","content":x.text} for x in self.recent(self.max_turns)]

def link_legacy_patient(factory, legacy_patient_id: str, patient_user_id: str) -> dict:
    """Move every care record to a verified auth patient id in one transaction."""
    if not legacy_patient_id or not patient_user_id:
        raise ValueError("Both legacy and target patient ids are required")
    with factory.begin() as s:
        legacy = s.get(PatientRow, legacy_patient_id)
        target = s.get(PatientRow, patient_user_id)
        if legacy is None:
            if target is not None:
                return {"status": "already_linked", "patient_id": patient_user_id}
            raise ValueError("Legacy patient record was not found")
        if legacy_patient_id == patient_user_id:
            return {"status": "already_linked", "patient_id": patient_user_id}
        if target is None:
            s.add(PatientRow(id=patient_user_id, preferred_name=legacy.preferred_name, caregiver_name=legacy.caregiver_name, timezone=legacy.timezone))
        for row in (PersonRow, PreferenceRow, ImportantDateRow, ReminderRow, AppointmentRow, ActivityRow, ConversationRow):
            s.execute(update(row).where(row.patient_id == legacy_patient_id).values(patient_id=patient_user_id))
        s.delete(legacy)
    return {"status": "linked", "patient_id": patient_user_id}


def upsert_caregiver_profile(factory, caregiver_id: str, fields: dict) -> dict:
    """Persist the caregiver-only professional fields without touching auth data."""
    allowed = {"designation", "specialization", "organization", "qualifications", "professional_phone", "professional_email"}
    values = {key: value for key, value in fields.items() if key in allowed}
    with factory.begin() as s:
        row = s.get(CaregiverProfileRow, caregiver_id)
        if row is None:
            row = CaregiverProfileRow(caregiver_id=caregiver_id)
            s.add(row)
        for key, value in values.items():
            setattr(row, key, value)
        s.flush()
        return {key: getattr(row, key) or "" for key in allowed}


def get_caregiver_profile(factory, caregiver_id: str) -> dict:
    with factory() as s:
        row = s.get(CaregiverProfileRow, caregiver_id)
        if row is None:
            return {}
        return {key: getattr(row, key) or "" for key in ("designation", "specialization", "organization", "qualifications", "professional_phone", "professional_email")}


def sync_caregiver_assignment(factory, caregiver_id: str, patient_id: str, permissions: list[str]) -> None:
    """Mirror a verified auth assignment in PostgreSQL for durable care queries.

    The caller has already validated the account roles.  We do not infer or
    create assignments here, so no patient is ever implicitly exposed.
    """
    with factory.begin() as s:
        if s.get(CaregiverProfileRow, caregiver_id) is None:
            s.add(CaregiverProfileRow(caregiver_id=caregiver_id))
        if s.get(PatientRow, patient_id) is None:
            s.add(PatientRow(id=patient_id))
        s.flush()
        row = s.scalars(select(CaregiverPatientAssignmentRow).where(
            CaregiverPatientAssignmentRow.caregiver_id == caregiver_id,
            CaregiverPatientAssignmentRow.patient_id == patient_id,
        )).first()
        if row is None:
            s.add(CaregiverPatientAssignmentRow(caregiver_id=caregiver_id, patient_id=patient_id, permissions=list(permissions)))
        else:
            row.permissions = list(permissions)


def list_caregiver_assignments(factory, caregiver_id: str) -> list[dict]:
    with factory() as s:
        rows = s.scalars(select(CaregiverPatientAssignmentRow).where(
            CaregiverPatientAssignmentRow.caregiver_id == caregiver_id
        )).all()
        return [{"patient_id": row.patient_id, "permissions": list(row.permissions or [])} for row in rows if row.permissions]

class PostgresRepositoryBundle:
    def __init__(self, url, patient_id, seed_path, *, pool_size=5, max_overflow=5, pool_timeout=30, pool_recycle=1800):
        engine_options = {"pool_pre_ping": True}
        if not url.startswith("sqlite"):
            engine_options.update(
                pool_size=pool_size,
                max_overflow=max_overflow,
                pool_timeout=pool_timeout,
                pool_recycle=pool_recycle,
            )
        self.engine=create_engine(url, **engine_options); self.factory=sessionmaker(self.engine,expire_on_commit=False)
        # Production schema changes are owned by Alembic.  SQLite is retained
        # solely for isolated repository tests.
        if url.startswith("sqlite"):
            Base.metadata.create_all(self.engine)
        self.patient_id=patient_id
        with self.factory.begin() as s:
            if not s.get(PatientRow,patient_id):
                seed=load_seed(seed_path); profile=seed.patient.get_profile(); s.add(PatientRow(id=patient_id,preferred_name=profile.preferred_name,caregiver_name=profile.caregiver_name,timezone=profile.timezone))
        self.memory=MemoryRepo(self.factory,patient_id); self.reminders=ReminderRepo(self.factory,patient_id); self.appointments=AppointmentRepo(self.factory,patient_id); self.activity=ActivityRepo(self.factory,patient_id); self.patient=PatientRepo(self.factory,patient_id)
