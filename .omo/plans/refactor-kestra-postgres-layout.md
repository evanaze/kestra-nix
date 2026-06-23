# Refactor Kestra Flake Layout and PostgreSQL Configuration

## Context

### Original Request
The user asked to review the current Kestra Nix flake implementation and suggest improvements, noting that the layout is confusing so far, especially the PostgreSQL configuration. After the review, the user asked to turn the recommendations into a work plan.

### Interview Summary
**Key Discussions**:
- Primary pain point: PostgreSQL behavior is confusing because the module exposes generic database options while unconditionally wiring local PostgreSQL.
- Desired outcome: clearer flake/module layout and an explicit local-vs-external PostgreSQL boundary.
- Planning constraint: create one plan only; do not implement directly.

**Research Findings**:
- `flake.nix` currently exposes packages/apps/checks, `nixosModules.kestra`, and `nixosConfigurations.example`.
- `kestra.nix` currently contains the entire NixOS module and exports through a flake-parts-like wrapper at `(import ./kestra.nix).flake.modules.nixos.servicesKestra`.
- `kestra.nix` currently defines flat database options: `databaseName`, `databaseUser`, `databaseHost`, `databasePort`, and `databasePasswordFile`.
- When `services.kestra.enable = true`, the module unconditionally adds `services.postgresql.ensureDatabases`, `services.postgresql.ensureUsers`, `services.postgresql.authentication`, `kestra-db-init.service`, and local PostgreSQL dependencies for `kestra.service`.
- Changing `databaseHost` currently changes the Kestra JDBC URL but does not stop the module from configuring and depending on local PostgreSQL.
- NixOS option docs: `services.postgresql.ensureUsers` uses peer authentication and does not clean up old users/ownership automatically.
- NixOS option docs: `services.postgresql.authentication` additions are inserted above defaults; `mkForce` is for replacing defaults entirely, so the current `mkOverride 10` is unnecessarily forceful.
- NixOS module convention search found many modules using `database.createLocally` for local DB provisioning boundaries.
- Official Kestra docs confirm `server standalone`, `--config`, PostgreSQL-backed `kestra.queue.type = "postgres"`, `kestra.repository.type = "postgres"`, and `datasources.postgres.*` are the relevant configuration shape.
- Prior `.sisyphus` notes explicitly intended local PostgreSQL to be opt-in in the reusable module and enabled in the runnable example.

### Metis Review
**Identified Gaps** (addressed):
- Backward compatibility needed an explicit decision: this plan treats the new nested database API as the documented API and includes compatibility aliases/shims where practical, because the repo appears in-progress but preserving easy migration is low-cost.
- `createLocally` default needed an explicit decision: this plan sets `services.kestra.database.createLocally = false` so the reusable module does not silently own PostgreSQL; the example sets it to `true`.
- Precedence needed definition: generated database defaults are merged first; `services.kestra.settings` remains the advanced raw override layer and can intentionally override generated Kestra YAML.
- Local and external database behavior need separate acceptance checks.
- Scope creep risks need locking down: no Kestra version/JRE change, no non-PostgreSQL support, no flake-parts migration, no secret-manager dependency, no TLS/client-cert scope, no plugin management.

---

## Work Objectives

### Core Objective
Refactor the Kestra flake/module structure and PostgreSQL option model so the reusable NixOS module has explicit, testable local and external PostgreSQL modes, while preserving the existing package/app/module flake outputs.

### Concrete Deliverables
- Clearer file layout separating package, module, examples, and checks.
- Plain NixOS module import path for `nixosModules.kestra`.
- Nested `services.kestra.database` option namespace.
- Explicit `database.createLocally` switch controlling all local PostgreSQL wiring.
- Local PostgreSQL mode that intentionally enables/provisions local PostgreSQL.
- External PostgreSQL mode that does not touch or depend on local PostgreSQL.
- Safer PostgreSQL auth rule merging.
- Improved secret handling plan, preferably via systemd credentials and YAML-safe runtime config generation.
- Flake checks covering package build, module evaluation, local DB mode, external DB mode, and config/secret edge cases.
- README updates documenting both local and external PostgreSQL modes plus migration from flat options.

