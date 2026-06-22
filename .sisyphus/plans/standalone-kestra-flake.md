# Standalone Kestra Flake

## Context

### Original Request
The user copied code for installing and configuring Kestra from the standalone-server documentation into this repository and asked to turn it into a standalone flake.

Source documentation: https://kestra.io/docs/installation/standalone-server

### Interview Summary
**Key Discussions**:
- Flake shape: reusable + runnable.
  - Reusable outputs must expose the Kestra package and NixOS module.
  - Runnable outputs must include an example NixOS configuration and a flake app/package smoke path.
- Secret handling: make secret management optional/agnostic.
  - Do not require `sops-nix` to evaluate or use the module.
  - Accept runtime secret file paths so sops-nix, agenix, systemd credentials, or manually managed files can provide secrets.
- Validation: include automated Nix checks/tests.
  - `nix flake check` should become the main verification command.
  - Include package build, module/example evaluation, and a lightweight NixOS VM/module test where practical.
- PostgreSQL: optional local PostgreSQL.
  - Reusable module should not always own PostgreSQL.
  - Runnable example should enable local PostgreSQL for a turnkey standalone demo.

**Research Findings**:
- `kestra/default.nix` packages Kestra 1.3.22 as a standalone JAR wrapper and uses Temurin JRE 25.
- `kestra.nix` currently contains a NixOS module-like service definition under a flake-parts-ish wrapper.
- The repository has no `flake.nix`, no `flake.lock`, and no top-level flake outputs.
- `nixpkgs` unstable package search found no existing `kestra` package, so local packaging is needed.
- Official Kestra docs say the standalone JAR requires JVM 21+, can run `server standalone`, accepts config with `--config`, and supports plugins via manual install, `KESTRA_PLUGINS_PATH`, or `--plugins`.
- Official systemd guidance uses a simple service with restart, `KillMode=mixed`, `TimeoutStopSec=150`, and `SuccessExitStatus=143`.
- Risks identified in existing code:
  - `kestra.nix:83-84` points to missing `../../pkgs/kestra` instead of the local `./kestra` package.
  - `kestra.nix:188-190` and `kestra.nix:222-237` assume `config.sops.secrets` exists.
  - `kestra.nix:300-311` hard-requires `sops-secrets.target`.
  - `kestra.nix:179` and `kestra.nix:315-346` generate `/run/kestra/application.yaml` without clear `RuntimeDirectory` ownership semantics.
  - `kestra.nix:163-167` and `kestra.nix:364-366` mix configurable `stateDir` with hardcoded `StateDirectory = "kestra"`.

### Metis Review
**Identified Gaps** (addressed):
- Runnable meaning: default to both `apps.${system}.default`/package smoke path and `nixosConfigurations.example`.
- Supported systems: default to Linux systems only for the service/package, with `x86_64-linux` and `aarch64-linux` unless evaluation reveals a platform limitation.
- JVM version: use Java 21 LTS by default unless the current package is proven to require JRE 25; Kestra only requires JVM 21+.
- Backwards compatibility: clean module API is acceptable; preserve obvious concepts but do not keep broken sops-specific option names as the primary API.
- Public namespace: use `services.kestra` and flake outputs `nixosModules.kestra` / `nixosModules.default`.
- Config model: keep a raw `settings` attrset rendered to YAML, plus runtime secret-file substitution for secret leaves; do not attempt to model the entire Kestra option schema.
- Plugin scope: only support plugin path configuration and safe directory management; do not implement plugin installation/packaging.
- Test depth: use real package build checks plus fake-executable NixOS module/VM checks; do not require the real Java service to boot in tests.

---

## Work Objectives

### Core Objective
Transform the repository into a standalone Nix flake for Kestra that is reusable by other flakes and runnable as an example NixOS configuration, while preserving secure runtime configuration generation and adding automated validation.

### Concrete Deliverables
- `flake.nix` with package, app, module, example configuration, and checks outputs.
- `flake.lock` generated from the chosen `nixpkgs` input.
- Refactored `kestra.nix` as a plain NixOS module export under `services.kestra`.
- Updated `kestra/default.nix` package if needed for JVM 21+ compatibility and flake output integration.
- Automated checks covering package build, module evaluation, example evaluation, and service wiring.
- Minimal documentation in `README.md` or equivalent Markdown showing package/module/example usage and optional sops-nix wiring.

