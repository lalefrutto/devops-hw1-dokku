"""Hello Dokku: a small FastAPI service used to demonstrate a Dokku CI/CD pipeline."""

import os
import platform
import socket
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from html import escape
from string import Template

import psycopg
from fastapi import FastAPI, Response
from fastapi.responses import HTMLResponse

APP_NAME = os.getenv("APP_NAME", "hello-dokku")
STARTED_AT = datetime.now(timezone.utc)
_START = time.monotonic()
_memory_visits = 0


def database_url() -> str | None:
    """DATABASE_URL is injected by `dokku postgres:link`; without it visits are counted in memory."""
    return os.getenv("DATABASE_URL") or None


def _connect(url: str) -> psycopg.Connection:
    return psycopg.connect(url, connect_timeout=3, autocommit=True)


def init_db() -> None:
    url = database_url()
    if not url:
        return
    with _connect(url) as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS visits ("
            " id bigserial PRIMARY KEY,"
            " visited_at timestamptz NOT NULL DEFAULT now(),"
            " served_by text NOT NULL)"
        )


def register_visit() -> int:
    """Stores a visit and returns the total number of visits."""
    global _memory_visits
    url = database_url()
    if not url:
        _memory_visits += 1
        return _memory_visits
    with _connect(url) as conn:
        conn.execute("INSERT INTO visits (served_by) VALUES (%s)", (socket.gethostname(),))
        return conn.execute("SELECT count(*) FROM visits").fetchone()[0]


def build_info() -> dict:
    return {
        "app": APP_NAME,
        # Dokku sets GIT_REV to the deployed commit SHA on every `git push` deploy.
        "version": os.getenv("GIT_REV", "local")[:7],
        "hostname": socket.gethostname(),
        "python": platform.python_version(),
        "storage": "postgres" if database_url() else "memory",
        "started_at": STARTED_AT.isoformat(timespec="seconds"),
        "uptime_seconds": int(time.monotonic() - _START),
    }


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    yield


app = FastAPI(title=APP_NAME, version="1.0.0", lifespan=lifespan)


@app.get("/health")
def health(response: Response) -> dict:
    """Used by Dokku zero-downtime checks (app.json) and by the smoke test in CI."""
    url = database_url()
    if not url:
        return {"status": "ok", "database": "not configured"}
    try:
        with _connect(url) as conn:
            conn.execute("SELECT 1")
    except psycopg.Error:
        response.status_code = 503
        return {"status": "error", "database": "unavailable"}
    return {"status": "ok", "database": "ok"}


@app.get("/api/info")
def info() -> dict:
    return build_info()


PAGE = Template("""<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hello Dokku</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0;
           display: grid; place-items: center; min-height: 100vh; margin: 0; }
    main { background: #1e293b; padding: 2rem 2.5rem; border-radius: 16px; max-width: 640px; }
    h1 { margin-top: 0; color: #38bdf8; }
    .visits { font-size: 2.5rem; font-weight: 700; color: #4ade80; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
    th, td { text-align: left; padding: .35rem .5rem; border-bottom: 1px solid #334155; }
    th { color: #94a3b8; font-weight: 500; width: 40%; }
    code { color: #fbbf24; }
  </style>
</head>
<body>
<main>
  <h1>Привет из Dokku!</h1>
  <p>Версия <code>$version</code> выложена автоматически:
     push в <code>main</code> &rarr; GitHub Actions &rarr; self-hosted runner &rarr; <code>git push dokku</code>.</p>
  <p>Посещений: <span class="visits">$visits</span></p>
  <table>$rows</table>
</main>
</body>
</html>
""")


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    visits = register_visit()
    data = build_info()
    rows = "".join(f"<tr><th>{escape(k)}</th><td>{escape(str(v))}</td></tr>" for k, v in data.items())
    return PAGE.substitute(version=escape(data["version"]), visits=visits, rows=rows)
