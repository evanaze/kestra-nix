# Decisions: Standalone Kestra Flake

## 2026-06-22 Task: session-initialization
- Follow the plan's reusable + runnable direction: package/app/module outputs plus `nixosConfigurations.example`.
- Keep the flake plain; do not introduce flake-parts as a required framework.
- Keep secret management file-path based and generic; do not require sops-nix.
- Make local PostgreSQL opt-in in the reusable module and enabled in the runnable example.

## 2026-06-22 Task: search-synthesis
- Keep Java 25 in package unless implementation evidence proves the pinned Kestra release works with Java 21; upstream `v1.3.22` evidence says Java 25 is required.
- For early flake skeleton, expose the current module carefully even before refactor. If needed, access current nested export as `(import ./kestra.nix).flake.modules.nixos.servicesKestra` as an interim bridge, then Task 3 will convert `kestra.nix` into a plain module.
- Prefer `lib.getExe` for app program paths.
- Do not add flake-parts, sops-nix, agenix, Docker/Kubernetes, or Home Manager/Darwin outputs.
