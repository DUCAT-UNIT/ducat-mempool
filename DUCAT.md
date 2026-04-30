# Ducat block explorer — local development

This fork of [mempool.space](https://mempool.space) adds Ducat protocol overlays
(vault banner, per-output asset badges) to the transaction page. This document
describes how to run the explorer locally against a Mutinynet stack.

## Prerequisites

You need these Mutinynet services running on `localhost`:

| Service             | Default port | Provided by                                      |
| ------------------- | ------------ | ------------------------------------------------ |
| Bitcoin Core RPC    | `19443`      | `services.bitcoind-mutinynet` in validator-rs    |
| Esplora (REST)      | `3000`       | `services.esplora-mutinynet` in validator-rs     |
| Electrs (Electrum)  | `50001`      | `services.electrs-mutinynet` (alternative)       |
| Ducat validator     | `4000`       | `services.ducat-mutinynet` in validator-rs       |

The script defaults to the **Esplora** backend (`MEMPOOL_BACKEND=esplora`)
because it indexes spending-tx-by-outpoint, which lights up the per-output
red-arrow links so you can navigate forward through the transaction graph.
The Electrum backend can only report spent/unspent.

Either Esplora *or* Electrs is enough — you don't need both. Both NixOS
modules share the same `services.bitcoind-mutinynet` Bitcoin Core node, so
they coexist if you want to keep them both around.

The validator-rs repo exposes the NixOS module `services.ducat-mutinynet` at
`deploy/mutiny/`, which imports all of the above. The defaults (RPC user
`user`, password `Shiengoojiraihooh3Va`, ports above) are what
`start-mutinynet.sh` expects out of the box.

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
| `MEMPOOL_BACKEND`    | `esplora` (or `electrum`)  |
| `ESPLORA_HOST`       | `127.0.0.1`                |
| `ESPLORA_PORT`       | `3000`                     |
| `ELECTRUM_HOST`      | `127.0.0.1`                |
| `ELECTRUM_PORT`      | `50001`                    |
| `VALIDATOR_PORT`     | `4000`                     |
| `BACKEND_PORT`       | `8999`                     |
| `FRONTEND_PORT`      | `4200`                     |

To switch to the Electrum backend (e.g. if Esplora is still indexing):

```bash
MEMPOOL_BACKEND=electrum nix run .#start-mutinynet
```

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