### Definition of Done
- [ ] `nix flake show` lists package, app, NixOS module, example config, and checks outputs.
- [ ] `nix build .#kestra` succeeds.
- [ ] `nix run .#kestra -- --help` or an equivalent non-server smoke command succeeds without starting a long-running service.
- [ ] `nix flake check` passes.
- [ ] Generic module evaluation does not require `sops-nix`, `agenix`, or any secret-manager module.
- [ ] Runnable example configuration evaluates and enables local PostgreSQL explicitly.
- [ ] No real secret values are embedded in Nix store paths or flake examples except clearly marked demo-only values.

### Must Have
- Plain flake outputs, not a flake-parts-only shape.
- `services.kestra` NixOS module namespace.
- `packages.${system}.kestra` and `packages.${system}.default`.
- `apps.${system}.default` for the wrapped Kestra executable.
- `nixosModules.kestra` and `nixosModules.default`.
- `nixosConfigurations.example` for a runnable local-PostgreSQL demo.
- Optional local PostgreSQL management controlled by a module option.
- Secret-manager-agnostic file path options for database password, encryption secret key, and JDBC secret key.
- Secure generated runtime config under `/run` with mode `0600`.

### Must NOT Have (Guardrails)
- MUST NOT implement the work in multiple plans.
- MUST NOT require `sops-nix`, `agenix`, or any specific secret manager for the reusable module.
- MUST NOT read secret file contents during Nix evaluation or build.
- MUST NOT place production secret values in the Nix store.
- MUST NOT always enable or configure local PostgreSQL for consumers.
- MUST NOT expand into Docker, Kubernetes, reverse proxy, TLS, backups, monitoring, multi-node Kestra, or plugin installation management.
- MUST NOT create network-dependent automated checks.
- MUST NOT leave broken references to `../../pkgs/kestra`.

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: NO standalone flake/check infrastructure currently exists.
- **User wants tests**: Automated flake checks.
- **Framework**: Nix flake checks, NixOS module evaluation, and lightweight NixOS VM/module test.

### Automated Nix Checks
- Package build check: builds the real Kestra package derivation.
- App smoke check: verifies the wrapped executable can print help/version without starting a long-running server.
- Module evaluation check: evaluates a minimal NixOS system importing `nixosModules.kestra` without any secret-manager module.
- Example evaluation check: evaluates `nixosConfigurations.example`.
- VM/module test check: uses a fake Kestra executable to verify systemd wiring, runtime config generation, secret substitution, permissions, and optional local PostgreSQL wiring without booting the real Java service.

### Manual Execution Verification (Always Required)
Even with checks, the executor must capture manual command outputs:
```bash
nix flake show
nix build .#kestra
nix run .#kestra -- --help
nix flake check
```

---

## Task Flow

