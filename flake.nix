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
    overlays.default = final: prev: {
      kestra = final.callPackage ./kestra {};
    };

    packages = forAllSystems (
      system: let
        pkgs = pkgsFor system;
        kestra = (pkgs.extend self.overlays.default).kestra;
      in {
        inherit kestra;
        default = kestra;
      }
    );

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = lib.getExe self.packages.${system}.kestra;
      };
    });

    checks = forAllSystems (
      system: let
        pkgs = pkgsFor system;
        moduleCheckPackage = pkgs.writeShellScriptBin "kestra" ''
          echo dummy kestra
        '';

        # External DB mode: default (createLocally = false).
        externalEval = lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.kestra
            ({...}: {
              services.kestra = {
                enable = true;
                package = moduleCheckPackage;
              };
              system.stateVersion = "25.11";
            })
          ];
        };
        externalUnitText = externalEval.config.systemd.units."kestra.service".text;
        externalPreStart = externalEval.config.systemd.services.kestra.preStart;

        defaultPackageEval = lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.kestra
            ({...}: {
              services.kestra.enable = true;
              system.stateVersion = "25.11";
            })
          ];
        };
        defaultPackageUnitText = defaultPackageEval.config.systemd.units."kestra.service".text;

        # Local DB mode: explicit createLocally = true.
        localEval = lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.kestra
            ({...}: {
              services.kestra = {
                enable = true;
                package = moduleCheckPackage;
                database.createLocally = true;
              };
              system.stateVersion = "25.11";
            })
          ];
        };
        localUnitText = localEval.config.systemd.units."kestra.service".text;
        localDbInitText = localEval.config.systemd.units."kestra-db-init.service".text or null;
        localDbInitScript = localEval.config.systemd.services.kestra-db-init.script or "";
        localPgAuth = localEval.config.services.postgresql.authentication or "";
      in {
        kestra-package = self.packages.${system}.kestra;

        # Module eval: kestra.service unit text is non-empty.
        kestra-module-eval =
          pkgs.runCommand "kestra-module-eval"
          {
            passAsFile = ["kestraUnitText"];
            kestraUnitText = externalUnitText;
          }
          ''
            test -s "$kestraUnitTextPath"
            touch $out
          '';

        # Module eval: default package resolves without pkgs.kestra in nixpkgs.
        kestra-module-default-package-check =
          pkgs.runCommand "kestra-module-default-package-check"
          {
            passAsFile = ["kestraUnitText"];
            kestraUnitText = defaultPackageUnitText;
          }
          ''
            test -s "$kestraUnitTextPath"
            touch $out
          '';

        # External DB mode: kestra.service exists, no kestra-db-init, no PostgreSQL ensureDatabases.
        kestra-external-db-check = pkgs.runCommand "kestra-external-db-check" {} ''
          unit_file=${
            pkgs.writeText "ext-unit" (externalEval.config.systemd.units."kestra.service".text or "MISSING")
          }
          pre_start_file=${pkgs.writeText "ext-pre-start" externalPreStart}

          # kestra.service unit must exist and have ExecStart
          test -s "$unit_file"
          grep -q "ExecStart" "$unit_file"
          grep -q "${externalEval.config.services.kestra.database.passwordFile}" "$pre_start_file"
          grep -q "${externalEval.config.services.kestra.encryptionSecretKeyFile}" "$pre_start_file"
          grep -q "${externalEval.config.services.kestra.jdbcSecretKeyFile}" "$pre_start_file"
          ! grep -q "LoadCredential" "$unit_file"
          ! grep -q '${"$"}{CREDENTIALS_DIRECTORY}' "$pre_start_file"
          touch "$out"
        '';

        # Local DB mode: kestra-db-init.service unit text is non-empty.
        kestra-local-db-check = pkgs.runCommand "kestra-local-db-check" {} ''
          unit_file=${
            pkgs.writeText "db-init-unit" (
              localEval.config.systemd.units."kestra-db-init.service".text or "MISSING"
            )
          }
          script_file=${pkgs.writeText "db-init-script" localDbInitScript}
          pg_hba_file=${pkgs.writeText "local-pg-auth" localPgAuth}

          # kestra-db-init.service unit must exist and be non-empty
          test -s "$unit_file"
          grep -q "LoadCredential=db-password:${localEval.config.services.kestra.database.passwordFile}" "$unit_file"
          grep -q '${"$"}CREDENTIALS_DIRECTORY/db-password' "$script_file"
          grep -q "hostnossl ${localEval.config.services.kestra.database.name} ${localEval.config.services.kestra.database.user} 127.0.0.1/32 scram-sha-256" "$pg_hba_file"
          grep -q "hostnossl ${localEval.config.services.kestra.database.name} ${localEval.config.services.kestra.database.user} ::1/128 scram-sha-256" "$pg_hba_file"
          touch "$out"
        '';
      }
    );

    nixosModules = rec {
      kestra = import ./modules/services/kestra;
      default = kestra;
    };

    nixosConfigurations.example = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.kestra
        (
          {pkgs, ...}: let
            system = pkgs.stdenv.hostPlatform.system;
          in {
            services.kestra = {
              enable = true;
              package = self.packages.${system}.kestra;
              database.createLocally = true;
            };

            # Minimal dummy settings so the example is evaluable by `nix flake check`
            # without acting as a real installation configuration.
            fileSystems."/" = {
              device = "tmpfs";
              fsType = "tmpfs";
            };
            boot.loader.grub.enable = false;

            system.stateVersion = "25.11";
          }
        )
      ];
    };
  };
}
