# kestra-nix

Standalone Nix package and NixOS module for [Kestra](https://kestra.io/).

> Replace `github:evanaze/kestra-nix` with the actual repository URL after publishing.

This flake provides:

- a `kestra` package and default app for running the Kestra CLI;
- a NixOS module at `nixosModules.kestra` / `nixosModules.default` for running Kestra as a systemd service backed by PostgreSQL.

## Package

Run the packaged Kestra CLI from the flake:

```sh
nix run github:evanaze/kestra-nix -- --help
```

Build the package:

```sh
nix build github:evanaze/kestra-nix#kestra
```

For local development from a checkout:

```sh
nix run . -- --help
nix build .#kestra
```

## NixOS module

Add the flake as an input and import its NixOS module from your host configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kestra-nix.url = "github:evanaze/kestra-nix";
  };

  outputs = { self, nixpkgs, kestra-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        kestra-nix.nixosModules.kestra
        ({ config, pkgs, ... }: {
          services.postgresql.enable = true;

          services.kestra = {
            enable = true;
            package = kestra-nix.packages.${pkgs.stdenv.hostPlatform.system}.kestra;

            databasePasswordFile = "/run/secrets/kestra/db-password";
            encryptionSecretKeyFile = "/run/secrets/kestra/encryption-secret-key";
            jdbcSecretKeyFile = "/run/secrets/kestra/jdbc-secret-key";
          };
        })
      ];
    };
  };
}
```

The module manages:

- `users.users.kestra`;
- `users.groups.kestra`;
- PostgreSQL database/user ownership via `services.postgresql.ensureDatabases` and `services.postgresql.ensureUsers`;
- `kestra-db-init.service`, which sets the PostgreSQL role password and database owner;
- `kestra.service`, which runs `kestra server standalone`;
- runtime config generation at `/run/kestra/application.yaml` by default.

The flake also contains `nixosConfigurations.example`, but it is evaluation-only. It includes dummy tmpfs/grub settings so `nix flake check` can evaluate a full NixOS system. Do not deploy that example directly; copy the relevant `services.kestra` options into a real host configuration instead.

## Secrets

The module is backend-neutral: it expects secret values to already exist as files at runtime. It does not require or configure `sops-nix` by itself.

Secret file options:

- `services.kestra.databasePasswordFile`: PostgreSQL password for the Kestra database user. This file must be readable by both the PostgreSQL service user (`postgres`), because `kestra-db-init.service` runs as `postgres`, and the Kestra service user, because `kestra.service` reads it during `preStart` to generate runtime configuration.
- `services.kestra.encryptionSecretKeyFile`: value for `kestra.encryption.secret-key`. This file must be readable by the Kestra service user.
- `services.kestra.jdbcSecretKeyFile`: value for `kestra.secret.jdbc.secret`. This file must be readable by the Kestra service user.

Additional secret leaves can be supplied anywhere under `services.kestra.settings` using `{ _secret = "/path/to/file"; }`, for example:

```nix
services.kestra.settings = {
  some.nested.value._secret = "/run/secrets/kestra/extra-secret";
};
```

Those arbitrary `settings.*._secret` paths are read during `kestra.service` `preStart` as the Kestra service user, so they must also be readable by that user.

### Example with sops-nix

One way to provide the expected files is with `sops-nix`:

```nix
{ config, ... }: {
  # The database password is read by both kestra-db-init.service
  # (as postgres) and kestra.service preStart (as kestra). The
  # module creates the kestra group; adding postgres to it lets a
  # group-readable secret be shared by both service users.
  users.users.postgres.extraGroups = [ "kestra" ];

  sops.secrets = {
    "kestra/db-password" = {
      owner = "kestra";
      group = "kestra";
      mode = "0440";
    };

    "kestra/encryption-secret-key" = {
      owner = "kestra";
      group = "kestra";
      mode = "0400";
    };

    "kestra/jdbc-secret-key" = {
      owner = "kestra";
      group = "kestra";
      mode = "0400";
    };
  };

  services.kestra = {
    databasePasswordFile = config.sops.secrets."kestra/db-password".path;
    encryptionSecretKeyFile = config.sops.secrets."kestra/encryption-secret-key".path;
    jdbcSecretKeyFile = config.sops.secrets."kestra/jdbc-secret-key".path;
  };
}
```

If your secret backend creates files with different ownership, permissions, or paths, set the three `*File` options to those paths and ensure the readability requirements above are satisfied.

## Validation

Run these checks from a checkout:

```sh
nix flake check
nix build .#kestra
nix run . -- --help
```

`nix flake check` evaluates the package checks and module example. `nix build .#kestra` builds the Kestra package. `nix run . -- --help` runs the packaged CLI and should print Kestra help output.
