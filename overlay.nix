{
  uv2nix,
  pyproject-nix,
  lib,
}:
let
  inherit (pyproject-nix.build.lib.resolvers) resolveNonCyclic;

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

  # Supplement build-system metadata
  buildSystems = lib.importTOML ./build-systems.toml;

  # Build-systems overlay
  buildSystemOverrides =
    final: prev:
    lib.mapAttrs (
      name: spec:
      let
        drv = prev.${name};
        format = drv.passthru.format;
      in
        # Only add build system if we're building from source
        if format == "pyproject" then
          drv.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem spec;
          })
        else
          drv
    ) buildSystems;

  # Various fixups to only apply when building from source
  sdistFixups =
    final: prev:
    let
      inherit (prev) stdenv;
      inherit (final) pkgs;
    in
    lib.mapAttrs (
      name: overriden:
      let
        drv = prev.${name};
        format = drv.passthru.format;
      in
        # Only add build system if we're building from source
        if format == "pyproject" then
          overriden
        else
          drv
    ) {

      pydantic-core = prev.pydantic-core.overrideAttrs(old: {
        inherit (pkgs.python3Packages.pydantic-core) name pname src version cargoDeps;
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.rustPlatform.cargoSetupHook
          pkgs.cargo
          pkgs.rustc
        ];
      });

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

      grpcio = prev.grpcio.overrideAttrs (old: {
        preBuild =
          ''
            export GRPC_PYTHON_BUILD_EXT_COMPILER_JOBS="$NIX_BUILD_CORES"
            if [ -z "$enableParallelBuilding" ]; then
              GRPC_PYTHON_BUILD_EXT_COMPILER_JOBS=1
            fi
          ''
          + lib.optionalString stdenv.hostPlatform.isDarwin ''
            unset AR
          '';

        buildInputs = (old.buildInputs or [ ]) ++ [
          pkgs.c-ares
          pkgs.openssl
          pkgs.zlib
        ];

        GRPC_BUILD_WITH_BORING_SSL_ASM = "";
        GRPC_PYTHON_BUILD_SYSTEM_OPENSSL = 1;
        GRPC_PYTHON_BUILD_SYSTEM_ZLIB = 1;
        GRPC_PYTHON_BUILD_SYSTEM_CARES = 1;
      });

      numpy = prev.numpy.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.pkg-config
          pkgs.blas
          pkgs.lapack
        ];
      });

      # Use maturin sources from nixpkgs because of Cargo dependencies
      maturin = final.callPackage (
        {
          stdenv,
          pkgs,
        }:
        stdenv.mkDerivation {
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
        }
      ) { };

      pdm-backend = prev.pdm-backend.overrideAttrs (
        old: lib.optionalAttrs (final.python.pythonOlder "3.10") {
          nativeBuildInputs =
            old.nativeBuildInputs
            ++ (final.resolveBuildSystem {
              importlib-metadata = [ ];
            });
        }
      );

      # Libcst is used for editable packages patching, and is a rust package
      # To avoid depending on wheels or resorting to IFD inherit sources from nixpkgs.
      libcst = prev.libcst.overrideAttrs(old: {
        inherit (pkgs.python3Packages.libcst) name pname src version cargoDeps cargoRoot;
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.rustPlatform.cargoSetupHook
          pkgs.cargo
          pkgs.rustc
        ];
      });

      oldest-supported-numpy = final.callPackage ({ stdenv }: stdenv.mkDerivation {
        inherit (pkgs.python3Packages.oldest-supported-numpy) name pname version src;
        passthru.dependencies = {
          numpy = [ ];
        };
      }) { };
    };

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

  # Manually created overrides applied regardless of build type
  overrides =
    final: prev:
    let
      pkgs = final.callPackage ({ pkgs }: pkgs) { };
    in
    {
      # Use setup hook from nixpkgs (forces cython regen)
      cython = prev.cython.overrideAttrs (old: {
        inherit (pkgs.python3Packages.cython) setupHook;
      });

      # Use stub from nixpkgs
      cmake = final.callPackage (
        { stdenv, python3Packages }:
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
        }
      ) { };

      # Use setup hook from nixpkgs (sets up build)
      meson-python = prev.meson-python.overrideAttrs (old: {
        inherit (pkgs.python3Packages.meson-python) setupHooks;
      });

      # Use setup hook from nixpkgs (pretends version)
      setuptools-scm = prev.setuptools-scm.overrideAttrs (old: {
        inherit (pkgs.python3Packages.setuptools-scm) setupHook;
      });

      # Use setup hook from nixpkgs (pretends version)
      poetry-dynamic-versioning = prev.poetry-dynamic-versioning.overrideAttrs (old: {
        inherit (pkgs.python3Packages.poetry-dynamic-versioning) setupHook;
      });

      # Use setup hook from nixpkgs (pretends version)
      pdm-backend = prev.pdm-backend.overrideAttrs (
        old: {
          inherit (pkgs.python3Packages.pdm-backend) setupHook;
        }
      );

      # Use setup hook from nixpkgs (sets up build)
      pkgconfig = prev.pkgconfig.overrideAttrs (old: {
        inherit (pkgs.pkg-config)
          setupHooks
          wrapperName
          suffixSalt
          targetPrefix
          baseBinName
          ;
      });

      cffi = prev.cffi.overrideAttrs (old: {
        buildInputs = [
          pkgs.libffi
        ];
      });

      # Use stub from nixpkgs
      ninja = final.callPackage (
        { stdenv, python3Packages }:
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
        }
      ) { };

      # Adapt setup hook from nixpkgs
      whool = prev.whool.overrideAttrs (old: {
        setupHook = pkgs.writeText "whool-setup-hook.sh" ''
          # Avoid using git to auto-bump the addon version
          # DOCS https://github.com/sbidoul/whool/?tab=readme-ov-file#configuration
          whool-post-version-strategy-hook() {
              # DOCS https://stackoverflow.com/a/13864829/1468388
              if [ -z ''${WHOOL_POST_VERSION_STRATEGY_OVERRIDE+x} ]; then
                  echo Setting WHOOL_POST_VERSION_STRATEGY_OVERRIDE to none
                  export WHOOL_POST_VERSION_STRATEGY_OVERRIDE=none
              fi
          }

          preBuildHooks+=(whool-post-version-strategy-hook)
        '';
      });

    };

in
{ sourcePreference }:
lib.composeManyExtensions [
  (workspace.mkPyprojectOverlay { inherit sourcePreference; })
  buildSystemOverrides
  sdistFixups
  overrides
  memoiseBuildSystems
]
