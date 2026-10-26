"""scope conversations to their authenticated account

Revision ID: 0003_chat_scope
Revises: 0002_caregiver_assignments

The migration is intentionally additive. Existing conversation rows are kept
with NULL ownership because their owner cannot be established safely.
"""
from alembic import op
import sqlalchemy as sa


revision = "0003_chat_scope"
down_revision = "0002_caregiver_assignments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"]: column for column in inspector.get_columns("conversation_messages")}
    if not columns["patient_id"]["nullable"]:
        # Caregiver-owned conversation rows have no patient foreign key.
        with op.batch_alter_table("conversation_messages") as batch:
            batch.alter_column("patient_id", existing_type=sa.String(length=64), nullable=True)
    if "account_id" not in columns:
        op.add_column("conversation_messages", sa.Column("account_id", sa.String(length=64), nullable=True))
    if "account_role" not in columns:
        op.add_column("conversation_messages", sa.Column("account_role", sa.String(length=20), nullable=True))
    indexes = {index["name"] for index in inspector.get_indexes("conversation_messages")}
    if "ix_conversation_messages_account_id" not in indexes:
        op.create_index("ix_conversation_messages_account_id", "conversation_messages", ["account_id"])


def downgrade() -> None:
    # Kept deliberately non-destructive for historical rows: converting NULL
    # caregiver rows back to a patient owner would require guessing.
    op.drop_index("ix_conversation_messages_account_id", table_name="conversation_messages")
    op.drop_column("conversation_messages", "account_role")
    op.drop_column("conversation_messages", "account_id")
