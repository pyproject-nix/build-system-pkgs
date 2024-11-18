# build-system-pkgs

Python dependency managers such as [`uv`](https://docs.astral.sh/uv/) [don't lock PEP-517 build-systems](https://github.com/astral-sh/uv/issues/5190), and [`pyproject.nix`'s builders](https://nix-community.github.io/pyproject.nix/build.html) will soon come without a package set.

This repository exists to be used as a base repository for [overriding](https://nix-community.github.io/pyproject.nix/builders/overriding.html) build-system dependencies.
Without a base package set you'd have to include build-systems in your project.

Auto-updates on a weekly basis. Automated testing of the package set is done for all stable CPython interpreters in the Nixpkgs unstable channel.
