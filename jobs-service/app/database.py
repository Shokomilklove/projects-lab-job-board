import os
from pathlib import Path
from urllib.parse import quote_plus
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

POSTGRES_DB = os.getenv("POSTGRES_DB", "jobboard")
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD_FILE = os.getenv("POSTGRES_PASSWORD_FILE","/run/secrets/db_password")

POSTGRES_PASSWORD = Path(POSTGRES_PASSWORD_FILE).read_text().strip()

DATABASE_URL = (
    f"postgresql://{quote_plus(POSTGRES_USER)}:"
    f"{quote_plus(POSTGRES_PASSWORD)}"
    f"@postgres:5432/{POSTGRES_DB}"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
