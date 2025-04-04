{
  uv2nix,
  pyproject-nix,
  lib,
}:
let
  mkOverlay = import ./overlay.nix { inherit uv2nix pyproject-nix lib; };
in
rec {
  sdist = mkOverlay { sourcePreference = "sdist"; };
  wheel = mkOverlay { sourcePreference = "wheel"; };
  default = sdist;
}
