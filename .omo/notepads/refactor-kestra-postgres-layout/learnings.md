# Learnings: Refactor Kestra Postgres Layout

## 2026-06-22 Task: session-start
- Active plan switched from `standalone-kestra-flake` to `refactor-kestra-postgres-layout` per user selection.
- Plan objective: clarify flake/module layout and split local vs external PostgreSQL semantics using nested `services.kestra.database`.

## 2026-06-22 Task: task-1-direct-baseline
- `nix flake show` currently exposes `apps`, `checks`, `nixosConfigurations.example`, `nixosModules.{default,kestra}`, and `packages.{x86_64-linux,aarch64-linux}.{default,kestra}`.
- `git status --short` produced no entries; tracked files are `.gitignore`, `LICENSE`, `README.md`, `flake.lock`, `flake.nix`, `kestra.nix`, and `kestra/default.nix`.
- Current references to old layout/database API are concentrated in `README.md`, `flake.nix`, and `kestra.nix`.
- Current package derivation path is `kestra/default.nix`; it pins Kestra `1.3.22`, uses `temurin-bin.jre-25`, and must remain behaviorally unchanged during layout refactor.
- `ast-grep` binary is unavailable; `/run/wrappers/bin/sg` is shadow-utils group switching, not ast-grep. Use text search/Nix eval for this repo.
- Repository root currently contains `.git/`, `.gitignore`, `.sisyphus/`, `flake.lock`, `flake.nix`, `kestra.nix`, `kestra/`, `LICENSE`, `README.md`, and ignored `result/`.
- File-level LSP diagnostics for `flake.nix` and `kestra.nix` are clean at baseline.
- NixOS convention search confirms many services use `database.createLocally`; examples include Tranquil PDS defaulting false and Pretix defaulting true depending on module ergonomics.
- NixOS secret handling examples commonly use systemd `LoadCredential`; examples include Castopod `database.passwordFile`, Keycloak DB init credentials, Nextcloud, Umami, LibreChat, and Lemmy.
- Kestra docs confirm minimal PostgreSQL-backed standalone config needs `kestra.queue.type = "postgres"`, `kestra.repository.type = "postgres"`, and `datasources.postgres.{url,driver-class-name,username,password}`. JDBC secrets use `kestra.secret.type = "jdbc"` and `kestra.secret.jdbc.secret`.

## 2026-06-22 Task: task-1-baseline-map
- Exact old-layout references are in `flake.nix:22,43,48,68,75,82,87` and `kestra.nix:85-86,111-144,209-230,248-316`; docs mirror them in `README.md:10,48,50,56,71-72,84,104-105,131` and plan notes in `.sisyphus/plans/refactor-kestra-postgres-layout.md:15-21,144-145,181,233-237,275-286,298-315`.
- Hidden/config file audit found `.gitignore:1-12` as the only non-README/Nix hidden file likely to need future updates; `.github`, `.vscode`, `.editorconfig`, and `.envrc` are absent.
- `git status --short --branch` was clean before this notepad append (`## main...origin/main`).
- `ast-grep` is not available in this environment, so text search is the reliable baseline for Nix files.


## 2026-06-22 Task: NixOS convention research
- Official flake validation recognizes `packages.<system>.*`, `apps.<system>.*`, `checks.<system>.*`, `nixosModules.*`, and `nixosConfigurations.*`; preserving `packages.${system}.kestra/default`, `apps.${system}.default`, `checks.${system}.*`, `nixosModules.kestra/default`, and `nixosConfigurations.example` matches current Nix output schema.
- Separating implementation files as `pkgs/kestra/default.nix`, `modules/services/kestra/default.nix`, `examples/nixos/local-postgres.nix`, and optional `checks/` helpers is a conventional repository organization; the stable public contract is the flake outputs, not the internal file paths.
- NixOS option search shows many service modules expose `services.<name>.database.createLocally` with description “Create the database and database user locally” or equivalent. Use `services.kestra.database.createLocally = false` by default for reusable external DB behavior, with the example opting into `true`.
- Common DB option naming is nested under `database` with `name`, `user`/`username`, `host`/`hostname`, `port`, and `passwordFile`; `passwordFile` should be an absolute path/string to a runtime file, not an inline password.
- PostgreSQL conventions: `services.postgresql.ensureUsers` uses peer authentication and does not delete stale users/ownership; `services.postgresql.authentication` additions are inserted above defaults, with `lib.mkForce` only for replacing defaults entirely.


## 2026-06-22 Task: kestra-postgres-config-reference
- Current module-generated Kestra defaults to preserve during refactor: `micronaut.server.host = "127.0.0.1"`; `datasources.postgres.url`; `datasources.postgres.driver-class-name = "org.postgresql.Driver"`; `datasources.postgres.username`; `datasources.postgres.password._secret`; `kestra.repository.type = "postgres"`; `kestra.queue.type = "postgres"`; `kestra.storage.type = "local"`; `kestra.storage.local.base-path = "${cfg.stateDir}/storage"`; `kestra.encryption.secret-key._secret`; `kestra.secret.type = "jdbc"`; `kestra.secret.jdbc.secret._secret`. `services.kestra.settings` is merged after generated defaults via `lib.recursiveUpdate`, so later refactors must preserve it as the advanced raw override layer.
- Official Kestra docs confirm standalone mode uses `server standalone` and requires a database-backed config; configuration can be supplied with `--config`/`-c` or `KESTRA_CONFIGURATION`.
- Official Kestra Runtime and Storage docs confirm PostgreSQL baseline keys: `kestra.queue.type = postgres`, `kestra.repository.type = postgres`, and `datasources.postgres.url`, `driver-class-name`, `username`, `password`. Configuration Basics also confirms `kestra.storage.type = local` as the minimal boot storage shape.
- Official Kestra Security and Secrets docs confirm `kestra.encryption.secret-key` for encrypted SECRET values and `kestra.secret.type = jdbc` with `kestra.secret.jdbc.secret` for JDBC-backed secrets.
- Official source examples also use PostgreSQL datasource + repository/queue + local storage for all-in-one/Postgres examples; test config includes `kestra.server-type = STANDALONE` with `queue.type = postgres`, `repository.type = postgres`, `storage.type = local`, and local base path.

## 2026-06-22 Task: task-1-acceptance-confirmation
- Re-ran `nix flake show`; it succeeded and listed `apps.{aarch64-linux,x86_64-linux}.default`, `checks.{aarch64-linux,x86_64-linux}.{kestra-module-eval,kestra-package}`, `nixosConfigurations.example`, `nixosModules.{default,kestra}`, and `packages.{aarch64-linux,x86_64-linux}.{default,kestra}`.
- Re-ran `git status --short`; it produced no output before this append.
- Confirmed full-plan package smoke command is `nix run . -- --help`; it is documented in README validation and plan verification, but was not run for Task 1.
- Re-confirmed old-layout/flat database references with text search: `flake.nix:22,43,48,68,75,82`; `kestra.nix:85-86,111-144,209,218,220,249,252,262-263,291-292`; `README.md:10,48,56,84,131`.
