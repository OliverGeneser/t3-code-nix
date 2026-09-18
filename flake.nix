{
  description = "T3 Code release and nightly packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      versions = builtins.fromJSON (builtins.readFile ./versions.json);
      mkPackages = system:
        let
          pkgs = import nixpkgs { inherit system; };
          mkT3Code = channel: pkgs.callPackage ./package.nix {
            inherit channel;
            release = versions.${channel};
          };
          latest = mkT3Code "latest";
          nightly = mkT3Code "nightly";
        in
        {
          default = latest;
          inherit latest nightly;
          t3code = latest;
          t3code-nightly = nightly;
        };
    in
    {
      packages = forAllSystems mkPackages;

      apps = forAllSystems (system:
        let
          packages = mkPackages system;
          mkApp = package: program: {
            type = "app";
            program = "${package}/bin/${program}";
          };
        in
        {
          default = mkApp packages.latest "t3code";
          latest = mkApp packages.latest "t3code";
          nightly = mkApp packages.nightly "t3code-nightly";
        });

      overlays.default = final: _prev: {
        t3code = final.callPackage ./package.nix {
          channel = "latest";
          release = versions.latest;
        };
        t3code-nightly = final.callPackage ./package.nix {
          channel = "nightly";
          release = versions.nightly;
        };
      };
    };
}
