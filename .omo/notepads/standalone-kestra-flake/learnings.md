# Learnings: Standalone Kestra Flake

## 2026-06-22 Task: session-initialization
- Active plan: `.sisyphus/plans/standalone-kestra-flake.md`.
- Existing repo has only two Nix source files: `kestra/default.nix` and `kestra.nix`.
- Direct grep/rg confirmed current risks in `kestra.nix`: broken `../../pkgs/kestra`, sops-specific references, hardcoded `sops-secrets.target`, hardcoded `StateDirectory = "kestra"`, and flake-parts-ish `flake.modules.nixos` export.
- AST-grep tool failed in this NixOS environment because its bundled executable is dynamically linked for generic Linux; use direct `rg`/Nix-aware review for this session.

## 2026-06-22 Task: search-synthesis
- Explore agent confirmed repo is not a standalone flake: no `flake.nix`, no `flake.lock`, no `README.md`, no `pkgs/` tree.
- Explore agent confirmed `git ls-files` currently tracks only `.gitignore` and `LICENSE`; current Kestra files and `.sisyphus/` are untracked working-tree files.
- Existing package `kestra/default.nix` pins Kestra `1.3.22` and uses fixed-output release URL/hash plus `makeWrapper` around Java.
- Kestra docs/source research found a Java-version nuance: standalone docs say JVM 21+, but current requirements and pinned upstream `v1.3.22` launcher require/reject below Java 25. Keep `temurin-bin.jre-25` for now.
- Official Kestra docs support explicit `--config`, `server standalone`, plugin path via `--plugins`/`KESTRA_PLUGINS_PATH`, and systemd settings matching the current service (`Type=simple`, restart, `KillMode=mixed`, `TimeoutStopSec=150`, `SuccessExitStatus=143`).
- Official PostgreSQL-backed standalone config requires `datasources.postgres.*`, `kestra.repository.type = "postgres"`, `kestra.queue.type = "postgres"`; current defaults generally align.
- Nix flake test research recommends plain `nixpkgs.lib.genAttrs` systems, `packages`, `apps`, `nixosModules`, `nixosConfigurations.example`, and `checks`; use `pkgs.testers.runNixOSTest` with fake executable for service wiring tests.
- Flake evaluation may ignore untracked files depending on source mode; ensure new flake files are in working tree and beware git-tracked-file gotchas during verification.

## 2026-06-21 - Task 1 standalone flake skeleton
- Added a plain flake with only nixpkgs/nixos-unstable as input.
- Exposed packages/apps/checks for x86_64-linux and aarch64-linux; package uses pkgs.callPackage ./kestra {} and app uses lib.getExe.
- Bridged current nested module export via (import ./kestra.nix).flake.modules.nixos.servicesKestra for nixosModules.kestra/default.
- nix flake lock and nix flake show require new flake files to be visible in the Git index; staged flake.nix and flake.lock without committing.
- Verified nix flake show and nix build .#checks.x86_64-linux.kestra-package --no-link.

## 2026-06-21 Task 2 Kestra package output wiring
- No edits were needed: `flake.nix` already exposes `packages.${system}.kestra` and `packages.${system}.default = kestra` for x86_64-linux/aarch64-linux, and the default flake app uses `lib.getExe self.packages.${system}.kestra`.
- `kestra/default.nix` still pins Kestra `1.3.22`, keeps `javaPackages.compiler.temurin-bin.jre-25`, and preserves homepage/license/platforms/mainProgram metadata.
- `rg` over `flake.nix` and `kestra/default.nix` found no forbidden new inputs such as sops-nix, agenix, flake-parts, Docker/Kubernetes, Home Manager, or Darwin.
- File-level LSP diagnostics were clean for `flake.nix` and `kestra/default.nix`.
- Verified `nix build .#kestra`, `nix build .#default`, and `nix run . -- --help`; the smoke command printed CLI help and exited without starting a server.

## 2026-06-22 Task 3 NixOS module API research
- Nixpkgs local DB toggles commonly use `database.createDatabase` (Gitea/Forgejo) or `createDatabaseLocally` (Miniflux/Mediagoblin); for Kestra prefer `services.kestra.configurePostgresql` only if the intent is broader than database creation (also enable PostgreSQL, ensure DB/user, and db-init dependencies).
- Runtime secret file options should use `lib.types.externalPath` for backend-neutral absolute paths outside the Nix store; nixpkgs `types.externalPath` is `pathWith { absolute = true; inStore = false; }`.
- Additional secret-provider ordering should be a list of systemd unit names and feed both `wants` and `after`; nixpkgs modules often call this `serviceDependencies`, while a Kestra-specific name like `secretUnitDependencies` is acceptable if scoped to secrets.
- `settings.*._secret = "/path"` is an existing NixOS pattern (Keycloak/Immich/Perses) for keeping raw settings attrsets while loading secret values at runtime. NixOS also has `utils.genJqSecretsReplacement`, but adopting it may be a Task 4 runtime implementation change rather than Task 3 API-only work.
