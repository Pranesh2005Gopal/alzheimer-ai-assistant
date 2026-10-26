"""add durable caregiver professional profiles and patient assignments

Revision ID: 0002_caregiver_profiles_and_assignments
Revises: 0001_postgres_storage

This migration is additive: it neither changes nor removes existing patient,
care, reminder, appointment, memory, or authentication data.  Existing JSON
permission links are mirrored only when an authorized patient explicitly saves
one; no blanket assignments are created.
"""
from alembic import op
import sqlalchemy as sa


revision = "0002_caregiver_assignments"
down_revision = "0001_postgres_storage"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "caregiver_profiles",
        sa.Column("caregiver_id", sa.String(length=64), primary_key=True),
        sa.Column("designation", sa.String(length=200), nullable=True),
        sa.Column("specialization", sa.String(length=300), nullable=True),
        sa.Column("organization", sa.String(length=300), nullable=True),
        sa.Column("qualifications", sa.Text(), nullable=True),
        sa.Column("professional_phone", sa.String(length=80), nullable=True),
        sa.Column("professional_email", sa.String(length=320), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
    )
    op.create_table(
        "caregiver_patient_assignments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("caregiver_id", sa.String(length=64), sa.ForeignKey("caregiver_profiles.caregiver_id", ondelete="CASCADE"), nullable=False),
        sa.Column("patient_id", sa.String(length=64), sa.ForeignKey("patients.id", ondelete="CASCADE"), nullable=False),
        sa.Column("permissions", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
        sa.UniqueConstraint("caregiver_id", "patient_id", name="uq_caregiver_patient_assignment"),
    )
    op.create_index("ix_caregiver_patient_assignments_caregiver_id", "caregiver_patient_assignments", ["caregiver_id"])
    op.create_index("ix_caregiver_patient_assignments_patient_id", "caregiver_patient_assignments", ["patient_id"])
    op.create_index("ix_caregiver_assignment_patient_caregiver", "caregiver_patient_assignments", ["patient_id", "caregiver_id"])


def downgrade() -> None:
    # Only the tables introduced above are removed.  Existing patient and care
    # data remains untouched; production rollback should be a reviewed action.
    op.drop_index("ix_caregiver_assignment_patient_caregiver", table_name="caregiver_patient_assignments")
    op.drop_index("ix_caregiver_patient_assignments_patient_id", table_name="caregiver_patient_assignments")
    op.drop_index("ix_caregiver_patient_assignments_caregiver_id", table_name="caregiver_patient_assignments")
    op.drop_table("caregiver_patient_assignments")
    op.drop_table("caregiver_profiles")
