import os

import pytest
from fastapi.testclient import TestClient

from app import main

TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with TestClient(main.app) as c:
        yield c


def test_health_without_database(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "database": "not configured"}


def test_info_fields(client):
    body = client.get("/api/info").json()
    assert body["storage"] == "memory"
    assert {"app", "version", "hostname", "python", "uptime_seconds"} <= body.keys()


def test_version_comes_from_git_rev(client, monkeypatch):
    monkeypatch.setenv("GIT_REV", "0123456789abcdef")
    assert client.get("/api/info").json()["version"] == "0123456"


def test_index_page_and_counter(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert "Dokku" in r.text
    first = main.register_visit()
    assert main.register_visit() == first + 1


@pytest.mark.skipif(not TEST_DATABASE_URL, reason="TEST_DATABASE_URL is not set")
def test_visits_are_stored_in_postgres(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", TEST_DATABASE_URL)
    with TestClient(main.app) as c:  # lifespan creates the table
        assert c.get("/health").json() == {"status": "ok", "database": "ok"}
        assert c.get("/api/info").json()["storage"] == "postgres"
        first = main.register_visit()
        assert main.register_visit() == first + 1
