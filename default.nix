{
  uv2nix,
  pyproject-nix,
  lib,
}:
let
  mkOverlay = import ./overlay.nix { inherit uv2nix pyproject-nix lib; };
  self = {
    overlays = builtins.removeAttrs self [ "overlays" ]; # To provide exactly the same API whether used with flakes or not
    sdist = mkOverlay { sourcePreference = "sdist"; };
    wheel = mkOverlay { sourcePreference = "wheel"; };
    default = self.sdist;
  };
in
self
