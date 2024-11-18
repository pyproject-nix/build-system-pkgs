{
  uv2nix,
  pyproject-nix,
  lib,
}:
let
  inherit (pyproject-nix.build.lib.resolvers) resolveNonCyclic;

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "sdist";
  };

  # Supplement build-system metadata
  buildSystems = lib.importTOML ./build-systems.toml;

  # Build-systems overlay
  buildSystemOverrides =
    final: prev:
    lib.mapAttrs (
      name: spec:
      prev.${name}.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem spec;
      })
    ) buildSystems;

  # Manually created overrides
  overrides =
    final: prev:
    let
      pkgs = final.callPackage ({ pkgs }: pkgs) { };
      inherit (pkgs) stdenv;
    in
    {
      hatchling = prev.hatchling.overrideAttrs (old: {
        nativeBuildInputs =
          old.nativeBuildInputs
          ++ final.resolveBuildSystem final.hatchling.passthru.dependencies;
      });

      flit-scm = prev.flit-scm.overrideAttrs (old: {
        nativeBuildInputs =
          old.nativeBuildInputs
          ++ final.resolveBuildSystem final.flit-scm.passthru.dependencies;
      });

      cffi = prev.cffi.overrideAttrs (old: {
        buildInputs = [
          pkgs.libffi
        ];
      });

      numpy = prev.numpy.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.pkg-config
          pkgs.blas
          pkgs.lapack
        ];
      });

      # Use stub from nixpkgs
      cmake =
        let
          python3Packages = pkgs.python3Packages;
        in
        stdenv.mkDerivation {
          inherit (python3Packages.cmake)
            pname
            version
            src
            meta
            postUnpack
            setupHooks
            ;

          nativeBuildInputs =
            [
              final.pyprojectHook
            ]
            ++ final.resolveBuildSystem {
              flit-core = [ ];
            };
        };

      # Use stub from nixpkgs
      ninja =
        let
          python3Packages = pkgs.python3Packages;
        in
        stdenv.mkDerivation {
          inherit (python3Packages.ninja)
            pname
            version
            src
            meta
            postUnpack
            setupHook
            preBuild
            ;

          nativeBuildInputs =
            [
              final.pyprojectHook
            ]
            ++ final.resolveBuildSystem {
              flit-core = [ ];
            };
        };

      # Use maturin sources from nixpkgs because of Cargo dependencies
      maturin = stdenv.mkDerivation {
        inherit (pkgs.maturin)
          pname
          version
          cargoDeps
          src
          meta
          ;

        # Dependency metadata from uv.lock
        inherit (prev.maturin) passthru;

        nativeBuildInputs =
          [
            pkgs.rustPlatform.cargoSetupHook
            final.pyprojectHook
            pkgs.cargo
            pkgs.rustc
          ]
          ++ final.resolveBuildSystem {
            setuptools = [ ];
            wheel = [ ];
            tomli = [ ];
            setuptools-rust = [ ];
          };
      };
    };

  # Work around a much larger set of bootstrap dependencies for Python 3.9.
  # TODO: Make a nicer mechanism for bootstrap hermeticity
  python39Fixups =
    final: prev:
    if builtins.compareVersions "3.9" prev.python.pythonVersion <= 0 then
      lib.genAttrs [
        "importlib-metadata"
        "setuptools"
        "setuptools-scm"
        "typing-extensions"
        "zipp"
        "setuptools"
      ] (
        name:
        prev.${name}.override {
          pyprojectHook = final.pyprojectBootstrapHook;
        }
      )
    else
      { };

  # Create a resolveBuildSystem function in the same way as pyproject.nix with fallback behaviour.
  # Uses the dependency names of this project as the memoisation names.
  mkResolveBuildSystem =
    set:
    let
      resolveNonCyclic' = resolveNonCyclic (lib.attrNames workspace.deps.default) set;
      # Implement fallback behaviour in case of empty build-system
      fallbackSystems = map (name: set.${name}) (resolveNonCyclic' {
        setuptools = [ ];
        wheel = [ ];
      });
    in
    spec: if spec != { } then map (name: set.${name}) (resolveNonCyclic' spec) else fallbackSystems;

  memoiseBuildSystems = final: prev: {
    resolveBuildSystem = mkResolveBuildSystem final.pythonPkgsBuildHost;
  };

in
lib.composeManyExtensions [
  overlay
  buildSystemOverrides
  overrides
  python39Fixups
  memoiseBuildSystems
]
