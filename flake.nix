{
  description = "Ducat mempool.space block explorer fork";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nodejs = pkgs.nodejs_22;
        # Backend deps: rust toolchain + a wrapped C compiler (cargo's NAPI build
        # links via `cc`), mariadb, openssl/pkg-config for native node modules.
        runtimeDeps = [
          nodejs
          pkgs.nodePackages.npm
          pkgs.cargo
          pkgs.rustc
          pkgs.stdenv.cc
          pkgs.mariadb
          pkgs.openssl
          pkgs.pkg-config
          pkgs.python3
          pkgs.curl
          pkgs.coreutils
          pkgs.bash
          pkgs.gnused
          pkgs.gnugrep
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = runtimeDeps;
        };

        apps.start-mutinynet = {
          type = "app";
          program = toString (pkgs.writeShellScript "start-mutinynet" ''
            export PATH=${pkgs.lib.makeBinPath runtimeDeps}:$PATH
            exec ${./scripts/start-mutinynet.sh} "$@"
          '');
        };

        # ── Frontend bundle ────────────────────────────────────────────
        # Static Angular build. nginx serves this directly under the
        # explorer vhost.
        packages.frontend = pkgs.buildNpmPackage {
          pname = "ducat-mempool-frontend";
          version = "3.4-dev";
          src = ./frontend;

          nodejs = nodejs;

          # Pin to the lockfile's vendored deps. Recompute by setting to
          # lib.fakeHash and rebuilding when frontend/package-lock.json
          # changes.
          npmDepsHash = "sha256-jvlGqXWIzqnZgvA0rgQ8hc4+ewtlMerVSeKv21Qhgnw=";

          # Cypress installer downloads its binary at install time —
          # bypass it; we don't run e2e tests during the deploy build.
          npmFlags = [ "--ignore-scripts" ];
          env.CYPRESS_INSTALL_BINARY = "0";

          buildPhase = ''
            runHook preBuild
            node generate-themes.js
            node generate-config.js
            npx ng build --configuration production
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r dist/mempool/browser/. $out/
            runHook postInstall
          '';
        };

        # ── Backend bundle ─────────────────────────────────────────────
        # Compiled TypeScript dist + node_modules. We swap in a stub for
        # `rust-gbt` (a NAPI Rust addon) and rely on the JS fallback path
        # at runtime — set MEMPOOL.RUST_GBT=false in the backend config.
        packages.backend = pkgs.buildNpmPackage {
          pname = "ducat-mempool-backend";
          version = "3.4-dev";
          src = ./backend;

          nodejs = nodejs;

          npmDepsHash = "sha256-yzSmJbK2IqBtwaWItPsQpYKRDDiiDc9MImi4pQv8QM8=";

          # Skip backend/preinstall (which tries to build the Rust NAPI)
          # and any other lifecycle hooks. We provide rust-gbt as a stub.
          npmFlags = [ "--ignore-scripts" ];

          # Drop the stub into ./rust-gbt/ so npm install resolves the
          # `"rust-gbt": "file:./rust-gbt"` dependency without compiling.
          preBuild = ''
            rm -rf rust-gbt
            cp -r rust-gbt-stub rust-gbt
            chmod -R u+w rust-gbt
          '';

          buildPhase = ''
            runHook preBuild
            ./node_modules/typescript/bin/tsc -p tsconfig.build.json
            cp ./src/tasks/price-feeds/mtgox-weekly.json ./dist/tasks/
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r dist $out/dist
            cp -r node_modules $out/node_modules
            # The package.json declares "rust-gbt": "file:./rust-gbt", so npm
            # symlinks node_modules/rust-gbt → ../rust-gbt. Bring the stub
            # into $out so that link doesn't dangle.
            cp -r rust-gbt $out/rust-gbt
            cp package.json $out/
            runHook postInstall
          '';
        };

        # Lightweight check: install deps + typecheck only
        checks.frontend-typecheck = pkgs.stdenv.mkDerivation {
          pname = "ducat-mempool-frontend-typecheck";
          version = "3.4-dev";
          src = ./frontend;

          nativeBuildInputs = [ nodejs ];

          buildPhase = ''
            export HOME=$TMPDIR
            npm ci --ignore-scripts || npm install --ignore-scripts
            node generate-themes.js
            node generate-config.js
            npx tsc --noEmit
          '';

          installPhase = ''
            mkdir -p $out
            echo "typecheck passed" > $out/result
          '';
        };
      }
    )) // {
      # ── NixOS module ───────────────────────────────────────────────
      # Importable into a colmena/nixos config; pre-wires the explorer
      # packages from this flake.
      nixosModules.ducat-mempool = { pkgs, lib, ... }: {
        imports = [ ./deploy/module.nix ];

        services.ducat-mempool = {
          frontendPackage = lib.mkDefault
            self.packages.${pkgs.stdenv.hostPlatform.system}.frontend;
          backendPackage = lib.mkDefault
            self.packages.${pkgs.stdenv.hostPlatform.system}.backend;
        };
      };
    };
}
