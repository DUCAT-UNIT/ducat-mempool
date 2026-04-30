#!/usr/bin/env bash
#
# start-mutinynet.sh — boot the Ducat block explorer locally against an
# already-running Mutinynet stack (Bitcoin Core + an indexer + Ducat validator).
#
# Expected services (defaults are the deploy/mutiny NixOS module values):
#   - Bitcoin Core RPC at 127.0.0.1:${BITCOIN_RPC_PORT} (user/pass below)
#   - One of:
#       * Esplora (Blockstream electrs) at 127.0.0.1:${ESPLORA_PORT}    (default)
#       * Electrs (Electrum protocol)   at 127.0.0.1:${ELECTRUM_PORT}   (MEMPOOL_BACKEND=electrum)
#   - Ducat validator HTTP API at 127.0.0.1:${VALIDATOR_PORT}
#
# Why default to esplora: it indexes spending-tx-by-outpoint, so per-output
# red-arrow links (forward navigation through the tx graph) work. The
# electrum backend can only report spent/unspent.
#
# What it does:
#   - Spins up an embedded MariaDB inside ./.local-mutinynet/ (Unix socket only,
#     no networking) and creates the `mempool` database on first run.
#   - Writes backend and frontend configs.
#   - Builds the backend (TS + the Rust GBT NAPI) on first run, then starts it.
#   - Starts the Angular dev server (proxies /api → backend, frontend hits the
#     Ducat validator at :4000 directly via CORS).
#
# Usage:
#   nix develop      # gets node, cargo, mariadb in PATH
#   ./scripts/start-mutinynet.sh
#
# Override defaults via env vars, e.g.
#   BITCOIN_RPC_PASS=hunter2 ./scripts/start-mutinynet.sh
#

set -euo pipefail

# Run from the repo root: the script writes config files into backend/ and
# frontend/, plus state into ./.local-mutinynet/, so we need a real checkout.
# (Resolving via BASH_SOURCE doesn't work under `nix run` — the script lives
# in the read-only Nix store there.)
REPO_ROOT="${DUCAT_MEMPOOL_REPO:-$PWD}"
if [ ! -f "${REPO_ROOT}/backend/package.json" ] || [ ! -f "${REPO_ROOT}/frontend/package.json" ]; then
  printf '\033[0;31merror:\033[0m run this from a ducat-mempool checkout\n' >&2
  printf '       (current dir: %s)\n' "${REPO_ROOT}" >&2
  printf '       e.g. cd ~/dev/ducat/ducat-mempool && nix run .#start-mutinynet\n' >&2
  exit 1
fi
STATE_DIR="${REPO_ROOT}/.local-mutinynet"
LOG_DIR="${STATE_DIR}/logs"
MYSQL_DIR="${STATE_DIR}/mysql"
MYSQL_SOCK="${STATE_DIR}/mysql.sock"
MYSQL_PID="${STATE_DIR}/mysql.pid"
BACKEND_PID="${STATE_DIR}/backend.pid"

BITCOIN_RPC_HOST="${BITCOIN_RPC_HOST:-127.0.0.1}"
BITCOIN_RPC_PORT="${BITCOIN_RPC_PORT:-19443}"
BITCOIN_RPC_USER="${BITCOIN_RPC_USER:-user}"
BITCOIN_RPC_PASS="${BITCOIN_RPC_PASS:-Shiengoojiraihooh3Va}"
ELECTRUM_HOST="${ELECTRUM_HOST:-127.0.0.1}"
ELECTRUM_PORT="${ELECTRUM_PORT:-50001}"
ESPLORA_HOST="${ESPLORA_HOST:-127.0.0.1}"
ESPLORA_PORT="${ESPLORA_PORT:-3000}"
MEMPOOL_BACKEND="${MEMPOOL_BACKEND:-esplora}"   # esplora | electrum
VALIDATOR_PORT="${VALIDATOR_PORT:-4000}"
BACKEND_PORT="${BACKEND_PORT:-8999}"
FRONTEND_PORT="${FRONTEND_PORT:-4200}"

case "${MEMPOOL_BACKEND}" in
  esplora|electrum) ;;
  *) printf '\033[0;31merror:\033[0m MEMPOOL_BACKEND must be "esplora" or "electrum" (got: %s)\n' "${MEMPOOL_BACKEND}" >&2; exit 1 ;;
esac

