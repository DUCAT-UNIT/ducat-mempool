# NixOS module for the Ducat block explorer (mempool.space fork).
#
# Wires up:
#   - MariaDB with a `mempool` database (the upstream backend auto-runs
#     schema migrations on startup)
#   - Backend systemd service (Node.js, talks to Bitcoin Core RPC and
#     Esplora for block/tx data, exposes /api/v1/* on $backendPort)
#   - Nginx vhost serving the static frontend and proxying:
#       /                      → static frontend bundle
#       /api/v1/*              → backend
#       /api/txs/outspends     → backend (rewritten to /api/v1/...) — the
#                                batched-outspends route the frontend's
#                                transactions-list uses for the green/grey
#                                "spent" icons. Blockstream electrs 0.4.x
#                                doesn't expose the batch path; the backend
#                                fans it out to N per-tx esplora calls.
#       /api/*                 → Esplora (everything else: single tx/block
#                                lookups, /block/:hash/txid/:index used by
#                                the runestone decoder, address lookups…)
#       /ducat-api/*           → Ducat validator (vault data, rune registry)
#
# Used both for the bundled cloud deploy and for ad-hoc setups by
# importing this file and providing the package paths.
#
# Usage:
#
#   imports = [ /path/to/ducat-mempool/deploy/module.nix ];
#   services.ducat-mempool = {
#     enable = true;
#     hostName = "explorer-mutinynet.dev.ducatprotocol.com";
#     frontendPackage = ducat-mempool.packages.${system}.frontend;
#     backendPackage  = ducat-mempool.packages.${system}.backend;
#   };
#
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.ducat-mempool;

  # Backend's mempool-config.json as a function of the RPC password, so we can
  # render two variants: the literal password baked into the store (default),
  # or a placeholder template that ExecStartPre fills from `passwordFile` at
  # runtime - keeping the real secret out of the world-readable Nix store.
  useFile = cfg.bitcoindRpc.passwordFile != null;
  rpcPasswordPlaceholder = "@DUCAT_RPC_PASSWORD@";

  mkConfigJson = rpcPassword: builtins.toJSON {
    MEMPOOL = {
      NETWORK = cfg.network;
      BACKEND = "esplora";
      HTTP_PORT = cfg.backendPort;
      SPAWN_CLUSTER_PROCS = 0;
      API_URL_PREFIX = "/api/v1/";
      POLL_RATE_MS = 2000;
      CACHE_DIR = "${cfg.stateDir}/cache";
      # -1 = unlimited; matches upstream production/mempool-config.signet.json.
      # Required to enable Common.indexingEnabled() which gates the mining
      # routes (/api/v1/mining/pool/...). Without it, the per-block pool
      # logo URL on the homepage 404s.
      INDEXING_BLOCKS_AMOUNT = -1;
      BLOCKS_SUMMARIES_INDEXING = false;
      AUDIT = false;
      # Set to false: the Nix deploy ships a stub rust-gbt module, the
      # JS fallback path handles mempool block templates.
      RUST_GBT = false;
      STDOUT_LOG_MIN_PRIORITY = "info";
      ALLOW_UNREACHABLE = true;
      PRICE_UPDATES_PER_HOUR = 0;
    };
    CORE_RPC = {
      HOST = cfg.bitcoindRpc.host;
      PORT = cfg.bitcoindRpc.port;
      USERNAME = cfg.bitcoindRpc.user;
      PASSWORD = rpcPassword;
      TIMEOUT = 60000;
    };
    ESPLORA = {
      REST_API_URL = cfg.esploraRestUrl;
      UNIX_SOCKET_PATH = null;
      FALLBACK = [];
    };
    DATABASE = {
      ENABLED = true;
      HOST = "127.0.0.1";
      PORT = 3306;
      SOCKET = "/run/mysqld/mysqld.sock";
      DATABASE = "mempool";
      # Must match the systemd user — MariaDB's unix_socket plugin checks
      # the OS uid against the SQL username before accepting the connect.
      USERNAME = "ducat-mempool";
      PASSWORD = "";
      # Backend writes a pidlock to PID_DIR/mempool-<dbname>.pid; falls
      # back to __dirname (inside the read-only nix store) if unset.
      PID_DIR = cfg.stateDir;
    };
    SYSLOG = { ENABLED = false; };
    STATISTICS = { ENABLED = true; };
    FIAT_PRICE = { ENABLED = false; };
  };

  # No passwordFile: bake the (public-default or caller-supplied) password in.
  configFileStore = pkgs.writeText "ducat-mempool-config.json"
    (mkConfigJson cfg.bitcoindRpc.password);

  # passwordFile mode: a store template carrying only a placeholder, plus a
  # render step that injects the real password into a tmpfs copy under /run.
  configTemplate = pkgs.writeText "ducat-mempool-config.template.json"
    (mkConfigJson rpcPasswordPlaceholder);

  runtimeConfig = "/run/ducat-mempool/mempool-config.json";

  # Runs as the service user at every start; jq --rawfile keeps the secret out
  # of argv, and gsub trims any trailing newline the secret file may carry.
  renderConfig = pkgs.writeShellScript "ducat-mempool-render-config" ''
    set -euo pipefail
    umask 077
    ${pkgs.jq}/bin/jq --rawfile pw ${cfg.bitcoindRpc.passwordFile} \
      '.CORE_RPC.PASSWORD = ($pw | gsub("\\s+$"; ""))' \
      ${configTemplate} > ${runtimeConfig}
  '';
