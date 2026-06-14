# Azeron Software NixOS Flake

[![CI](https://github.com/crazydisi/azeron-flake/actions/workflows/ci.yml/badge.svg)](https://github.com/crazydisi/azeron-flake/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL_3.0-blue.svg)](./LICENSE)

A Nix flake for installing **[Azeron Software](https://azeron.com/pages/software)** — the keypad configurator for Azeron devices (Cyborg, Cyro, Classic, Keyzen) — on NixOS, Home Manager, or any system with Nix.

Upstream ships a single Linux AppImage (officially marked "experimental", tested on Arch / SteamOS) and no `.deb`, `.rpm`, or Flatpak. This flake wraps that AppImage with `appimageTools.wrapType2`, registers a `.desktop` entry plus icon, and pins the binary by SRI hash for `x86_64-linux`. Version and hash are bumped manually — see [Manual hash bump](#manual-hash-bump) below.

## Features

- **Declarative install** — no manual `chmod +x`, no rogue AppImage in `~/Downloads`
- **First-class outputs** — `packages`, `apps`, `overlays`, `nixosModules`, `homeManagerModules`, `checks`, `formatter`, `devShells`
- **Real desktop integration** — 256×256 icon (extracted from the AppImage) and `.desktop` entry land in the correct hicolor paths
- **Reproducible** — every commit pins a specific AppImage by SHA-256
- **CI-verified** — every push runs `nix flake check`, `nix fmt --check`, and a real `nix build`

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

## Manual hash bump

When azeron.com publishes a new Linux build, refresh the URL/version/hash in [flake.nix](./flake.nix) by hand:

1. Visit <https://azeron.com/pages/software> and grab the current download URL — it looks like
   `https://azeron-software-public.s3.us-east-1.amazonaws.com/live/X.Y.Z/Azeron+Software-X.Y.Z.AppImage`.
2. Compute the SRI hash:

   ```sh
   nix store prefetch-file \
     "https://azeron-software-public.s3.us-east-1.amazonaws.com/live/X.Y.Z/Azeron+Software-X.Y.Z.AppImage" \
     --json | jq -r .hash
   ```

3. Update the matching `version` and `hash` lines in [flake.nix](./flake.nix).
4. Rebuild and verify:

   ```sh
   nix flake check
   nix build .#packages.x86_64-linux.azeron-software
   ```

5. To pull a fresh `nixpkgs`, run `nix flake update` and commit the new `flake.lock`.

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
├── azeron.png                      # 256×256 icon (extracted from upstream AppImage)
├── LICENSE                         # GPL-3.0 (wrapper code only)
├── README.md
└── .github/workflows/
    └── ci.yml                      # build + fmt + flake check on every push
```

## License

The Nix expressions and CI glue in this repo are GPL-3.0 (see [LICENSE](./LICENSE)). Azeron Software itself is governed by [Azeron's own terms](https://azeron.com/pages/software) — this repo only pins a public download URL and the wrapping logic, never the binary.
