# Issues: Standalone Kestra Flake

## 2026-06-22 Task: session-initialization
- NixOS option search did not find `systemd.services.<name>.serviceConfig.RuntimeDirectory` or `StateDirectory` as typed options, likely because `serviceConfig` is freeform systemd config. Implementers should validate through NixOS evaluation/checks rather than relying on option docs.
- AST-grep unavailable due dynamic linker issue; note for verification/search limitations.

## 2026-06-22 Task: search-synthesis
- Current runtime secret substitution uses raw string replacement in YAML (`config.replace(token, value)`), which can break for secret values containing quotes, colons, backslashes, or newlines. Later tasks should consider structured YAML-safe generation.
- `databaseHost` currently changes JDBC URL but local PostgreSQL ensure/auth/db-init still target local PostgreSQL; external database behavior must be explicit when adding `configurePostgresql`.
- `preStart` likely runs as the service user and may fail creating `/run/kestra` without `RuntimeDirectory`.

## 2026-06-22 Task: task-1-verification
- Project-level `lsp_diagnostics` on the repository root is unavailable because no LSP server is configured for an empty/default extension. File-level `flake.nix` diagnostics were clean.