### Definition of Done
- [ ] `nix flake show` still lists expected package/app/module/check outputs.
- [ ] `nix build .#kestra` succeeds.
- [ ] `nix run . -- --help` prints Kestra CLI help and does not start the server.
- [ ] `nix flake check` passes.
- [ ] `nixosModules.kestra` and `nixosModules.default` remain usable.
- [ ] Local PostgreSQL eval/check proves PostgreSQL is enabled and locally wired only when `database.createLocally = true`.
- [ ] External PostgreSQL eval/check proves local PostgreSQL is not configured, initialized, wanted, required, or depended on when `database.createLocally = false`.
- [ ] README clearly documents the two supported database modes.

### Must Have
- Preserve flake outputs: `packages.${system}.kestra`, `packages.${system}.default`, `apps.${system}.default`, `nixosModules.kestra`, `nixosModules.default`, `checks.${system}.*`.
- New public database namespace: `services.kestra.database`.
- `services.kestra.database.createLocally = false` by default.
- Example local PostgreSQL configuration explicitly sets `database.createLocally = true`.
- `services.kestra.settings` remains available for advanced raw Kestra YAML settings.
- Existing service name `kestra.service` remains stable.

### Must NOT Have (Guardrails)
- MUST NOT change Kestra package version, JRE version, fixed-output hash, or package behavior unless a verification failure proves it is required.
- MUST NOT introduce `flake-parts`, sops-nix, agenix, overlays, Home Manager, Darwin, Docker, Kubernetes, TLS/reverse proxy, backups, monitoring, or plugin management.
- MUST NOT configure local PostgreSQL in external DB mode.
- MUST NOT require local `postgresql.service` in external DB mode.
- MUST NOT support databases beyond PostgreSQL in this refactor.
- MUST NOT remove or rename public flake outputs.
- MUST NOT store secret values in the Nix store.
- MUST NOT rely only on README claims; local/external database semantics must be asserted by checks.

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES, flake checks already exist in `flake.nix`.
- **User wants tests**: YES, use Nix flake checks and module evaluation checks.
- **Framework**: Nix flake checks, NixOS module evaluation, package/app smoke verification.

### Automated Nix Checks
- Keep package build check for `self.packages.${system}.kestra`.
- Keep a minimal module evaluation check.
- Add/adjust a local PostgreSQL module evaluation check.
- Add an external PostgreSQL module evaluation check.
- Add a secret/config generation check or lightweight NixOS check that validates YAML-sensitive secret values do not break runtime config generation.
- Avoid network-dependent checks beyond normal fixed-output derivation behavior.

### Manual Execution Verification
The executor must capture outputs for:

```bash
nix flake show
nix build .#kestra
nix run . -- --help
nix flake check
```

---

## Task Flow

```text
Task 1 → Task 2 → Task 3 → Task 4 → Task 5 → Task 6 → Task 7
          ↘ Task 8 (docs after public API stabilizes)
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 2, 3 | Layout movement and database API drafting can proceed after existing references are mapped, but must reconcile before checks. |
| B | 6, 8 | Documentation can be finalized once checks and option names are stable. |

| Task | Depends On | Reason |
|------|------------|--------|
| 1 | none | Establishes reference map and safety baseline. |
| 2 | 1 | Moves files and updates flake imports without changing behavior. |
| 3 | 1, 2 | Introduces new module API in the final module location. |
| 4 | 3 | Implements local/external PostgreSQL behavior under the new API. |
| 5 | 3, 4 | Secret/runtime config improvements depend on finalized option paths. |
| 6 | 3, 4, 5 | Checks assert final semantics. |
| 7 | 6 | Final validation after all checks exist. |
| 8 | 3, 4, 6 | Docs need stable option names and verified examples. |

---

## TODOs

- [x] 1. Establish baseline and reference map

  **What to do**:
  - Inspect current tracked/untracked state before editing.
  - Record current flake outputs and working commands.
  - Map all references to `./kestra`, `./kestra.nix`, `nixosModules.kestra`, and database options.
  - Confirm no hidden files outside the known Nix/README/.sisyphus files need to be updated.

  **Must NOT do**:
  - Do not edit implementation yet.
  - Do not run server-starting commands.

  **Parallelizable**: NO.

  **References**:
  - `flake.nix:20-33` - Current package and app outputs.
  - `flake.nix:35-65` - Current checks and module evaluation shape.
  - `flake.nix:67-70` - Current NixOS module output bridge.
  - `flake.nix:72-100` - Current example NixOS configuration.
  - `kestra.nix:80-205` - Current service options.
  - `kestra.nix:207-394` - Current module implementation.
  - `README.md` - Current user-facing documented API.

  **Acceptance Criteria**:
  - [ ] Current outputs are recorded with `nix flake show`.
  - [ ] Existing package smoke command is identified.
  - [ ] All code/docs references to old paths and flat database options are listed.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake show`
  - [ ] Expected: output includes `packages`, `apps`, `checks`, `nixosModules`, and `nixosConfigurations.example`.

  **Evidence Required**:
  - [ ] Captured command output.

  **Commit**: NO.