```
Task 1 → Task 2 → Task 3 → Task 4 → Task 5 → Task 6 → Task 7
                ↘ Task 8 (docs, after API stabilizes)
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 2, 3 | Package output and module API can be drafted in parallel after flake skeleton exists, but must reconcile before checks. |
| B | 6, 8 | Documentation can proceed once output names and module option names are stable. |

| Task | Depends On | Reason |
|------|------------|--------|
| 1 | none | Establishes flake skeleton and shared output names. |
| 2 | 1 | Package output must be wired through `flake.nix`. |
| 3 | 1, 2 | Module package default references package wiring. |
| 4 | 3 | Runtime/state/systemd fixes depend on finalized module API. |
| 5 | 3, 4 | Example config should use final module options. |
| 6 | 2, 3, 4, 5 | Checks validate all finalized outputs. |
| 7 | 6 | Final verification after all outputs/checks exist. |
| 8 | 3, 5 | Docs need stable public API and example. |

---

## TODOs

- [ ] 1. Add standard standalone flake skeleton

  **What to do**:
  - Create a root `flake.nix` with a minimal `nixpkgs` input.
  - Generate `flake.lock` and include it in the working tree changes.
  - Support Linux systems, defaulting to `x86_64-linux` and `aarch64-linux` unless package evaluation shows a concrete limitation.
  - Expose:
    - `packages.${system}.kestra`
    - `packages.${system}.default`
    - `apps.${system}.default`
    - `nixosModules.kestra`
    - `nixosModules.default`
    - `nixosConfigurations.example`
    - `checks.${system}.*`
  - Use a plain flake output style; do not require flake-parts.

  **Must NOT do**:
  - Do not add `sops-nix` as a required flake input for the reusable module.
  - Do not create Home Manager, Darwin, Docker, or Kubernetes outputs.

  **Parallelizable**: NO.

  **References**:
  - `kestra/default.nix:1-45` - Existing package derivation to expose through `packages` and `apps`.
  - `kestra.nix:375-379` - Current flake-parts-ish export shape that should be replaced by plain flake outputs.
  - Nix flake concepts: use `nix flake show` and `nix flake check` as validation targets.

  **Acceptance Criteria**:
  - [ ] `flake.nix` exists at repo root.
  - [ ] `flake.lock` exists after input locking.
  - [ ] `nix flake show` lists package/app/module/example/check outputs.
  - [ ] No required input for `sops-nix`, `agenix`, flake-parts, Docker, or Kubernetes is introduced.

  **Evidence Required**:
  - [ ] Captured `nix flake show` output.

  **Commit**: NO (group with final commit strategy unless user requests commits).

- [ ] 2. Wire and harden the Kestra package output

  **What to do**:
  - Expose `kestra/default.nix` as `packages.${system}.kestra` and `packages.${system}.default`.
  - Expose an app that runs the wrapped `kestra` executable.
  - Review `kestra/default.nix` JRE choice:
    - Kestra docs require JVM 21+.
    - Prefer a Java 21 LTS Temurin runtime unless there is evidence the pinned Kestra version needs Java 25.
  - Keep the current Kestra version `1.3.22` unless the build/hash fails or the user explicitly asks for an update.
  - Ensure metadata remains Linux-only if the wrapped binary/package is Linux-only.

  **Must NOT do**:
  - Do not fetch from network in checks beyond normal fixed-output derivation fetch behavior.
  - Do not change Kestra version opportunistically without a reason.

  **Parallelizable**: YES, after Task 1, with Task 3 draft work.

  **References**:
  - `kestra/default.nix:10-11` - Current version and JRE selection.
  - `kestra/default.nix:17-20` - Fixed-output upstream release download and hash.
  - `kestra/default.nix:31-33` - Wrapper command shape.
  - Kestra docs standalone JAR requirement: JVM 21+, executable command supports `server standalone`.

  **Acceptance Criteria**:
  - [ ] `nix build .#kestra` succeeds.
  - [ ] `nix build .#default` succeeds or resolves to the same package.
  - [ ] `nix run .#kestra -- --help` or `nix run . -- --help` exits successfully or prints expected Kestra CLI help.
  - [ ] Package metadata includes homepage, license, platforms, and main program.

  **Evidence Required**:
  - [ ] Captured `nix build .#kestra` output.
  - [ ] Captured CLI help/smoke command output.

  **Commit**: NO.

- [ ] 3. Refactor `kestra.nix` into a plain reusable NixOS module

  **What to do**:
  - Make `kestra.nix` directly return the NixOS module function instead of a wrapper containing `flake.modules.nixos.servicesKestra`.
  - Export it from `flake.nix` as `nixosModules.kestra` and `nixosModules.default`.
  - Preserve namespace `services.kestra`.
  - Fix `services.kestra.package` default to use the local flake package wiring rather than `../../pkgs/kestra`.
  - Keep `settings` as a raw YAML-rendered attrset using `pkgs.formats.yaml {}`.
  - Replace sops-specific options with secret-manager-agnostic file-path options:
    - `databasePasswordFile`
    - `encryptionSecretKeyFile`
    - `jdbcSecretKeyFile`
  - Add an option such as `secretUnitDependencies` defaulting to `[]` for users who need `sops-secrets.target`, agenix units, or other secret providers.
  - Add an option such as `configurePostgresql` defaulting to `false` so local PostgreSQL management is opt-in.

  **Must NOT do**:
  - Do not reference `config.sops.secrets` in the generic module.
  - Do not define `sops.secrets` from the generic module.
  - Do not hard-require `sops-secrets.target`.
  - Do not require local PostgreSQL unless `configurePostgresql = true`.

  **Parallelizable**: YES, after Task 1, with Task 2; must finish before Task 4.

  **References**:
  - `kestra.nix:78-184` - Current `services.kestra` option structure to preserve/refine.
  - `kestra.nix:83-84` - Broken package default path to replace.
  - `kestra.nix:88-107` - Existing `settings` option and secret leaf convention.
  - `kestra.nix:133-149` - Current sops secret name options to replace with file-path options.
  - `kestra.nix:186-214` - Default settings construction and secret substitution flow.
  - `kestra.nix:222-237` - Current sops-specific declarations to remove from generic module.
  - `kestra.nix:240-258` - Current PostgreSQL management to guard behind an opt-in option.

  **Acceptance Criteria**:
  - [ ] Importing `nixosModules.kestra` in a minimal NixOS evaluation succeeds without importing sops-nix.
  - [ ] `services.kestra.package` defaults to the local flake package.
  - [ ] `configurePostgresql = false` does not enable or mutate `services.postgresql`.
  - [ ] `configurePostgresql = true` configures the local database/user/password initialization path.
  - [ ] Secret file options are runtime paths and are not read at evaluation time.
  - [ ] No `config.sops`, `sops.secrets`, or mandatory `sops-secrets.target` reference remains in the reusable module.

  **Evidence Required**:
  - [ ] Captured module evaluation/check output.
  - [ ] Search output showing no generic-module references to `config.sops` or `sops.secrets`.

  **Commit**: NO.

