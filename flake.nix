{
  description = "Standalone Kestra package and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    lib = nixpkgs.lib;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = lib.genAttrs systems;
    pkgsFor = system: import nixpkgs {inherit system;};
  in {
    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
      kestra = pkgs.callPackage ./kestra {};
    in {
      inherit kestra;
      default = kestra;
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = lib.getExe self.packages.${system}.kestra;
      };
    });

    checks = forAllSystems (system: let
      pkgs = pkgsFor system;
      moduleCheckPackage = pkgs.writeShellScriptBin "kestra" ''
        echo dummy kestra
      '';
      evalConfig = lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.kestra
          ({...}: {
            services.kestra = {
              enable = true;
              package = moduleCheckPackage;
              databasePasswordFile = "/run/secrets/kestra/db-password";
              encryptionSecretKeyFile = "/run/secrets/kestra/encryption-secret-key";
              jdbcSecretKeyFile = "/run/secrets/kestra/jdbc-secret-key";
            };
            system.stateVersion = "25.11";
          })
        ];
      };
    in {
      kestra-package = self.packages.${system}.kestra;
      kestra-module-eval = pkgs.runCommand "kestra-module-eval" {
        passAsFile = ["kestraUnitText"];
        kestraUnitText = evalConfig.config.systemd.units."kestra.service".text;
      } ''
        test -s "$kestraUnitTextPath"
        touch $out
      '';
    });

    nixosModules = rec {
      kestra = (import ./kestra.nix).flake.modules.nixos.servicesKestra;
      default = kestra;
    };

    nixosConfigurations.example = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.kestra
        ({pkgs, ...}: let
          system = pkgs.stdenv.hostPlatform.system;
        in {
          services.kestra = {
            enable = true;
            package = self.packages.${system}.kestra;
            databasePasswordFile = "/run/secrets/kestra/db-password";
            encryptionSecretKeyFile = "/run/secrets/kestra/encryption-secret-key";
            jdbcSecretKeyFile = "/run/secrets/kestra/jdbc-secret-key";
          };

          services.postgresql.enable = true;

          # Minimal dummy settings so the example is evaluable by `nix flake check`
          # without acting as a real installation configuration.
          fileSystems."/" = {
            device = "tmpfs";
            fsType = "tmpfs";
          };
          boot.loader.grub.enable = false;

          system.stateVersion = "25.11";
        })
      ];
    };
  };
}