- [ ] 2. Normalize repository layout without changing behavior

  **What to do**:
  - Move package derivation from `kestra/default.nix` to `pkgs/kestra/default.nix`, or keep a compatibility path if moving would cause unnecessary churn.
  - Move the service module from root `kestra.nix` to `modules/services/kestra/default.nix`.
  - Update `flake.nix` so `nixosModules.kestra = import ./modules/services/kestra` directly.
  - Update package calls to the final package path.
  - If preserving old root `kestra.nix`, make it a minimal compatibility shim only, not the primary implementation.
  - Keep public flake outputs unchanged.

  **Must NOT do**:
  - Do not introduce flake-parts.
  - Do not change package version/JRE/hash.
  - Do not change module behavior in this task except import paths.

  **Parallelizable**: YES, with Task 3 after Task 1.

  **References**:
  - `kestra/default.nix:10-20` - Current Kestra version, JRE, URL, and hash that must not change.
  - `kestra/default.nix:31-44` - Current wrapper and metadata that must be preserved.
  - `flake.nix:22` - Current package call path.
  - `flake.nix:67-70` - Current module output path that should become a plain module import.
  - `.sisyphus/drafts/kestra-nix-flake-review.md` - Review rationale for clearer layout.

  **Acceptance Criteria**:
  - [ ] `nixosModules.kestra` imports a plain NixOS module path.
  - [ ] Package/app outputs still resolve.
  - [ ] No flake output names are removed or renamed.
  - [ ] No package version/JRE/hash changes are present.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake show`
  - [ ] Expected: same public output categories as before.
  - [ ] Run: `nix build .#kestra`
  - [ ] Expected: build succeeds.

  **Evidence Required**:
  - [ ] Captured `nix flake show` and `nix build .#kestra` output.

  **Commit**: NO.

