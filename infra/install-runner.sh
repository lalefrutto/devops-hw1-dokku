#!/usr/bin/env bash
# Registers a GitHub Actions self-hosted runner on the Dokku VM and lets it deploy to Dokku.
# Run on the VM:
#   sudo REPO_URL=https://github.com/<owner>/<repo> RUNNER_TOKEN=<token> bash install-runner.sh
# The token comes from Repository -> Settings -> Actions -> Runners -> New self-hosted runner
# (or: gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token).
set -euo pipefail

: "${REPO_URL:?REPO_URL is required}"
: "${RUNNER_TOKEN:?RUNNER_TOKEN is required}"
RUNNER_VERSION="${RUNNER_VERSION:-2.338.2}"
RUNNER_SHA256="${RUNNER_SHA256:-baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40}"  # linux-x64
RUNNER_USER="${RUNNER_USER:-gh-runner}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-dokku}"

if [[ $EUID -ne 0 ]]; then
  echo "run as root: sudo bash $0" >&2
  exit 1
fi

echo "==> 1. Unprivileged user '${RUNNER_USER}' (no sudo, no docker group)"
id "${RUNNER_USER}" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "${RUNNER_USER}"
RUNNER_HOME="$(getent passwd "${RUNNER_USER}" | cut -d: -f6)"
as_runner() { sudo -u "${RUNNER_USER}" -H "$@"; }

echo "==> 2. SSH key of the runner -> Dokku (the only way the runner can touch Dokku)"
if [[ ! -f "${RUNNER_HOME}/.ssh/id_rsa" ]]; then
  as_runner mkdir -p "${RUNNER_HOME}/.ssh"
  as_runner ssh-keygen -t ed25519 -f "${RUNNER_HOME}/.ssh/id_rsa" -N "" -C "${RUNNER_USER}@$(hostname)"
fi
if ! dokku ssh-keys:list 2>/dev/null | grep -q "NAME=\"${RUNNER_USER}\""; then
  cat "${RUNNER_HOME}/.ssh/id_rsa.pub" | dokku ssh-keys:add "${RUNNER_USER}"
fi
as_runner bash -c 'ssh-keyscan -H localhost >> ~/.ssh/known_hosts 2>/dev/null; sort -u -o ~/.ssh/known_hosts ~/.ssh/known_hosts'

echo "==> 3. Download actions/runner v${RUNNER_VERSION} and verify its checksum"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"
if [[ ! -x "${RUNNER_DIR}/config.sh" ]]; then
  as_runner mkdir -p "${RUNNER_DIR}"
  TARBALL="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  as_runner curl -fsSL -o "${RUNNER_DIR}/${TARBALL}" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"
  echo "${RUNNER_SHA256}  ${RUNNER_DIR}/${TARBALL}" | sha256sum -c -
  as_runner tar -xzf "${RUNNER_DIR}/${TARBALL}" -C "${RUNNER_DIR}"
  rm -f "${RUNNER_DIR}/${TARBALL}"
  "${RUNNER_DIR}/bin/installdependencies.sh"
fi

echo "==> 4. Register the runner (labels: self-hosted, Linux, X64, ${RUNNER_LABELS})"
cd "${RUNNER_DIR}"
as_runner ./config.sh --unattended --replace \
  --url "${REPO_URL}" --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" --labels "${RUNNER_LABELS}" --work _work

echo "==> 5. Run it as a systemd service under '${RUNNER_USER}'"
./svc.sh install "${RUNNER_USER}"
./svc.sh start
./svc.sh status --no-pager || true
