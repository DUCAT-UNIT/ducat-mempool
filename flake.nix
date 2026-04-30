{
  description = "Ducat mempool.space block explorer fork";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
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
          pkgs.stdenv.cc      # provides `cc` for cargo's linker
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

        packages.frontend = pkgs.buildNpmPackage {
          pname = "ducat-mempool-frontend";
          version = "3.4-dev";
          src = ./frontend;

          nodejs = nodejs;

          npmDepsHash = "";

          # Generate config/themes before build, then compile TS only (no i18n localize)
          buildPhase = ''
            node generate-themes.js
            node generate-config.js
            npx ng build --configuration production
          '';

          installPhase = ''
            mkdir -p $out
            cp -r dist/mempool/browser $out/
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
    );
}