- [ ] 3. Introduce nested database option API

  **What to do**:
  - Add `services.kestra.database` option namespace with:
    - `createLocally` defaulting to `false`.
    - `host` defaulting to `127.0.0.1`.
    - `port` defaulting to `5432`.
    - `name` defaulting to `kestra`.
    - `user` defaulting to `kestra`.
    - `passwordFile` defaulting to `/run/secrets/kestra/db-password`.
    - Optional `jdbcUrl` defaulting to `null` for full JDBC URL override.
  - Define precedence clearly in option descriptions:
    - Database convenience options generate default Kestra datasource settings.
    - `database.jdbcUrl` overrides the generated JDBC URL from host/port/name.
    - `services.kestra.settings` is merged last and can intentionally override generated Kestra settings.
  - Provide compatibility aliases or clear migration assertions for old flat options where practical:
    - `databaseName` → `database.name`
    - `databaseUser` → `database.user`
    - `databaseHost` → `database.host`
    - `databasePort` → `database.port`
    - `databasePasswordFile` → `database.passwordFile`
  - Update default settings generation to use `cfg.database.*`.

  **Must NOT do**:
  - Do not remove `services.kestra.settings`.
  - Do not model the entire Kestra YAML schema as NixOS options.
  - Do not add non-PostgreSQL options.

  **Parallelizable**: YES, with Task 2 after Task 1, but final merge depends on Task 2 path decisions.

  **References**:
  - `kestra.nix:90-109` - Current raw `settings` option and secret leaf convention.
  - `kestra.nix:111-144` - Current flat database options to nest/migrate.
  - `kestra.nix:213-231` - Current default Kestra PostgreSQL datasource settings.
  - NixOS convention references: `services.keycloak.database.*`, `services.castopod.database.*`, and `database.createLocally` patterns.
  - Official Kestra runtime/storage docs - Required PostgreSQL config shape.

  **Acceptance Criteria**:
  - [ ] New nested database options exist and have clear descriptions.
  - [ ] Default generated Kestra settings match existing PostgreSQL-backed standalone behavior.
  - [ ] `database.jdbcUrl` precedence is documented and implemented.
  - [ ] `services.kestra.settings` override precedence is documented and implemented.
  - [ ] Old flat options are either supported as aliases with migration notes or rejected with clear assertions/warnings.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake check`
  - [ ] Expected: module option evaluation succeeds.

  **Evidence Required**:
  - [ ] Captured check output.

  **Commit**: NO.

- [ ] 4. Split local and external PostgreSQL behavior

  **What to do**:
  - Gate all local PostgreSQL provisioning behind `cfg.database.createLocally`.
  - In local mode:
    - Enable `services.postgresql.enable = true`.
    - Add `services.postgresql.ensureDatabases = [ cfg.database.name ]`.
    - Add `services.postgresql.ensureUsers` for `cfg.database.user`.
    - Set ownership/login clauses as currently intended.
    - Add PostgreSQL auth rules using normal merge priority, not `mkOverride 10`.
    - Define `kestra-db-init.service` to set password and owner.
    - Make `kestra.service` depend on local PostgreSQL and DB init.
  - In external mode:
    - Do not set `services.postgresql.enable`.
    - Do not add `ensureDatabases`, `ensureUsers`, or PostgreSQL auth rules.
    - Do not define `kestra-db-init.service`.
    - Do not require/want `postgresql.service` or `kestra-db-init.service` from `kestra.service`.
    - Ensure `kestra.service` still starts after network targets appropriate for external database access.
  - Add assertions for invalid combinations, for example local mode with non-local host if not supported.
  - Decide and document local mode port behavior: either configure PostgreSQL to `database.port` or assert that local mode uses the configured PostgreSQL/default port consistently.

  **Must NOT do**:
  - Do not configure local PostgreSQL in external mode.
  - Do not use `mkForce`/forceful overrides for auth unless replacing the entire user config is explicitly required.
  - Do not create/delete actual databases outside NixOS PostgreSQL mechanisms and the existing password/owner init purpose.

  **Parallelizable**: NO, depends on Task 3.

  **References**:
  - `kestra.nix:248-266` - Current unconditional PostgreSQL module config.
  - `kestra.nix:268-299` - Current `kestra-db-init.service`.
  - `kestra.nix:301-316` - Current `kestra.service` local PostgreSQL dependencies.
  - NixOS `services.postgresql.ensureUsers` docs - Ownership/login behavior and cleanup caveat.
  - NixOS `services.postgresql.authentication` docs - Merge behavior and default rule ordering.
  - `.sisyphus/notepads/standalone-kestra-flake/decisions.md:7` - Prior decision: local PostgreSQL opt-in in reusable module and enabled in example.

  **Acceptance Criteria**:
  - [ ] Local mode eval proves `services.postgresql.enable = true`.
  - [ ] Local mode eval proves `ensureDatabases` includes the Kestra database.
  - [ ] Local mode eval proves `ensureUsers` includes the Kestra DB user.
  - [ ] Local mode eval proves `kestra-db-init.service` exists.
  - [ ] Local mode eval proves `kestra.service` requires/wants or orders after local DB init/PostgreSQL as intended.
  - [ ] External mode eval proves no `kestra-db-init.service` exists.
  - [ ] External mode eval proves local PostgreSQL options are untouched by the Kestra module.
  - [ ] External mode eval proves `kestra.service` has no local PostgreSQL dependency.
  - [ ] PostgreSQL auth rules are merged without `mkOverride 10`.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake check`
  - [ ] Expected: local and external DB module checks pass.

  **Evidence Required**:
  - [ ] Captured check output showing local and external DB checks.

  **Commit**: NO.