- [ ] 4. Fix systemd runtime, state, plugin, and secret-substitution behavior

  **What to do**:
  - Ensure `/run/kestra` is managed by systemd using `RuntimeDirectory = "kestra"` and an appropriate mode when `runtimeConfigFile` defaults under `/run/kestra`.
  - Ensure generated runtime config containing secrets is mode `0600` and owned by the Kestra service user/group.
  - Use secure generation semantics, such as restrictive umask and atomic write/rename, so the config is never briefly world-readable.
  - Fail clearly if required secret files are missing or unreadable at service start.
  - Strip trailing newline from secret files consistently, preserving special characters safely in YAML output.
  - Pick one source of truth for state directory management:
    - Either derive `stateDir` from systemd `StateDirectory`, or
    - Manage absolute `stateDir` explicitly without hardcoded `StateDirectory = "kestra"` divergence.
  - Keep default plugin path under `stateDir` manageable.
  - If a custom `pluginPath` is provided, do not blindly `mkdir`/`chmod` it if it may be read-only/store-backed; add a management option or only manage the default plugin path.
  - Ensure systemd `after`/`wants`/`requires` include optional `secretUnitDependencies` and local PostgreSQL dependencies only when configured.

  **Must NOT do**:
  - Do not write production secret contents into the Nix store.
  - Do not hardcode `StateDirectory = "kestra"` while allowing arbitrary `stateDir` with different semantics.
  - Do not assume a custom plugin path is writable.

  **Parallelizable**: NO, depends on Task 3.

  **References**:
  - `kestra.nix:12-15` - Existing default plugin path calculation.
  - `kestra.nix:17-76` - Existing recursive secret substitution helper to preserve/test.
  - `kestra.nix:163-183` - Existing state/plugin/runtime path options.
  - `kestra.nix:260-293` - Existing database init systemd service to guard behind local PostgreSQL option.
  - `kestra.nix:295-371` - Existing Kestra systemd unit, preStart, environment, ExecStart, and directory settings.
  - Kestra docs systemd guidance: simple service, restart, `KillMode=mixed`, `TimeoutStopSec=150`, `SuccessExitStatus=143`.

  **Acceptance Criteria**:
  - [ ] Runtime directory exists before config generation in the VM/module test.
  - [ ] Generated runtime config path is outside the Nix store.
  - [ ] Generated runtime config permissions are `0600`.
  - [ ] Generated runtime config is owned by the Kestra service user/group.
  - [ ] Missing secret files cause a clear service start failure.
  - [ ] Nested secret leaves in attrsets and lists are substituted correctly.
  - [ ] `KESTRA_PLUGINS_PATH` and `--plugins` point to the effective plugin path.
  - [ ] Custom plugin path behavior is documented and does not assume store paths are writable.

  **Evidence Required**:
  - [ ] Captured VM/module test output proving config path, permissions, and command args.

  **Commit**: NO.