in {
  options.services.ducat-mempool = {
    enable = mkEnableOption "Ducat block explorer (mempool.space fork)";

    hostName = mkOption {
      type = types.str;
      example = "explorer-mutinynet.dev.ducatprotocol.com";
      description = "Public hostname; used as the nginx vhost and ACME cert subject.";
    };

    frontendPackage = mkOption {
      type = types.package;
      description = "Pre-built static frontend bundle (Angular dist output).";
    };

    backendPackage = mkOption {
      type = types.package;
      description = "Pre-built backend bundle (dist + node_modules).";
    };

    network = mkOption {
      type = types.enum [ "mainnet" "testnet" "testnet4" "signet" "regtest" ];
      default = "signet";
      description = "Bitcoin network — Mutinynet rides on signet.";
    };

    backendPort = mkOption {
      type = types.port;
      default = 8999;
      description = "Local bind port for the mempool backend HTTP API.";
    };

    bitcoindRpc = {
      host = mkOption { type = types.str; default = "127.0.0.1"; };
      port = mkOption { type = types.port; default = 19443; };
      user = mkOption { type = types.str; default = "user"; };
      password = mkOption {
        type = types.str;
        default = "Shiengoojiraihooh3Va";
        description = "RPC password baked into the store config. Ignored when passwordFile is set.";
      };
      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Path to a file holding the bitcoind RPC password, read at service
          start. Takes precedence over `password`. The service user must be
          able to read this file (e.g. via a shared group).
        '';
      };
    };

    esploraRestUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3000";
      description = "Esplora HTTP REST URL (Blockstream electrs).";
    };

    validatorApiUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:4000";
      description = "Ducat validator REST URL — proxied via /ducat-api/*.";
    };

    enableAcme = mkOption {
      type = types.bool;
      default = true;
      description = "Issue a Let's Encrypt cert for hostName.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/ducat-mempool";
      description = "Backend cache/state directory.";
    };
  };

  config = mkIf cfg.enable {
    # ── MariaDB ───────────────────────────────────────────────────────
    # ensureUsers grants unix_socket auth, which matches the OS user to
    # the SQL user name. Use "ducat-mempool" for both so the backend's
    # socket connect succeeds without a password.
    services.mysql = {
      enable = mkDefault true;
      package = mkDefault pkgs.mariadb;
      ensureDatabases = [ "mempool" ];
      ensureUsers = [{
        name = "ducat-mempool";
        ensurePermissions = { "mempool.*" = "ALL PRIVILEGES"; };
      }];
    };

    # ── Backend systemd service ───────────────────────────────────────
    systemd.services.ducat-mempool = {
      description = "Ducat block explorer backend (mempool.space)";
      after = [ "mysql.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        MEMPOOL_CONFIG_FILE = if useFile then runtimeConfig else "${configFileStore}";
      };

      serviceConfig = {
        # When passwordFile is set, render the config (with the secret injected).
        ExecStartPre = lib.optional useFile renderConfig;
        ExecStart = "${pkgs.nodejs_22}/bin/node --max-old-space-size=2048 ${cfg.backendPackage}/dist/index.js";
        Restart = "on-failure";
        RestartSec = 10;
        StateDirectory = "ducat-mempool";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "ducat-mempool";
        RuntimeDirectoryMode = "0700";
        DynamicUser = false;
        User = "ducat-mempool";
        Group = "ducat-mempool";
        WorkingDirectory = cfg.stateDir;
      };
    };

    users.users.ducat-mempool = {
      isSystemUser = true;
      group = "ducat-mempool";
    };
    users.groups.ducat-mempool = {};

    # Backend talks to mariadb via the socket; grant access.
    systemd.services.ducat-mempool.serviceConfig.SupplementaryGroups = [ "mysql" ];

    # ── Nginx vhost ────────────────────────────────────────────────────
    services.nginx = {
      enable = mkDefault true;
      recommendedTlsSettings = mkDefault true;
      recommendedProxySettings = mkDefault true;
      recommendedGzipSettings = mkDefault true;

      virtualHosts.${cfg.hostName} = {
        enableACME = cfg.enableAcme;
        forceSSL = cfg.enableAcme;

        # Static frontend bundle.
        root = "${cfg.frontendPackage}";
        locations."/".tryFiles = "$uri $uri/ /index.html =404";

        # Mempool's own backend (fees, mining, transactions stream, etc.).
        locations."/api/v1/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
        };
        # WebSocket for live mempool updates.
        locations."/api/v1/ws" = {
          proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
          proxyWebsockets = true;
        };

        # Surgical override: only the batched-outspends call goes through
        # the mempool backend (which fans out to N per-tx esplora calls).
        # Blockstream electrs 0.4.x has /tx/:id/outspend(s) but not the
        # plural /txs/outspends, and the frontend's transactions-list
        # relies on it for the green/grey "spent" icons. Exact-match
        # `=` so it wins over the general `/api/` prefix that follows.
        locations."= /api/txs/outspends" = {
          proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
          extraConfig = ''
            rewrite ^/api/(.*) /api/v1/$1 break;
          '';
        };

        # Everything else under /api/ → Esplora. The mempool backend is a
        # near-superset of the esplora REST API but misses a few esplora-
        # only routes (notably /block/:hash/txid/:index, used by the
        # runestone decoder to look up rune etchings by ID). Sending the
        # general traffic to esplora keeps those working; the override
        # above handles the one path esplora itself can't answer.
        locations."/api/" = {
          proxyPass = "${cfg.esploraRestUrl}";
          extraConfig = ''
            rewrite ^/api/(.*) /$1 break;
          '';
        };

        # Ducat validator — strip /ducat-api/ prefix so /ducat-api/api/X
        # forwards as /api/X to the validator.
        locations."/ducat-api/" = {
          proxyPass = "${cfg.validatorApiUrl}";
          extraConfig = ''
            rewrite ^/ducat-api/(.*) /$1 break;
          '';
        };
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.enableAcme [ 80 443 ];
  };
}
