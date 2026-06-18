#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./component-common.sh
source "$script_dir/component-common.sh"

run_git_in_repo() {
  local repo_path="$1"
  shift

  # Pre-commit hooks export repo-local Git env vars (for example GIT_DIR) that
  # break commands executed against nested repositories (submodules). Run each
  # nested-repo command in a clean Git env.
  (
    unset $(git rev-parse --local-env-vars)
    git -C "$repo_path" "$@"
  )
}

is_commit_on_remote() {
  local repo_path="$1"
  local commit_oid="$2"
  local remote_name=""
  local ref_name=""

  remote_name="$(run_git_in_repo "$repo_path" remote | head -n 1)"
  if [[ -z "$remote_name" ]]; then
    echo "No remote configured for submodule repository: $repo_path" >&2
    return 1
  fi

  if ! run_git_in_repo "$repo_path" fetch --quiet --tags "$remote_name"; then
    echo "Unable to fetch remote refs for submodule repository: $repo_path" >&2
    return 1
  fi

  while IFS= read -r ref_name; do
    if run_git_in_repo "$repo_path" merge-base --is-ancestor "$commit_oid" "$ref_name"; then
      return 0
    fi
  done < <(run_git_in_repo "$repo_path" for-each-ref --format='%(refname)' "refs/remotes/$remote_name" refs/tags)

  return 1
}

has_blockers=0
checked_gitlinks=0

while IFS= read -r -d '' staged_path; do
  stage_entry="$(git ls-files --stage -- "$staged_path")"
  stage_mode="$(awk '{print $1}' <<<"$stage_entry")"
  stage_oid="$(awk '{print $2}' <<<"$stage_entry")"

  if [[ "$stage_mode" != "160000" ]]; then
    continue
  fi

  checked_gitlinks=1

  if resolve_component_by_vendor_path "$staged_path"; then
    if [[ -f "$state_file" ]]; then
      load_edit_state "$component_id"

      if [[ $has_blockers -eq 0 ]]; then
        echo "pre-commit: staged submodule references cannot be committed while component edit sessions are active." >&2
      fi

      has_blockers=1
      echo "- component: $component_id" >&2
      echo "  staged submodule path: $component_vendor_path" >&2
      echo "  active edit branch: $EDIT_BRANCH_NAME" >&2
      echo "  inspect with: just component-status $component_id" >&2
      echo "  finish with: just component-finish $component_id" >&2
      echo "  or abort with: just component-abort $component_id" >&2
      continue
    fi
  else
    vendor_abs="$repo_root/$staged_path"
    component_id="$staged_path"
  fi

  if ! is_commit_on_remote "$vendor_abs" "$stage_oid"; then
    if [[ $has_blockers -eq 0 ]]; then
      echo "pre-commit: staged submodule references must point to commits available on the submodule remote." >&2
    fi

    has_blockers=1
    echo "- component: $component_id" >&2
    echo "  staged submodule path: $staged_path" >&2
    echo "  staged gitlink commit: $stage_oid" >&2
    echo "  The commit is not reachable from the fetched remote refs." >&2
    echo "  Push the vendor commit upstream or reset the submodule to a published commit before committing the superproject." >&2
  fi
done < <(git diff --cached --name-only -z --diff-filter=AMRT)

if [[ $checked_gitlinks -eq 0 ]]; then
  exit 0
fi

if [[ $has_blockers -ne 0 ]]; then
  exit 1
fi