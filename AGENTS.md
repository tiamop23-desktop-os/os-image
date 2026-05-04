# AGENTS.md

Start with [README.md](README.md). It documents the normal developer workflow and the vendored component edit cycle in more detail.

## Repository Shape

- `manifests/components.yml` is the source of truth for component ids, types, and generated install destinations; vendor and patch paths are derived from component ids.
- `vendor/` contains upstream submodules after `just setup` or `just sync-submodules`. Treat it as upstream state, not the long-term home of local changes.
- `patches/` contains the local patch queues that define this repo's customizations. A component may legitimately have no exported patches yet.
- `bluebuild/files/generated/` is rendered output and may be empty until `just prepare` runs. Do not hand-edit it.
- `.work/` contains transient edit-session and render state.
- `.githooks/` contains the versioned Git hooks installed by `just install-git-hooks`.
- `scripts/` contains the manifest-driven render and vendor-edit helpers.

## Preferred Commands

- Use `just setup` for first-time local setup.
- Use `just prepare [component]` after manifest or patch changes to rerender generated output.
- Use `just component-list` to inspect the component ids defined in the manifest.
- Use `just component-status [component]` to inspect active edit sessions.
- Use `just component-edit <component>` before changing vendored source.
- After committing inside the vendored repo, use `just component-finish <component>` to refresh patches and rerender that component.
- Use `just component-abort <component>` only to discard an in-progress vendor edit session.
- Use `just refresh-patches <component> [base-ref]` only when you need to export a patch queue without finishing an edit session.

## Rules That Matter

- Do not edit `bluebuild/files/generated/` directly. Regenerate it.
- Do not keep local source-of-truth changes only inside `vendor/`. Export them back to `patches/` through the component workflow.
- Do not hand-manage temporary vendor branches when the `just component-*` helpers cover the workflow.
- If you change a vendored component, commit inside the submodule before running `just component-finish <component>`.
- If an edit session exists, inspect it with `just component-status` instead of reading `.work/` directly.
- If a vendor checkout is missing locally, run `just setup` or `just sync-submodules` before assuming the manifest is wrong.
- Prefer touching the smallest source-of-truth surface: `manifests/components.yml`, `patches/`, or the vendored source being patched.

## Build And Tooling Notes

- User-facing task entrypoints live in `justfile`.
- `just build`, `just switch`, and `just generate` require a local `bluebuild` CLI.
- CI workflows also validate the scaffold by checking out submodules recursively and running `scripts/prepare-components.sh`.
- There is no separate top-level test suite documented today; validate changes with the narrowest relevant workflow command.

## Useful References

- [README.md](README.md)
- [justfile](justfile)
- [manifests/components.yml](manifests/components.yml)
- [scripts/component-common.sh](scripts/component-common.sh)