# NixOS module for the Ducat block explorer (mempool.space fork).
#
# Wires up:
#   - MariaDB with a `mempool` database (the upstream backend auto-runs
#     schema migrations on startup)
#   - Backend systemd service (Node.js, talks to Bitcoin Core RPC and
#     Esplora for block/tx data, exposes /api/v1/* on $backendPort)
#   - Nginx vhost serving the static frontend and proxying:
#       /              → static frontend bundle
#       /api/v1/*      → backend
#       /api/*         → Esplora (for spending-tx-by-outpoint links)
#       /ducat-api/*   → Ducat validator (vault data, rune registry)
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

  # Backend's mempool-config.json. Generated at activation time so the
  # secret-ish RPC password lives only in the systemd service env.
  configFile = pkgs.writeText "ducat-mempool-config.json" (builtins.toJSON {
    MEMPOOL = {
      NETWORK = cfg.network;
      BACKEND = "esplora";
      HTTP_PORT = cfg.backendPort;
      SPAWN_CLUSTER_PROCS = 0;
      API_URL_PREFIX = "/api/v1/";
      POLL_RATE_MS = 2000;
      CACHE_DIR = "${cfg.stateDir}/cache";
      INDEXING_BLOCKS_AMOUNT = 0;
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
      PASSWORD = cfg.bitcoindRpc.password;
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
      USERNAME = "mempool";
      PASSWORD = "mempool";
    };
    SYSLOG = { ENABLED = false; };
    STATISTICS = { ENABLED = true; };
    FIAT_PRICE = { ENABLED = false; };
  });
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
      password = mkOption { type = types.str; default = "Shiengoojiraihooh3Va"; };
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
    services.mysql = {
      enable = mkDefault true;
      package = mkDefault pkgs.mariadb;
      ensureDatabases = [ "mempool" ];
      ensureUsers = [{
        name = "mempool";
        ensurePermissions = { "mempool.*" = "ALL PRIVILEGES"; };
      }];
    };

    # NixOS' MariaDB module enforces socket-auth for ensureUsers; the
    # backend connects via socket too (see the SOCKET key in configFile),
    # so password isn't actually checked. We still set one in config for
    # completeness so a host:port fallback would work too.

    # ── Backend systemd service ───────────────────────────────────────
    systemd.services.ducat-mempool = {
      description = "Ducat block explorer backend (mempool.space)";
      after = [ "mysql.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        MEMPOOL_CONFIG_FILE = "${configFile}";
      };

      serviceConfig = {
        ExecStart = "${pkgs.nodejs_22}/bin/node --max-old-space-size=2048 ${cfg.backendPackage}/dist/index.js";
        Restart = "on-failure";
        RestartSec = 10;
        StateDirectory = "ducat-mempool";
        StateDirectoryMode = "0750";
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

        # Esplora — strip /api/ prefix to match esplora's routing.
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
