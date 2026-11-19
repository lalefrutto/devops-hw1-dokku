#!/usr/bin/env bash
# Installs and configures Dokku on a clean Ubuntu 24.04 VM.
# Run on the VM:  sudo bash install-dokku.sh
set -euo pipefail

DOKKU_VERSION="${DOKKU_VERSION:-v0.38.34}"
APP="${APP:-hello}"
DB="${DB:-hello-db}"
# <app>.<ip>.sslip.io resolves to the VM IP without editing any hosts file.
GLOBAL_DOMAIN="${GLOBAL_DOMAIN:-$(hostname -I | awk '{print $1}').sslip.io}"

if [[ $EUID -ne 0 ]]; then
  echo "run as root: sudo bash $0" >&2
  exit 1
fi

echo "==> 1. Install Dokku ${DOKKU_VERSION} (also installs Docker and nginx)"
if ! command -v dokku >/dev/null 2>&1; then
  wget -nv -O /tmp/dokku-bootstrap.sh "https://dokku.com/install/${DOKKU_VERSION}/bootstrap.sh"
  DOKKU_TAG="${DOKKU_VERSION}" bash /tmp/dokku-bootstrap.sh
fi
dokku version

echo "==> 2. Global domain: ${GLOBAL_DOMAIN}"
dokku domains:set-global "${GLOBAL_DOMAIN}"

echo "==> 3. Postgres plugin"
if ! dokku plugin:installed postgres; then
  dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
fi

echo "==> 4. App '${APP}'"
dokku apps:exists "${APP}" >/dev/null 2>&1 || dokku apps:create "${APP}"
# Dokku deploys the 'master' branch by default; our repository uses 'main'.
dokku git:set "${APP}" deploy-branch main
# nginx :80 -> container :5000 (the port from EXPOSE in the Dockerfile)
dokku ports:set "${APP}" http:80:5000

echo "==> 5. Postgres service '${DB}' linked to '${APP}' (injects DATABASE_URL)"
dokku postgres:exists "${DB}" >/dev/null 2>&1 || dokku postgres:create "${DB}"
dokku postgres:linked "${DB}" "${APP}" >/dev/null 2>&1 || dokku postgres:link "${DB}" "${APP}" --no-restart

echo "==> Done"
dokku domains:report "${APP}"