- [ ] 5. Add runnable example NixOS configuration

  **What to do**:
  - Add `nixosConfigurations.example` in `flake.nix`.
  - Import the local `nixosModules.kestra`.
  - Enable `services.kestra`.
  - Enable `configurePostgresql = true` for a local standalone demo.
  - Provide demo-only secret files in a way that is clearly insecure and not recommended for production.
  - Keep production examples secret-manager agnostic and point to runtime files.
  - Include optional sops-nix wiring as documentation/snippet only, not as a required flake input for the generic module.

  **Must NOT do**:
  - Do not imply demo secrets are production-safe.
  - Do not require a particular hostname or hardware configuration beyond what is needed for evaluation.
  - Do not turn the example into a full production server with reverse proxy/TLS/backups.

  **Parallelizable**: NO, depends on module API and systemd behavior.

  **References**:
  - `kestra.nix:192-210` - Default Kestra settings for PostgreSQL repository/queue, local storage, encryption, and JDBC secret.
  - `kestra.nix:240-258` - PostgreSQL database/user setup behavior to exercise when `configurePostgresql = true`.
  - Official Kestra production-ish standalone config example: requires PostgreSQL repository/queue and encryption/secret keys.

  **Acceptance Criteria**:
  - [ ] `nixosConfigurations.example.config.system.build.toplevel` evaluates.
  - [ ] Example explicitly enables local PostgreSQL via the new opt-in option.
  - [ ] Example uses demo-only secret file paths with clear warnings.
  - [ ] Reusable module still evaluates without local PostgreSQL enabled.

  **Evidence Required**:
  - [ ] Captured `nix eval` or `nix build .#nixosConfigurations.example.config.system.build.toplevel` output as appropriate.

  **Commit**: NO.

- [ ] 6. Add automated flake checks and lightweight NixOS module/VM test

  **What to do**:
  - Add `checks.${system}.kestra-package` building the real package.
  - Add a module evaluation check for minimal `services.kestra` usage without sops-nix.
  - Add an example configuration evaluation check.
  - Add a lightweight NixOS VM/module test using a fake Kestra executable.
  - Fake executable should record arguments and either exit successfully for a oneshot-style test or stay alive only as long as needed for systemd assertions.
  - VM/module test should validate:
    - Kestra service unit exists.
    - Runtime config file is generated outside `/nix/store`.
    - Runtime config has secure permissions and ownership.
    - Secret substitution works for nested attrsets/lists.
    - Kestra command receives `server standalone --config <runtimeConfigFile> --plugins <pluginPath>`.
    - Local PostgreSQL wiring is present when `configurePostgresql = true`.
    - PostgreSQL wiring is absent when `configurePostgresql = false` in an eval check.

  **Must NOT do**:
  - Do not start the real Java Kestra service in VM checks unless it is trivial and deterministic.
  - Do not make checks depend on external network services.
  - Do not leak secret values into check logs beyond demo/fake values intentionally created inside the test VM.

  **Parallelizable**: NO, depends on Tasks 2-5.

  **References**:
  - `kestra.nix:315-359` - preStart and ExecStart behavior to test with fake executable.
  - `kestra.nix:354-357` - environment variables including `KESTRA_PLUGINS_PATH`.
  - `kestra.nix:349-370` - service config and directory permissions.
  - NixOS VM tests are appropriate for validating systemd wiring without running the real service.

  **Acceptance Criteria**:
  - [ ] `nix flake check` runs all checks successfully.
  - [ ] Package check builds real Kestra package.
  - [ ] Module eval check proves no sops-nix dependency.
  - [ ] Example eval check succeeds.
  - [ ] VM/module check verifies service command args, generated config location, mode, ownership, and secret substitution.
  - [ ] A negative/eval assertion verifies `configurePostgresql = false` does not enable local PostgreSQL.

  **Evidence Required**:
  - [ ] Captured `nix flake check` output.

  **Commit**: NO.

