{
  description = "Pyproject.nix base package set";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:adisbladis/uv2nix";
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

      overlay = import ./overlay.nix { inherit uv2nix pyproject-nix lib; };

    in
    {
      overlays.default = overlay;

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) callPackage;

          mkCheck =
            prefix: python:
            let
              baseSet = callPackage pyproject-nix.build.packages {
                inherit python;
              };
              pythonSet = baseSet.overrideScope overlay;

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
        lib.mapAttrs mkCheck (
          lib.filterAttrs (
            n: drv: lib.hasPrefix "python3" n && n != "python3Minimal" && !isPre drv.version
          ) pkgs.pythonInterpreters
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
