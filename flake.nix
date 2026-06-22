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

    checks = forAllSystems (system: {
      kestra-package = self.packages.${system}.kestra;
    });

    nixosModules = rec {
      kestra = (import ./kestra.nix).flake.modules.nixos.servicesKestra;
      default = kestra;
    };

    nixosConfigurations.example = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.kestra
        ({pkgs, ...}: {
          services.kestra.package = self.packages.${pkgs.system}.kestra;
          system.stateVersion = "25.11";
        })
      ];
    };
  };
}
