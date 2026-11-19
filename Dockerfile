FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app
# Dokku reads healthchecks from app.json (kept in the image too, for older Dokku versions).
COPY app.json ./

RUN useradd --create-home --uid 10001 appuser
USER appuser

# Dokku reads EXPOSE and proxies http:80 -> 5000 through its nginx.
EXPOSE 5000
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-5000} --proxy-headers --forwarded-allow-ips='*'"]