cyan()  { printf '\033[0;36m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[0;33m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { red "missing: $1 — run inside 'nix develop'"; exit 1; }
}
require node
require npm
require cargo
require mariadbd
require mariadb-install-db
require mariadb

mkdir -p "${STATE_DIR}" "${LOG_DIR}"

# --- preflight: probe expected services ---
cyan "==> Checking external services"
if ! curl -fsS --max-time 2 -u "${BITCOIN_RPC_USER}:${BITCOIN_RPC_PASS}" \
    --data-binary '{"jsonrpc":"1.0","id":"chk","method":"getblockchaininfo","params":[]}' \
    -H 'content-type: text/plain;' \
    "http://${BITCOIN_RPC_HOST}:${BITCOIN_RPC_PORT}/" >/dev/null; then
  yellow "  ! Bitcoin Core RPC at ${BITCOIN_RPC_HOST}:${BITCOIN_RPC_PORT} unreachable (continuing)"
else
  green  "  ✓ Bitcoin Core RPC ${BITCOIN_RPC_HOST}:${BITCOIN_RPC_PORT}"
fi
if [ "${MEMPOOL_BACKEND}" = "esplora" ]; then
  if ! curl -fsS --max-time 2 "http://${ESPLORA_HOST}:${ESPLORA_PORT}/blocks/tip/height" >/dev/null; then
    yellow "  ! Esplora at ${ESPLORA_HOST}:${ESPLORA_PORT} unreachable (continuing)"
  else
    green  "  ✓ Esplora ${ESPLORA_HOST}:${ESPLORA_PORT}"
  fi
else
  if ! (echo > "/dev/tcp/${ELECTRUM_HOST}/${ELECTRUM_PORT}") 2>/dev/null; then
    yellow "  ! Electrs at ${ELECTRUM_HOST}:${ELECTRUM_PORT} unreachable (continuing)"
  else
    green  "  ✓ Electrs ${ELECTRUM_HOST}:${ELECTRUM_PORT}"
  fi
fi
if ! curl -fsS --max-time 2 "http://127.0.0.1:${VALIDATOR_PORT}/api/height" >/dev/null; then
  yellow "  ! Ducat validator at 127.0.0.1:${VALIDATOR_PORT} unreachable (the explorer will run, but Ducat overlays will be empty)"
else
  green  "  ✓ Ducat validator 127.0.0.1:${VALIDATOR_PORT}"
fi

# --- mariadb ---
cyan "==> MariaDB (socket: ${MYSQL_SOCK})"
if [ ! -d "${MYSQL_DIR}/mysql" ]; then
  green "  initializing data dir at ${MYSQL_DIR}"
  mariadb-install-db --datadir="${MYSQL_DIR}" --auth-root-authentication-method=normal >/dev/null
fi

start_mariadb() {
  if [ -f "${MYSQL_PID}" ] && kill -0 "$(cat "${MYSQL_PID}")" 2>/dev/null; then
    green "  already running (pid $(cat "${MYSQL_PID}"))"
    return
  fi
  mariadbd \
    --datadir="${MYSQL_DIR}" \
    --socket="${MYSQL_SOCK}" \
    --pid-file="${MYSQL_PID}" \
    --skip-networking \
    --skip-log-bin \
    >"${LOG_DIR}/mariadb.log" 2>&1 &
  echo $! > "${MYSQL_PID}"
  for i in $(seq 1 30); do
    if mariadb --socket="${MYSQL_SOCK}" -uroot -e 'SELECT 1' >/dev/null 2>&1; then
      green "  ready"
      return
    fi
    sleep 0.5
  done
  red "MariaDB failed to start; see ${LOG_DIR}/mariadb.log"
  exit 1
}
start_mariadb

