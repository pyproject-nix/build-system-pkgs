{
  description = "Pyproject.nix base package set";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
    }:
    let
      inherit (nixpkgs) lib;
      npins = import ./npins;

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      mkOverlay = import ./default.nix { inherit uv2nix pyproject-nix lib; };

    in
    {
      overlays = {
        default = self.overlays.sdist;
        sdist = mkOverlay { sourcePreference = "sdist"; };
        wheel = mkOverlay { sourcePreference = "wheel"; };
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) callPackage;
          inherit (lib) nameValuePair;

          interpreters =  lib.filterAttrs (
            n: drv: lib.hasPrefix "python3" n && n != "python3Minimal" && !isPre drv.version
          ) pkgs.pythonInterpreters;

          mkCheck =
            sourcePreference: prefix: python:
            let
              baseSet = callPackage pyproject-nix.build.packages {
                inherit python;
              };
              pythonSet = baseSet.overrideScope (mkOverlay {
                inherit sourcePreference;
              });

              venv = pythonSet.mkVirtualEnv "${prefix}-venv" {
                pyproject-nix-build-system-pkgs = [ ];
              };
            in
            # Basic smoke tests
            pkgs.runCommand "${prefix}-venv-test"
              {
                nativeBuildInputs = [ venv ];
              }
              ''
                python -c "import setuptools"
                python -c "import maturin"
                ln -s ${venv} $out
              '';

          # Filter out Python pre-releases from testing
          isPre = version: (pyproject-nix.lib.pep440.parseVersion version).pre != null;

        in
          (
            let
              mkCheck' = mkCheck "sdist";
            in
            lib.mapAttrs' (name: python: nameValuePair "${name}-pref-sdist" (mkCheck' name python)) interpreters
          ) // (
            let
              mkCheck' = mkCheck "wheel";
            in
            lib.mapAttrs' (name: python: nameValuePair "${name}-pref-wheel" (mkCheck' name python)) interpreters
          )
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.callPackage ./shell.nix { };
        }
      );

      githubActions = (import npins.nix-github-actions).mkGithubMatrix {
        checks = {
          inherit (self.checks) x86_64-linux aarch64-darwin;
        };
      };

    };
}
