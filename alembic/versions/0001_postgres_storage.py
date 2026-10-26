"""initial care storage

Revision ID: 0001_postgres_storage
"""
from alembic import op
from repositories.postgres import Base
revision = "0001_postgres_storage"
down_revision = None
def upgrade():
    # Keep this historical revision immutable in scope.  Importing the shared
    # metadata must not make a fresh 0001 installation create tables added by
    # later revisions.
    names = (
        "patients", "people", "personal_memories", "important_dates",
        "reminders", "appointments", "activity_logs", "conversation_messages",
    )
    Base.metadata.create_all(op.get_bind(), tables=[Base.metadata.tables[name] for name in names])
def downgrade():
    names = (
        "conversation_messages", "activity_logs", "appointments", "reminders",
        "important_dates", "personal_memories", "people", "patients",
    )
    Base.metadata.drop_all(op.get_bind(), tables=[Base.metadata.tables[name] for name in names])
