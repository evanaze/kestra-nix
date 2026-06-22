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
