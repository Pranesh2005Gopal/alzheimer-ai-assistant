"""One-time, idempotent migration from the existing JSON stores to PostgreSQL."""
from __future__ import annotations
import json, shutil
from pathlib import Path
from utils.config import get_settings
from repositories.postgres import PostgresRepositoryBundle, PostgresConversationHistory
from models.domain import Person, Preference, ImportantDate, Reminder, ReminderKind, ReminderStatus, Appointment

def main():
    settings=get_settings()
    if not settings.database_url: raise SystemExit("DATABASE_URL is required")
    backup=Path("data/backups") / "pre_postgres_migration"
    backup.mkdir(parents=True,exist_ok=True)
    for path in (settings.seed_path,settings.state_path,settings.conversation_path):
        if path.exists(): shutil.copy2(path,backup/path.name)
    bundle=PostgresRepositoryBundle(settings.database_url,settings.database_patient_id,settings.seed_path)
    raw={}
    for path in (settings.seed_path,settings.state_path):
        if path.exists(): raw.update(json.loads(path.read_text()))
    for row in raw.get("people",[]): bundle.memory.add_person(Person(**row))
    for row in raw.get("preferences",[]): bundle.memory.add_preference(Preference(**row))
    for row in raw.get("important_dates",[]): bundle.memory.add_important_date(ImportantDate(**row))
    for row in raw.get("reminders",[]):
        row=dict(row);row["kind"]=ReminderKind(row["kind"]);row["status"]=ReminderStatus(row["status"]);bundle.reminders.update(Reminder(**row))
    for row in raw.get("appointments",[]): bundle.appointments.add(Appointment(**row))
    history=PostgresConversationHistory(bundle.factory,settings.database_patient_id,settings.conversation_history_limit)
    # Conversation messages do not have stable legacy IDs.  Import them only
    # into an empty patient history so rerunning this migration cannot duplicate
    # an existing history.
    if settings.conversation_path.exists() and not history.recent(1):
        for row in json.loads(settings.conversation_path.read_text()): history.add(row["role"],row["text"],row.get("intent"))
    print({"backup":str(backup),"people":len(bundle.memory.list_people()),"memories":len(bundle.memory.list_preferences()),"reminders":len(bundle.reminders.list_all()),"appointments":len(bundle.appointments.list_all()),"messages":len(history.recent(50))})
if __name__=="__main__":main()
