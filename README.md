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
        ({ pkgs, ... }: {
          services.kestra = {
            enable = true;
            package = kestra-nix.packages.${pkgs.stdenv.hostPlatform.system}.kestra;

            # Choose local or external PostgreSQL mode below.
          };
        })
      ];
    };
  };
}
```

### Local PostgreSQL mode

Set `database.createLocally = true` to have the module provision a local PostgreSQL database:

```nix
{
  services.kestra = {
    enable = true;
    database.createLocally = true;
  };
}
```

The module will enable PostgreSQL, create the database and user, add authentication rules, and define `kestra-db-init.service`.

### External PostgreSQL mode

With `database.createLocally = false` (the default), the module assumes an external PostgreSQL instance and does not configure or depend on local PostgreSQL:

```nix
{
  services.kestra = {
    enable = true;
    database.host = "db.example.com";
    database.port = 5432;
    database.name = "kestra";
    database.user = "kestra";
  };
}
```

### HTTP server port

Use `services.kestra.port` to set the generated `micronaut.server.port` value:

```nix
{
  services.kestra = {
    enable = true;
    port = 8080;
  };
}
```

As with the other generated settings, `services.kestra.settings` can still override this explicitly:

```nix
{
  services.kestra = {
    enable = true;
    port = 8080;
    settings.micronaut.server.port = 9090;
  };
}
```

### Module options

All `services.kestra` options exposed by the module are listed below.

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the Kestra NixOS service |
| `package` | `pkgs.kestra` if available, otherwise this flake's packaged derivation | Kestra package used for `kestra.service` |
| `port` | `8080` | Generated `micronaut.server.port` value for the Kestra HTTP server |
| `settings` | `{}` | Extra Kestra YAML settings merged after generated defaults; may override generated values |
| `database.createLocally` | `false` | When `true`, provisions a local PostgreSQL database |
| `database.host` | `"127.0.0.1"` | PostgreSQL host |
| `database.port` | `5432` | PostgreSQL port |
| `database.name` | `"kestra"` | Database name |
| `database.user` | `"kestra"` | Database user |
| `database.passwordFile` | `"/run/secrets/kestra/db-password"` | Path to the PostgreSQL password file |
| `database.jdbcUrl` | `null` | Full JDBC URL override (replaces auto-generated URL) |
| `encryptionSecretKeyFile` | `"/run/secrets/kestra/encryption-secret-key"` | File used for `kestra.encryption.secret-key` |
| `jdbcSecretKeyFile` | `"/run/secrets/kestra/jdbc-secret-key"` | File used for `kestra.secret.jdbc.secret` |
| `user` | `"kestra"` | System user that runs `kestra.service` |
| `group` | `"kestra"` | System group that runs `kestra.service` |
| `stateDir` | `"/var/lib/kestra"` | Directory for Kestra runtime state, storage, and default plugins path |
| `pluginPath` | `null` | Plugin directory passed via `--plugins`; defaults to `${stateDir}/plugins` when unset |
| `runtimeConfigFile` | `"/run/kestra/application.yaml"` | Runtime path for the generated Kestra YAML config with secrets substituted |

### Option precedence

Generated Kestra defaults (from `database.*` options) are merged first. The `services.kestra.settings` option is merged last and can intentionally override any generated value:

```nix
services.kestra.settings = {
  micronaut.server.host = "127.0.0.1";
  # ... custom Kestra YAML settings
};
```

## Secrets

The module is backend-neutral: it expects secret values to already exist as files at runtime. It does not require or configure `sops-nix` by itself.

Secret file options:

- `services.kestra.database.passwordFile`: PostgreSQL password for the Kestra database user. `kestra-db-init.service` receives it via systemd `LoadCredential`, but `kestra.service` reads the configured file directly during `preStart`, so it must be readable by the Kestra service user.
- `services.kestra.encryptionSecretKeyFile`: value for `kestra.encryption.secret-key`. Readable by the Kestra service user.
- `services.kestra.jdbcSecretKeyFile`: value for `kestra.secret.jdbc.secret`. Readable by the Kestra service user.

Additional secret leaves can be supplied anywhere under `services.kestra.settings` using `{ _secret = "/path/to/file"; }`:

```nix
services.kestra.settings = {
  some.nested.value._secret = "/run/secrets/kestra/extra-secret";
};
```

Secret values are substituted at service start time into a generated runtime config at `/run/kestra/application.yaml` (mode `0600`). They are never stored in the Nix store.

### Example with sops-nix

```nix
{ config, ... }: {
  sops.secrets = {
    "kestra/db-password" = {
      owner = "root";
      mode = "0400";
    };
    "kestra/encryption-secret-key" = {
      owner = "root";
      mode = "0400";
    };
    "kestra/jdbc-secret-key" = {
      owner = "root";
      mode = "0400";
    };
  };

  services.kestra = {
    enable = true;
    database.createLocally = true;  # or false for external DB

    database.passwordFile = config.sops.secrets."kestra/db-password".path;
    encryptionSecretKeyFile = config.sops.secrets."kestra/encryption-secret-key".path;
    jdbcSecretKeyFile = config.sops.secrets."kestra/jdbc-secret-key".path;
  };
}
```

If you prefer `pkgs.kestra`, add the flake overlay to your `nixpkgs` import:

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
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ kestra-nix.overlays.default ];

          services.kestra = {
            enable = true;
            package = pkgs.kestra;
          };
        })
        kestra-nix.nixosModules.kestra
      ];
    };
  };
}
```

If your secret backend creates files with different ownership, permissions, or paths, set the three `*File` options to those paths accordingly.

## Repository layout

```
flake.nix                  # Flake definition: packages, apps, checks, modules, example
kestra/default.nix         # Kestra package derivation (unchanged)
modules/services/kestra/   # NixOS module implementation
  default.nix
examples/                  # (optional future examples)
checks/                    # (optional future check helpers)
README.md                  # This file
```

## Validation

Run these checks from a checkout:

```sh
nix flake check
nix build .#kestra
nix run . -- --help
```

`nix flake check` evaluates the package checks, module local/external DB mode checks, and the example NixOS configuration. `nix build .#kestra` builds the Kestra package. `nix run . -- --help` runs the packaged CLI and should print Kestra help output.