- [ ] 5. Improve runtime secret and config generation safety

  **What to do**:
  - Review current runtime config generation and identify how to avoid raw YAML token replacement breaking YAML-sensitive values.
  - Prefer systemd `LoadCredential` for configured secret files so services read credential copies instead of requiring broad source-file readability.
  - Ensure DB password, encryption secret key, JDBC secret key, and arbitrary `settings.*._secret` leaves remain runtime-only and are not read at Nix evaluation/build time.
  - Ensure generated runtime config remains under `/run`, mode `0600`, readable by the Kestra service user only.
  - Add checks or test fixtures with YAML-sensitive secret values such as `abc: def`, quotes, `#comment`, backslashes, and newline cases.
  - Keep secret-manager agnostic behavior: sops-nix/agenix/manual files should all work as input file providers.

  **Must NOT do**:
  - Do not add sops-nix/agenix as flake inputs or required modules.
  - Do not place secret contents in generated Nix store files.
  - Do not remove arbitrary `_secret` leaf support unless replaced by an equivalent documented mechanism.

  **Parallelizable**: NO, depends on finalized option paths from Task 3 and mode behavior from Task 4.

  **References**:
  - `kestra.nix:19-78` - Current `_secret` detection and token substitution data structure.
  - `kestra.nix:200-203` - Current `runtimeConfigFile` option.
  - `kestra.nix:318-365` - Current preStart runtime YAML generation and raw replacement script.
  - `README.md` secrets section - Current documented readability requirements.
  - NixOS examples: `services.castopod.database.passwordFile` and `services.nextcloud.secrets` use systemd credentials/secret loading patterns.

  **Acceptance Criteria**:
  - [ ] Secret files are read only at service runtime.
  - [ ] Generated runtime config is not in the Nix store.
  - [ ] Runtime config remains mode `0600`.
  - [ ] YAML-sensitive secret values are represented safely in generated config.
  - [ ] README no longer requires awkward shared readability between `postgres` and `kestra` unless still strictly necessary for local DB init.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake check`
  - [ ] Expected: secret/config generation check passes.

  **Evidence Required**:
  - [ ] Captured check output.

  **Commit**: NO.

- [ ] 6. Add/adjust flake checks for behavior regressions

  **What to do**:
  - Keep existing package build check.
  - Add a module eval check for default/external mode.
  - Add a module eval check for explicit local PostgreSQL mode.
  - Add checks that inspect generated systemd unit text or evaluated config for service dependencies.
  - Add checks that assert external mode does not define local DB init or local PostgreSQL dependencies.
  - Add checks that assert local mode defines the intended local DB services/options.
  - Add checks for old-option compatibility or migration failure messages, depending on Task 3 decision.
  - Keep checks lightweight and non-network-dependent.

  **Must NOT do**:
  - Do not require booting real Kestra.
  - Do not require real production secrets.
  - Do not introduce slow VM tests unless a lightweight check cannot verify the behavior.

  **Parallelizable**: YES, with docs after Task 4/5 interfaces stabilize.

  **References**:
  - `flake.nix:35-65` - Current checks pattern using module evaluation and unit text.
  - `flake.nix:37-39` - Current fake Kestra executable for module checks.
  - `kestra.nix:301-391` - Systemd unit text fields to assert.
  - `.sisyphus/plans/standalone-kestra-flake.md:104-109` - Prior intended automated Nix checks.

  **Acceptance Criteria**:
  - [ ] `checks.${system}.kestra-package` or equivalent still builds the package.
  - [ ] A local DB check validates local PostgreSQL wiring.
  - [ ] An external DB check validates absence of local PostgreSQL wiring.
  - [ ] A config/secret check validates runtime config generation behavior.
  - [ ] `nix flake check` passes for supported systems or clearly documents any system-specific limitation.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake check`
  - [ ] Expected: all checks pass.

  **Evidence Required**:
  - [ ] Captured full check output.

  **Commit**: NO.

