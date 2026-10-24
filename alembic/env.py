from alembic import context
from sqlalchemy import engine_from_config, pool
from repositories.postgres import Base
from utils.config import get_settings

config = context.config
target_metadata = Base.metadata

# Alembic's INI parser performs %-interpolation.  Keep credentials out of the
# INI file and escape literal percent signs supplied in a URL/password.
database_url = get_settings().database_url
if not database_url:
    raise RuntimeError("DATABASE_URL must be set in .env or the environment before running Alembic.")
config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))

def run_migrations_online():
    connectable = engine_from_config(config.get_section(config.config_ini_section), prefix="sqlalchemy.", poolclass=pool.NullPool)
    with connectable.connect() as connection:
        with connection.begin(): context.configure(connection=connection, target_metadata=target_metadata); context.run_migrations()
run_migrations_online()
