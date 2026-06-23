# Decisions: Refactor Kestra Postgres Layout

## 2026-06-22 Task: session-start
- Follow `.sisyphus/plans/refactor-kestra-postgres-layout.md` as the active boulder.
- Preserve public flake outputs and Kestra package behavior.
- Use `services.kestra.database.createLocally = false` as reusable-module default; examples should opt into local PostgreSQL explicitly.
