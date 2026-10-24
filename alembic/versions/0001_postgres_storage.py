"""initial care storage

Revision ID: 0001_postgres_storage
"""
from alembic import op
from repositories.postgres import Base
revision = "0001_postgres_storage"
down_revision = None
def upgrade(): Base.metadata.create_all(op.get_bind())
def downgrade(): Base.metadata.drop_all(op.get_bind())