- [ ] 7. Final validation and regression sweep

  **What to do**:
  - Run the package/app/check commands.
  - Inspect the diff to confirm only intended files changed.
  - Confirm no secret values, local machine paths, or accidental generated artifacts were added.
  - Confirm the old confusing behavior is gone: external mode must not create local PostgreSQL coupling.
  - Confirm local mode remains turnkey when explicitly enabled.

  **Must NOT do**:
  - Do not commit unless the user explicitly asks.
  - Do not force-push, amend, or change git config.

  **Parallelizable**: NO, final gate.

  **References**:
  - All changed files.
  - `.gitignore` - Ensure generated artifacts remain ignored where appropriate.
  - README examples - Ensure commands and option names match implementation.

  **Acceptance Criteria**:
  - [ ] `nix flake show` succeeds.
  - [ ] `nix build .#kestra` succeeds.
  - [ ] `nix run . -- --help` succeeds or prints expected help.
  - [ ] `nix flake check` succeeds.
  - [ ] Diff contains no Kestra version/JRE/hash change unless justified by test failure.
  - [ ] Diff contains no new secret manager dependency.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake show`
  - [ ] Run: `nix build .#kestra`
  - [ ] Run: `nix run . -- --help`
  - [ ] Run: `nix flake check`

  **Evidence Required**:
  - [ ] Captured outputs for all commands.

  **Commit**: NO.

- [ ] 8. Update documentation and migration notes

  **What to do**:
  - Update README layout description to match final files.
  - Document local PostgreSQL mode with explicit `database.createLocally = true`.
  - Document external PostgreSQL mode with `database.createLocally = false`.
  - Document option precedence between `database.*`, `database.jdbcUrl`, and `settings`.
  - Document migration from old flat options to new nested options.
  - Document secret file expectations after LoadCredential/runtime config changes.
  - Keep examples minimal and avoid production-only expansion into reverse proxy/TLS/backups/monitoring.

  **Must NOT do**:
  - Do not add sops-nix as a required dependency.
  - Do not document unsupported DBs or deployment topologies.
  - Do not leave examples that imply local PostgreSQL is automatic without `createLocally = true`.

  **Parallelizable**: YES, with Task 6 after option/API behavior stabilizes.

  **References**:
  - `README.md` NixOS module section - Current usage example.
  - `README.md` Secrets section - Current shared readability guidance.
  - `README.md` Validation section - Current commands.
  - Final module option descriptions from Tasks 3-5.

  **Acceptance Criteria**:
  - [ ] README has one local PostgreSQL example.
  - [ ] README has one external PostgreSQL example.
  - [ ] README migration notes map old flat options to new nested options.
  - [ ] README validation commands match final checks.
  - [ ] README does not claim support for out-of-scope features.

  **Manual Execution Verification**:
  - [ ] Run: `nix flake check`
  - [ ] Expected: examples referenced by docs are covered by eval checks or are syntactically consistent with checked snippets.

  **Evidence Required**:
  - [ ] Captured check output.

  **Commit**: NO.

---

## Commit Strategy

No commits unless explicitly requested by the user. If the user asks for commits, use one final atomic commit after verification.

Suggested message:

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| Final | `refactor(module): clarify kestra postgres configuration` | flake/module/package/docs/check files | `nix flake check` |

---

## Success Criteria

### Verification Commands

```bash
nix flake show
nix build .#kestra
nix run . -- --help
nix flake check
```

### Final Checklist
- [ ] Package behavior unchanged.
- [ ] Public flake outputs preserved.
- [ ] Module layout is plain and discoverable.
- [ ] New database API is nested under `services.kestra.database`.
- [ ] Local PostgreSQL is explicit via `database.createLocally = true`.
- [ ] External PostgreSQL mode has no local PostgreSQL coupling.
- [ ] PostgreSQL auth merging is not overly forceful.
- [ ] Runtime secrets remain out of the Nix store.
- [ ] README documents local and external database modes clearly.
