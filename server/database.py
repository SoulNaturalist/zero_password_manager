from collections.abc import Generator

from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import Session, declarative_base, sessionmaker

SQLALCHEMY_DATABASE_URL = "sqlite:///./zero_vault.db"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
)


@event.listens_for(engine, "connect")
def _set_sqlite_pragmas(dbapi_connection, _connection_record):
    """
    Apply security and performance PRAGMAs on every new SQLite connection.

    WAL mode:    allows concurrent readers during writes (avoids lock contention).
    foreign_keys: enforce FK constraints (SQLite ignores them by default).
    busy_timeout: prevent "database is locked" errors under load.
    synchronous NORMAL: safe with WAL; faster than FULL without data-loss risk.
    """
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.execute("PRAGMA busy_timeout=5000")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.close()


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def run_migrations(engine) -> None:
    """Add missing columns to existing tables.

    SQLAlchemy's create_all() only creates tables that don't exist yet — it
    never alters existing tables.  Any column added to a model after the
    initial deployment must be added manually via ALTER TABLE.
    """
    with engine.connect() as conn:
        result = conn.execute(text("PRAGMA table_info(users)"))
        existing = {row[1] for row in result.fetchall()}
        if "token_version" not in existing:
            conn.execute(
                text("ALTER TABLE users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0")
            )
            conn.commit()


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency: yields a database session and closes it when done."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
