{
  pkgs ?
    let
      flakeLock = builtins.fromJSON (builtins.readFile ./flake.lock);
      inherit (flakeLock.nodes.nixpkgs) locked;
    in
    import (builtins.fetchTree locked) { },
}:

pkgs.mkShell {
  packages = [
    (pkgs.onlyBin pkgs.uv)
    pkgs.python3
    pkgs.npins
  ];
  env.UV_NO_SYNC = 1;
}