- [ ] 7. Run final verification and inspect for forbidden coupling/scope creep

  **What to do**:
  - Run final validation commands:
    ```bash
    nix flake show
    nix build .#kestra
    nix run .#kestra -- --help
    nix flake check
    ```
  - Search the generic module for forbidden coupling:
    - `config.sops`
    - `sops.secrets`
    - mandatory `sops-secrets.target`
    - `../../pkgs/kestra`
  - Inspect the flake outputs for unintended expansions such as Docker/Kubernetes/Home Manager/Darwin support.
  - Confirm no production secret value is committed.

  **Must NOT do**:
  - Do not skip evidence capture.
  - Do not commit generated local result symlinks.

  **Parallelizable**: NO, final gate.

  **References**:
  - `.gitignore` - Should ignore Nix build outputs/result symlinks if already configured; update only if needed.
  - Full repo after implementation - Search for forbidden strings and accidental secret values.

  **Acceptance Criteria**:
  - [ ] All final validation commands pass.
  - [ ] Forbidden sops-specific references are absent from the generic module.
  - [ ] `../../pkgs/kestra` is absent.
  - [ ] No unintended scope expansion outputs are present.
  - [ ] No real secrets are committed.

  **Evidence Required**:
  - [ ] Captured command output for every final validation command.
  - [ ] Captured search results or explicit note that no matches were found.

  **Commit**: NO.

- [ ] 8. Document usage and optional secret-manager integration

  **What to do**:
  - Add or update Markdown documentation, preferably `README.md` if no project docs exist.
  - Include package usage:
    ```bash
    nix run .#kestra -- --help
    nix build .#kestra
    ```
  - Include module usage via `nixosModules.kestra`.
  - Include example configuration usage/evaluation.
  - Document secret file options and warn not to put production secrets in the Nix store.
  - Provide optional sops-nix snippet showing how a consumer can pass `config.sops.secrets.<name>.path` into file-path options.
  - Document local PostgreSQL option and clarify it is opt-in for reusable consumers but enabled in the runnable example.
  - Document plugin path support and explicitly state plugin installation/management is out of scope.

  **Must NOT do**:
  - Do not document demo secrets as production-safe.
  - Do not add non-Markdown docs unless required by existing repo conventions.

  **Parallelizable**: YES, after module API/example output names are stable.

  **References**:
  - Official Kestra standalone docs: installation, config with `--config`, plugin path behavior, systemd service behavior.
  - `flake.nix` final outputs - Document exact output names.
  - `kestra.nix` final options - Document exact option names.

  **Acceptance Criteria**:
  - [ ] Documentation lists all public flake outputs.
  - [ ] Documentation shows minimal module import/enable snippet.
  - [ ] Documentation shows optional sops-nix wiring without making sops-nix mandatory.
  - [ ] Documentation states plugin installation is out of scope.
  - [ ] Documentation points users to `nix flake check` for validation.

  **Evidence Required**:
  - [ ] Markdown file path and summary of documented sections.

  **Commit**: NO.

---

## Commit Strategy

The user did not request commits. Do not commit unless explicitly asked.

If commits are later requested, use atomic commits such as:

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1-2 | `feat(flake): expose kestra package and app` | `flake.nix`, `flake.lock`, `kestra/default.nix` | `nix build .#kestra`, smoke command |
| 3-5 | `feat(module): add reusable kestra nixos module` | `kestra.nix`, `flake.nix` | module/example evaluation |
| 6 | `test(flake): add kestra module checks` | `flake.nix`, test files if created | `nix flake check` |
| 8 | `docs: document kestra flake usage` | `README.md` | doc review |

---

## Success Criteria

### Verification Commands
```bash
nix flake show
# Expected: shows packages/apps/modules/nixosConfigurations/checks for supported Linux systems

nix build .#kestra
# Expected: builds the Kestra wrapper package successfully

nix run .#kestra -- --help
# Expected: prints Kestra CLI help or equivalent non-server CLI output and exits successfully

nix flake check
# Expected: all package, eval, and VM/module checks pass
```

### Final Checklist
- [ ] `flake.nix` and `flake.lock` present.
- [ ] Package/app/module/example/check outputs present.
- [ ] `services.kestra` reusable module imports without sops-nix.
- [ ] Secret handling uses runtime file paths, not evaluation/build-time secret reads.
- [ ] Local PostgreSQL is opt-in and enabled in the runnable example.
- [ ] Runtime config is generated under `/run`, outside the Nix store, with secure permissions.
- [ ] State directory handling has one source of truth.
- [ ] Plugin path behavior is safe for custom/read-only paths.
- [ ] Automated checks pass.
- [ ] Documentation explains usage, validation, secrets, local PostgreSQL, and plugin scope.
