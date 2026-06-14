{
  description = "Standalone Azeron Software package wrapping the upstream Linux AppImage.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      version = "2.0.0";

      sources = {
        x86_64-linux = {
          url = "https://azeron-software-public.s3.us-east-1.amazonaws.com/live/${version}/Azeron+Software-${version}.AppImage";
          hash = "sha256-2JwBNVNdNEgdlI1pLY7BPlEJA1KPS96TIWmBitrlcvU=";
        };
      };

      mkAzeron = pkgs:
        pkgs.appimageTools.wrapType2 {
          pname = "azeron-software";
          inherit version;

          src = pkgs.fetchurl sources.${pkgs.stdenv.hostPlatform.system};

          extraInstallCommands = ''
            mkdir -p $out/share/icons/hicolor/256x256/apps
            cp ${./azeron.png} $out/share/icons/hicolor/256x256/apps/azeron-software.png

            mkdir -p $out/share/applications
            cat > $out/share/applications/azeron-software.desktop <<EOF
            [Desktop Entry]
            Type=Application
            Name=Azeron Software
            GenericName=Azeron Keypad Configurator
            Exec=azeron-software --no-sandbox %U
            Icon=azeron-software
            Comment=Configure Azeron keypads, remap keys, flash firmware
            Categories=Utility;Settings;HardwareSettings;
            Terminal=false
            StartupWMClass=Azeron Software
            EOF
          '';

          meta = with pkgs.lib; {
            description = "Azeron Software — keypad configurator (AppImage wrapper)";
            longDescription = ''
              Standalone Nix flake that wraps the upstream Azeron Software AppImage
              with appimageTools.wrapType2 and installs an icon plus .desktop entry.
              The AppImage URL, version, and SRI hash are pinned manually — bump them
              when azeron.com publishes a new Linux release.

              Note: this packages the GUI configurator only. Flashing firmware over
              USB requires udev rules that grant your user access to the device;
              those are not bundled here.
            '';
            homepage = "https://azeron.com/pages/software";
            downloadPage = "https://azeron.com/pages/software";
            license = licenses.unfree;
            sourceProvenance = with sourceTypes; [ binaryNativeCode ];
            platforms = systems;
            mainProgram = "azeron-software";
          };
        };
    in
    {
      # Build with allowUnfree set internally so consumers don't need to
      # configure `nixpkgs.config.allowUnfree` just to evaluate this input.
      # The wrapped binary is Azeron's own closed-source AppImage — anyone
      # adding this flake as an input is implicitly opting in to that.
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        rec {
          azeron-software = mkAzeron pkgs;
          default = azeron-software;
        });

      apps = forAllSystems (system: rec {
        azeron-software = {
          type = "app";
          program = "${self.packages.${system}.azeron-software}/bin/azeron-software";
          meta.description = "Launch Azeron Software without installing.";
        };
        default = azeron-software;
      });

      overlays.default = final: _prev: {
        azeron-software = mkAzeron final;
      };

      nixosModules.default = { config, lib, pkgs, ... }:
        let cfg = config.programs.azeron-software;
        in {
          options.programs.azeron-software = {
            enable = lib.mkEnableOption "Azeron Software keypad configurator";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.azeron-software;
              defaultText = lib.literalExpression "azeron.packages.\${system}.azeron-software";
              description = "Which Azeron Software package to install.";
            };
          };
          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
          };
        };

      homeManagerModules.default = { config, lib, pkgs, ... }:
        let cfg = config.programs.azeron-software;
        in {
          options.programs.azeron-software = {
            enable = lib.mkEnableOption "Azeron Software keypad configurator";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.azeron-software;
              defaultText = lib.literalExpression "azeron.packages.\${system}.azeron-software";
              description = "Which Azeron Software package to install.";
            };
          };
          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };

      checks = forAllSystems (system: {
        build = self.packages.${system}.azeron-software;
      });

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [ nixpkgs-fmt jq gnused curl ];
          };
        });
    };
}
