{ pkgs }:
let
  ipAddress = pkgs.fetchurl {
    url = "https://registry.npmjs.org/ip-address/-/ip-address-10.7.4.tgz";
    hash = "sha512-DWBMKyeM25D70nrIiTkgQth59/G+naKOTep6huF9j+GmeK3DMD60Zvxg5d5qQnz+38AHgou6ean2LECX+lrKDg==";
  };
in
pkgs.symlinkJoin {
  name = "nodejs-${pkgs.nodejs_22.version}-security-npm";
  paths = [ pkgs.nodejs_22 ];
  postBuild = ''
    rm -rf "$out/lib/node_modules/npm"
    mkdir -p "$out/lib/node_modules"
    cp -rL ${pkgs.nodejs_22}/lib/node_modules/npm "$out/lib/node_modules/npm"
    chmod -R u+w "$out/lib/node_modules/npm"
    target="$out/lib/node_modules/npm/node_modules/ip-address"
    rm -rf "$target"
    mkdir -p "$target"
    tar -xzf ${ipAddress} --strip-components=1 -C "$target"
    rm "$out/bin/npm" "$out/bin/npx"
    ln -s ../lib/node_modules/npm/bin/npm-cli.js "$out/bin/npm"
    ln -s ../lib/node_modules/npm/bin/npx-cli.js "$out/bin/npx"
    ${pkgs.nodejs_22}/bin/node -e \
      "const {Address4,Address6}=require(process.argv[1]);new Address4('127.0.0.1');new Address6('::1');require(process.argv[2])" \
      "$target" "$out/lib/node_modules/npm/node_modules/socks"
    "$out/bin/npm" --version
  '';
}
