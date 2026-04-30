# Ducat block explorer — local development

This fork of [mempool.space](https://mempool.space) adds Ducat protocol overlays
(vault banner, per-output asset badges) to the transaction page. This document
describes how to run the explorer locally against a Mutinynet stack.

## Prerequisites

You need three Mutinynet services already running on `localhost`:

| Service          | Default port | Provided by                                      |
| ---------------- | ------------ | ------------------------------------------------ |
| Bitcoin Core RPC | `19443`      | `services.electrs-mutinynet` in validator-rs     |
| Electrs (plain)  | `50001`      | `services.electrs-mutinynet` in validator-rs     |
| Ducat validator  | `4000`       | `services.ducat-mutinynet` in validator-rs       |

The validator-rs repo exposes the NixOS module `services.ducat-mutinynet` at
`deploy/mutiny/`, which wires up all three with a single
`services.ducat-mutinynet.enable = true;`. The defaults (RPC user `user`,
password `Shiengoojiraihooh3Va`, ports above) are what `start-mutinynet.sh`
expects out of the box.

You also need:

- **Nix with flakes enabled**.
- **NixOS with `programs.nix-ld.enable = true;`** (or any other working dynamic
  linker shim) — `npm install` pulls prebuilt Linux binaries (esbuild,
  swc, the Cypress installer if not skipped, etc.) that won't run on a bare
  NixOS without `nix-ld`.

## Start the explorer

**You must run this from the repo root** — the script writes config files
into `backend/` and `frontend/` and state into `./.local-mutinynet/`, so it
needs a real checkout in your current working directory:

```bash
cd ~/dev/ducat/ducat-mempool
nix run .#start-mutinynet
```

(If you'd rather run it from elsewhere, point at the checkout explicitly:
`DUCAT_MEMPOOL_REPO=~/dev/ducat/ducat-mempool nix run .#start-mutinynet`.)

That single command:

1. Probes the three services above and warns if any are down.
2. Initializes an embedded MariaDB at `./.local-mutinynet/mysql/` (Unix socket,
   no networking) and creates the `mempool` database on first run.
3. Writes `backend/mempool-config.json` and
   `frontend/mempool-frontend-config.json` for signet/Mutinynet.
4. On first run, builds the backend: `npm install` (which compiles the Rust
   GBT NAPI from `rust/gbt/`) followed by `npm run build`. Expect 5–10 min.
5. Starts the backend on `:8999` (logs at `./.local-mutinynet/logs/backend.log`).
6. On first run, runs `npm install` inside `frontend/` (Cypress binary
   skipped via `CYPRESS_INSTALL_BINARY=0`).
7. Starts the Angular dev server on `:4200` in the foreground.

When it's up: open <http://localhost:4200>.

`Ctrl-C` stops the frontend and tears down the backend + MariaDB.

## Configuration overrides

All connection details default to the `services.ducat-mutinynet` NixOS module
values. Override per invocation via env vars:

```bash
BITCOIN_RPC_PASS=hunter2 \
ELECTRUM_PORT=50002 \
VALIDATOR_PORT=4001 \
nix run .#start-mutinynet
```

Recognized variables:

| Variable             | Default                    |
| -------------------- | -------------------------- |
| `BITCOIN_RPC_HOST`   | `127.0.0.1`                |
| `BITCOIN_RPC_PORT`   | `19443`                    |
| `BITCOIN_RPC_USER`   | `user`                     |
| `BITCOIN_RPC_PASS`   | `Shiengoojiraihooh3Va`     |
| `ELECTRUM_HOST`      | `127.0.0.1`                |
| `ELECTRUM_PORT`      | `50001`                    |
| `VALIDATOR_PORT`     | `4000`                     |
| `BACKEND_PORT`       | `8999`                     |
| `FRONTEND_PORT`      | `4200`                     |

## State and logs

Everything writable lives in `./.local-mutinynet/`:

```
.local-mutinynet/
├── mysql/             # MariaDB data dir (gitignored)
├── mysql.sock         # Unix socket for the embedded mariadb
├── mysql.pid          # tracked so restarts kill the previous instance
├── backend.pid
└── logs/
    ├── mariadb.log
    └── backend.log
```

To start over from scratch: `rm -rf .local-mutinynet/ backend/node_modules
backend/dist backend/rust-gbt frontend/node_modules`.

## Without `nix run`

If you'd rather drive things by hand:

```bash
nix develop                      # gets node, npm, cargo, mariadb in PATH
./scripts/start-mutinynet.sh
```

## How the Ducat overlays talk to the validator

The frontend calls `http://localhost:4000/api/tx/{txid}` directly from the
browser (see `frontend/src/app/services/ducat-api.service.ts`). The validator
sets CORS to `Any` (`crates/ducat-validator-api/src/http/server/mod.rs`), so
no proxy is needed. If the validator is down or the txid isn't a Ducat tx, the
overlay silently no-ops.
