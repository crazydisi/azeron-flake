# Azeron Software NixOS Flake

[![CI](https://github.com/crazydisi/azeron-flake/actions/workflows/ci.yml/badge.svg)](https://github.com/crazydisi/azeron-flake/actions/workflows/ci.yml)
[![Update](https://github.com/crazydisi/azeron-flake/actions/workflows/update.yml/badge.svg)](https://github.com/crazydisi/azeron-flake/actions/workflows/update.yml)
[![Release](https://img.shields.io/github/v/release/crazydisi/azeron-flake)](https://github.com/crazydisi/azeron-flake/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL_3.0-blue.svg)](./LICENSE)

A Nix flake for installing **[Azeron Software](https://azeron.com/pages/software)** — the keypad configurator for Azeron devices (Cyborg, Cyro, Classic, Keyzen) — on NixOS, Home Manager, or any system with Nix.

Upstream ships a single Linux AppImage (officially marked "experimental", tested on Arch / SteamOS) and no `.deb`, `.rpm`, or Flatpak. This flake wraps that AppImage with `appimageTools.wrapType2`, registers a `.desktop` entry plus icon, and pins the binary by SRI hash for `x86_64-linux`. New upstream versions are picked up automatically — see [Automatic updates and releases](#automatic-updates-and-releases) below.

## Features

- **Declarative install** — no manual `chmod +x`, no rogue AppImage in `~/Downloads`
- **First-class outputs** — `packages`, `apps`, `overlays`, `nixosModules`, `homeManagerModules`, `checks`, `formatter`, `devShells`
- **Real desktop integration** — 256×256 icon (extracted from the AppImage) and `.desktop` entry land in the correct hicolor paths
- **Reproducible** — every commit pins a specific AppImage by SHA-256
- **CI-verified** — every push runs `nix flake check`, `nix fmt --check`, and a real `nix build`
- **Auto-updated** — a daily job bumps to new upstream releases and publishes a tagged GitHub release

## Quick start

Try it once without installing:

```sh
nix run github:crazydisi/azeron-flake
```

> Azeron Software ships as a closed-source Electron AppImage and the derivation is marked `meta.license = unfree`. The flake configures `allowUnfree` internally on its own `pkgs` instance, so consumers don't need to set anything to evaluate or build it. Adding this flake as an input is implicit consent.

## Install

Replace `github:crazydisi/azeron-flake` with your own fork if you maintain one.

### NixOS module (recommended)

Adds the package and a typed option set under `programs.azeron-software`.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    azeron.url = "github:crazydisi/azeron-flake";
  };

  outputs = { self, nixpkgs, azeron, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        azeron.nixosModules.default
        ({ ... }: {
          programs.azeron-software.enable = true;
        })
      ];
    };
  };
}
```

### Home Manager module

```nix
{
  inputs.azeron.url = "github:crazydisi/azeron-flake";

  outputs = { self, home-manager, azeron, ... }: {
    homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
      modules = [
        azeron.homeManagerModules.default
        ({ ... }: {
          programs.azeron-software.enable = true;
        })
      ];
    };
  };
}
```

### Overlay (add to your nixpkgs)

```nix
{
  nixpkgs.overlays = [ inputs.azeron.overlays.default ];
  environment.systemPackages = [ pkgs.azeron-software ];
}
```

### Plain `environment.systemPackages`

```nix
environment.systemPackages = [
  inputs.azeron.packages.${pkgs.system}.default
];
```

### Ad-hoc shell

```sh
nix shell github:crazydisi/azeron-flake
```

## USB / udev rules

This flake packages the **GUI configurator only**. Talking to an Azeron device (and especially flashing firmware over DFU) requires a udev rule that grants your user access to the USB device. Upstream does not publish an official rules file; the most permissive snippet that works for current Azeron hardware is roughly:

```nix
services.udev.extraRules = ''
  # Azeron keypads (configurator + DFU)
  SUBSYSTEM=="usb", ATTRS{idVendor}=="16d0", MODE="0666"
  SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0666"
'';
```

Add that (or a tighter equivalent) to your system configuration if the app cannot detect your device. The flake intentionally does not enable this for you — udev rules are system-wide and you should audit them yourself.

## Unfree status

The wrapped binary is closed-source (`meta.license = unfree`). To avoid forcing every consumer to fiddle with `allowUnfree`, the flake imports its own `nixpkgs` with `config.allowUnfree = true;` internally. Practical implications:

- `nix run`, `nix shell`, `nix build`, and consuming the flake as an input all work with no extra config.
- Your host's `nixpkgs.config.allowUnfree` setting is independent — it stays whatever you have it set to.
- Adding this flake as an input is implicit consent to install the unfree binary.

## Pinning a release

Every packaged upstream version gets a tag `vX.Y.Z` and a [GitHub release](https://github.com/crazydisi/azeron-flake/releases). Pin one instead of tracking `main`:

```nix
inputs.azeron.url = "github:crazydisi/azeron-flake/v2.0.3";
```

## Automatic updates and releases

| What | Workflow | Schedule | Release? |
| --- | --- | --- | --- |
| New Azeron Software version | [update.yml](./.github/workflows/update.yml) → `upstream` | daily | yes, `vX.Y.Z` |
| nixpkgs bump in `flake.lock` | [update.yml](./.github/workflows/update.yml) → `flake-lock` | weekly (Mon) | no |

Both open a PR with auto-merge enabled; it merges once CI is green. When a merge changes [sources.json](./sources.json), [release.yml](./.github/workflows/release.yml) tags the commit and publishes the release.

Version detection reads upstream's electron-builder feed (`live/latest.yml`) and falls back to scraping the download page. `live/latest-linux.yml` is unusable — upstream uploaded the AppImage itself under that name.

### One-time repository setup

1. Create a fine-grained PAT scoped to this repo with **Contents: read & write** and **Pull requests: read & write**, and store it as the Actions secret `UPDATE_TOKEN`. (PRs opened with the default `GITHUB_TOKEN` don't trigger CI.)
2. Settings → General → enable **Allow auto-merge**.
3. Settings → Branches → protect `main`, require the status check **`check`** (from CI).
4. Settings → Actions → General → Workflow permissions: **Read and write**.

### Manual bump

```sh
scripts/update.sh          # latest upstream
scripts/update.sh 2.0.4    # specific version
nix build .#packages.x86_64-linux.azeron-software
```

The script rewrites [sources.json](./sources.json) (version, release date, URL, SRI hash). It tries the known upstream file-name schemes in order, since they have changed before (`Azeron+Software-X.Y.Z.AppImage` → `Azeron-Software-vX.Y.Z.AppImage`).

## Development

```sh
nix develop          # nixpkgs-fmt, jq, gnused, curl
nix fmt              # format flake.nix
nix flake check
nix build .#packages.x86_64-linux.azeron-software
nix run
```

## Repository layout

```text
.
├── flake.nix                       # package, overlay, modules, checks, formatter, devShell
├── sources.json                    # pinned upstream version, URL, SRI hash
├── scripts/update.sh               # bumps sources.json to the latest upstream release
├── azeron.png                      # 256×256 icon (extracted from upstream AppImage)
├── LICENSE                         # GPL-3.0 (wrapper code only)
├── README.md
└── .github/workflows/
    ├── ci.yml                      # build + fmt + flake check on every push
    ├── update.yml                  # scheduled upstream + flake.lock update PRs (auto-merge)
    └── release.yml                 # tag + GitHub release when sources.json changes
```

## License

The Nix expressions and CI glue in this repo are GPL-3.0 (see [LICENSE](./LICENSE)). Azeron Software itself is governed by [Azeron's own terms](https://azeron.com/pages/software) — this repo only pins a public download URL and the wrapping logic, never the binary.
