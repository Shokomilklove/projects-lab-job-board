import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.database import get_db
from app.models import Base


# In-memory SQLite database for tests
SQLALCHEMY_DATABASE_URL = "sqlite://"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

TestingSessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)

    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)


def override_get_db(db):
    try:
        yield db
    finally:
        db.close()


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()


def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_create_job(client):
    job_data = {
        "title": "Python Developer",
        "description": "Looking for an experienced Python developer.",
        "company": "Test Company",
        "location": "Tel Aviv",
        "salary_range": "15000-20000",
    }

    response = client.post("/jobs", json=job_data)

    assert response.status_code == 201

    data = response.json()
    assert data["title"] == job_data["title"]
    assert data["description"] == job_data["description"]
    assert data["company"] == job_data["company"]
    assert data["location"] == job_data["location"]
    assert "id" in data
    assert "created_at" in data


def test_create_job_missing_fields(client):
    job_data = {
        "title": "Python Developer",
    }

    response = client.post("/jobs", json=job_data)

    assert response.status_code == 422


def test_get_nonexistent_job(client):
    response = client.get("/jobs/non-existent-id")

    assert response.status_code == 404