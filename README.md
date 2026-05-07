# desktop-os-2

Monorepo scaffold for a custom BlueBuild-based desktop image.

## Layout

- `bluebuild/` contains the BlueBuild recipe tree and image-facing filesystem inputs.
- `.github/workflows/` contains CI validation and image publish workflows.
- `.githooks/` stores the versioned Git hooks that `just setup` installs.
- `.work/` is transient local state used by render and component edit helpers.
- `vendor/` is reserved for upstream Git submodules.
- `patches/` stores local patch queues that mirror `vendor/`.
- `manifests/components.yml` is the source of truth for rendered components.
- `scripts/` contains deterministic local and CI helpers.

## Current Status

This repository is bootstrapped around a manifest-driven component workflow.

- The image recipe exists and is ready to evolve.
- Renovate configuration is checked in for dependency updates.
- The component manifest currently defines one GNOME extension component: `dash-to-panel`.
- The `dash-to-panel` submodule is configured in `.gitmodules` under `vendor/extensions/dash-to-panel` and tracks the upstream `v73` branch.
- The generated tree is disposable output and is normally populated by `just prepare`, not committed as source of truth.

Component manifests define `id`, `type`, and `install_dir`. The workflow derives `vendor/` and `patches/` locations from `id`, so a `gnome-extension` with id `dash-to-panel` maps to `vendor/extensions/dash-to-panel` and `patches/extensions/dash-to-panel` automatically.

## Local Workflow

Use the `justfile` entrypoints. For normal local work, you only need `setup`, `prepare`, `component-edit`, `component-finish`, `component-status`, `build`, and `switch`.

- `just setup` installs the versioned git hooks, syncs and initializes submodules, and prepares the generated filesystem tree.
- `just prepare [component]` regenerates the full generated tree or rerenders one component in place from the manifest, vendor checkout, and patch queue.
- `just generate` runs `bluebuild generate -d` when the BlueBuild CLI is available locally.
- `just build` and `just switch` defer to the local BlueBuild CLI.
- `just component-list` prints the known component ids from `manifests/components.yml`.
- `just component-status [component]` shows active edit sessions, current branch state, and component paths.
- `just component-edit <component>` creates a temporary vendor branch, records the patch base automatically, and replays the current patch queue onto that branch before you edit.
- `just component-finish <component>` exports the committed edit branch back into `patches/`, resets the vendor checkout, and rerenders only that component.
- `just component-abort <component>` drops an in-progress edit session without refreshing patches.

Maintenance helpers that you usually do not need in the normal edit loop:

- `just install-git-hooks` repoints Git at `.githooks/` explicitly.
- `just sync-submodules` resyncs the repo to the gitlinks pinned in the superproject.
- `just update-submodules` updates submodules from upstream when you are intentionally bumping them.
- `just refresh-patches <component> [base-ref]` exports patches directly without finishing an edit session. Keep this as an expert-only helper.
- `just clean-generated` clears `bluebuild/files/generated/` when you need to force a fresh rerender.

## Editing Vendor Modules

Use the scripted edit session helpers instead of carrying the base ref and branch lifecycle by hand. Each edit session starts from the pinned upstream commit and then reapplies the current patch queue, so new work is stacked on top of the existing series rather than replacing it.

If the vendor checkout does not exist locally yet, run `just setup` or `just sync-submodules` first. If the generated extension tree is missing, run `just prepare` before treating that as a repository problem.

### Example: `dash-to-panel`

1. Start a temporary edit session.

```bash
just component-edit dash-to-panel
```

2. Edit the vendored source in place.

```bash
$EDITOR vendor/extensions/dash-to-panel/src/panel.js
```

3. Commit the change inside the vendored repository.

```bash
git -C vendor/extensions/dash-to-panel add src/panel.js
git -C vendor/extensions/dash-to-panel commit -m "fix: keep secondary monitor taskbars visible when overview opens"
```

4. Finish the edit session.

```bash
just component-finish dash-to-panel
```

That single command refreshes the patch queue, resets the submodule back to the pinned upstream commit, deletes the temporary edit branch, and rerenders that component into the generated tree.

5. If you want to discard the temporary edit branch instead, use:

```bash
just component-abort dash-to-panel
```

### Rules For This Workflow

- Treat the vendor repository branch as a temporary editing surface only.
- Do not keep long-lived local branches under `vendor/` as the source of truth.
- Commit the edits in the vendor repository before exporting patches.
- An empty `patches/` directory for a component is valid when no local patch queue has been exported yet.
- Use `just component-status` when you need to inspect active edit sessions instead of reading `.work/` directly.
- Let `just component-finish` rerender `bluebuild/files/generated/` after every patch refresh.
- If you later update the submodule to a newer upstream commit, refresh the patch queue again from the new base.
- The pre-commit hook blocks staged submodule gitlink changes for components that still have an active edit session.
- The pre-commit hook also rejects staged submodule gitlink commits that are not reachable from the fetched remote refs, which catches accidental local-only vendor commits.

## CI And Validation

- Pull request and nightly validation workflows check out submodules recursively and run `scripts/prepare-components.sh` before asserting scaffold invariants.
- The image build workflow in `.github/workflows/build.yml` prepares the generated tree and publishes `ghcr.io/<owner>/desktop-os:latest`.
- The build workflow also supports manual runs through GitHub Actions `workflow_dispatch` on `main`.
- There is no separate top-level test suite documented today, so the narrowest relevant validation step is usually `just prepare [component]`.

## Repository Rules

- Treat `vendor/` as upstream-only state.
- Keep local changes in `patches/`, not in submodule worktrees.
- Treat `bluebuild/files/generated/` as disposable output.
- Refresh patches when upstream changes break application instead of editing generated output.
- Do not infer manifest drift from a missing local submodule checkout or empty generated tree before running the setup or prepare workflow.