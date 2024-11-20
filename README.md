# build-system-pkgs

Python dependency managers such as [`uv`](https://docs.astral.sh/uv/) [does not lock PEP-517 build-systems](https://github.com/astral-sh/uv/issues/5190), and [`pyproject.nix`'s builders](https://nix-community.github.io/pyproject.nix/build.html) does not come with a Python package set.

This repository exists to be used as a base repository for [overriding](https://nix-community.github.io/pyproject.nix/builders/overriding.html) build-system dependencies.
Without a base package set you'd have to include build-systems to your project dependencies.

Auto-updates on a weekly basis. Automated testing of the package set is done for all stable CPython interpreters in the Nixpkgs unstable channel.

## Migration

Add the overlay [to your project](https://github.com/pyproject-nix/uv2nix/pull/63/commits/f2f4d5661658de3efecf99f4249c8d2c308b6aff).

## Binary cache

https://app.cachix.org/cache/pyproject-nix