# Bootstrap database/user (idempotent)
mariadb --socket="${MYSQL_SOCK}" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS mempool;
CREATE USER IF NOT EXISTS 'mempool'@'localhost' IDENTIFIED BY 'mempool';
GRANT ALL ON mempool.* TO 'mempool'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- write configs ---
cyan "==> Writing backend/mempool-config.json"
cat > "${REPO_ROOT}/backend/mempool-config.json" <<JSON
{
  "MEMPOOL": {
    "NETWORK": "signet",
    "BACKEND": "${MEMPOOL_BACKEND}",
    "HTTP_PORT": ${BACKEND_PORT},
    "SPAWN_CLUSTER_PROCS": 0,
    "API_URL_PREFIX": "/api/v1/",
    "POLL_RATE_MS": 2000,
    "CACHE_DIR": "./cache",
    "INDEXING_BLOCKS_AMOUNT": 0,
    "BLOCKS_SUMMARIES_INDEXING": false,
    "AUDIT": false,
    "RUST_GBT": true,
    "STDOUT_LOG_MIN_PRIORITY": "info",
    "ALLOW_UNREACHABLE": true,
    "PRICE_UPDATES_PER_HOUR": 0
  },
  "CORE_RPC": {
    "HOST": "${BITCOIN_RPC_HOST}",
    "PORT": ${BITCOIN_RPC_PORT},
    "USERNAME": "${BITCOIN_RPC_USER}",
    "PASSWORD": "${BITCOIN_RPC_PASS}",
    "TIMEOUT": 60000
  },
  "ELECTRUM": {
    "HOST": "${ELECTRUM_HOST}",
    "PORT": ${ELECTRUM_PORT},
    "TLS_ENABLED": false
  },
  "ESPLORA": {
    "REST_API_URL": "http://${ESPLORA_HOST}:${ESPLORA_PORT}",
    "UNIX_SOCKET_PATH": null,
    "FALLBACK": []
  },
  "DATABASE": {
    "ENABLED": true,
    "HOST": "127.0.0.1",
    "PORT": 3306,
    "SOCKET": "${MYSQL_SOCK}",
    "DATABASE": "mempool",
    "USERNAME": "mempool",
    "PASSWORD": "mempool"
  },
  "SYSLOG": { "ENABLED": false },
  "STATISTICS": { "ENABLED": true },
  "FIAT_PRICE": { "ENABLED": false }
}
JSON

cyan "==> Writing frontend/mempool-frontend-config.json"
cat > "${REPO_ROOT}/frontend/mempool-frontend-config.json" <<JSON
{
  "TESTNET_ENABLED": false,
  "TESTNET4_ENABLED": false,
  "SIGNET_ENABLED": true,
  "LIQUID_ENABLED": false,
  "ITEMS_PER_PAGE": 25,
  "BASE_MODULE": "mempool",
  "MEMPOOL_WEBSITE_URL": "http://localhost:${FRONTEND_PORT}",
  "AUDIT": false,
  "LIGHTNING": false
}
JSON

# --- backend build (first run only) ---
cd "${REPO_ROOT}/backend"
if [ ! -d node_modules ] || [ ! -d rust-gbt ]; then
  cyan "==> Installing backend deps (this also builds the Rust GBT NAPI)"
  npm install
fi
if [ ! -d dist ]; then
  cyan "==> Building backend"
  npm run build
fi

# --- start backend ---
cyan "==> Starting backend on :${BACKEND_PORT}"
if [ -f "${BACKEND_PID}" ] && kill -0 "$(cat "${BACKEND_PID}")" 2>/dev/null; then
  yellow "  already running (pid $(cat "${BACKEND_PID}")) — restarting"
  kill "$(cat "${BACKEND_PID}")" || true
  sleep 1
fi
MEMPOOL_CONFIG_FILE="${REPO_ROOT}/backend/mempool-config.json" \
  node --max-old-space-size=2048 dist/index.js \
  >"${LOG_DIR}/backend.log" 2>&1 &
echo $! > "${BACKEND_PID}"
green "  backend pid $(cat "${BACKEND_PID}") — logs: ${LOG_DIR}/backend.log"

# --- frontend (foreground) ---
cd "${REPO_ROOT}/frontend"
if [ ! -d node_modules ]; then
  cyan "==> Installing frontend deps (cypress binary skipped)"
  CYPRESS_INSTALL_BINARY=0 npm install
fi

cleanup() {
  echo
  cyan "==> Shutting down"
  [ -f "${BACKEND_PID}" ] && kill "$(cat "${BACKEND_PID}")" 2>/dev/null || true
  [ -f "${MYSQL_PID}" ]   && kill "$(cat "${MYSQL_PID}")"   2>/dev/null || true
  rm -f "${BACKEND_PID}" "${MYSQL_PID}"
}
trap cleanup INT TERM EXIT

cyan "==> Starting frontend dev server on :${FRONTEND_PORT}"
green "    open http://localhost:${FRONTEND_PORT}"
PORT="${FRONTEND_PORT}" npm run serve -- --port "${FRONTEND_PORT}" --host 127.0.0.1
