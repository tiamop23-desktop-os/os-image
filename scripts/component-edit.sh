#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./component-common.sh
source "$script_dir/component-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  component-edit.sh start <component-id> [branch-name]
  component-edit.sh finish <component-id>
  component-edit.sh abort <component-id>
  component-edit.sh refresh <component-id> [base-ref]
  component-edit.sh status [component-id]
  component-edit.sh list
EOF
}

refresh_patches() {
  local component_id="$1"
  local base_ref="${2:-}"

  require_component "$component_id"
  ensure_vendor_repo "$component_id"

  if [[ -z "$base_ref" ]]; then
    load_edit_state "$component_id"
    base_ref="$EDIT_BASE_REF"
  fi

  require_clean_vendor_repo
  export_patch_series "$vendor_abs" "$patches_abs" "$base_ref" "$component_id"

  echo "Wrote patch series for $component_id to $component_patches_path"
}

start_edit() {
  local component_id="$1"
  local branch_name="${2:-}"
  local current_branch=""
  local base_ref=""

  require_component "$component_id"
  ensure_vendor_repo "$component_id"

  if [[ -f "$state_file" ]]; then
    load_edit_state "$component_id"
    echo "Edit session already active for $component_id on branch $EDIT_BRANCH_NAME" >&2
    exit 1
  fi

  require_clean_vendor_repo

  current_branch="$(git -C "$vendor_abs" branch --show-current)"
  if [[ -n "$current_branch" ]]; then
    echo "Vendor repository is already on branch $current_branch; detach or finish that work first." >&2
    exit 1
  fi

  base_ref="$(git -C "$vendor_abs" rev-parse HEAD)"
  if [[ -z "$branch_name" ]]; then
    branch_name="patch/$component_id-$(date +%Y%m%d%H%M%S)"
  fi

  if git -C "$vendor_abs" rev-parse --verify --quiet "$branch_name" >/dev/null 2>&1; then
    echo "Branch already exists in $component_vendor_path: $branch_name" >&2
    exit 1
  fi

  git -C "$vendor_abs" switch -c "$branch_name" "$base_ref" >/dev/null

  if ! apply_existing_patches; then
    git -C "$vendor_abs" switch --detach "$base_ref" >/dev/null 2>&1 || true
    git -C "$vendor_abs" branch -D "$branch_name" >/dev/null 2>&1 || true
    exit 1
  fi

  write_edit_state "$component_id" "$base_ref" "$branch_name"

  echo "Started edit session for $component_id"
  echo "Vendor path: $component_vendor_path"
  echo "Branch: $branch_name"
  echo "Base ref: $base_ref"
  echo "Existing patches replayed onto edit branch before you start editing"
  echo "Next: edit files, commit inside $component_vendor_path, then run: just component-finish $component_id"
}

finish_edit() {
  local component_id="$1"
  local current_branch=""

  require_component "$component_id"
  ensure_vendor_repo "$component_id"
  load_edit_state "$component_id"
  require_clean_vendor_repo

  if ! git -C "$vendor_abs" rev-parse --verify --quiet "$EDIT_BRANCH_NAME" >/dev/null 2>&1; then
    echo "Tracked edit branch no longer exists for $component_id: $EDIT_BRANCH_NAME" >&2
    exit 1
  fi

  current_branch="$(git -C "$vendor_abs" branch --show-current)"
  if [[ "$current_branch" != "$EDIT_BRANCH_NAME" ]]; then
    git -C "$vendor_abs" switch "$EDIT_BRANCH_NAME" >/dev/null
  fi

  refresh_patches "$component_id" "$EDIT_BASE_REF"
  git -C "$vendor_abs" switch --detach "$EDIT_BASE_REF" >/dev/null
  git -C "$vendor_abs" branch -D "$EDIT_BRANCH_NAME" >/dev/null
  clear_edit_state
  bash "$script_dir/prepare-components.sh" "$component_id"

  echo "Finished edit session for $component_id"
  echo "Vendor repository reset to $EDIT_BASE_REF"
  echo "Patch queue refreshed at $component_patches_path"
}

abort_edit() {
  local component_id="$1"

  require_component "$component_id"
  ensure_vendor_repo "$component_id"
  load_edit_state "$component_id"
  require_clean_vendor_repo

  git -C "$vendor_abs" switch --detach "$EDIT_BASE_REF" >/dev/null
  if git -C "$vendor_abs" rev-parse --verify --quiet "$EDIT_BRANCH_NAME" >/dev/null 2>&1; then
    git -C "$vendor_abs" branch -D "$EDIT_BRANCH_NAME" >/dev/null
  fi
  clear_edit_state

  echo "Aborted edit session for $component_id"
  echo "Vendor repository reset to $EDIT_BASE_REF"
}

list_components() {
  local current_component_id=""

  load_component_manifest
  for current_component_id in "${component_ids[@]}"; do
    printf '%s\n' "$current_component_id"
  done
}

print_component_status() {
  local requested_component_id="$1"
  local current_branch=""
  local vendor_head=""
  local vendor_status="clean"

  require_component "$requested_component_id"
  ensure_vendor_repo "$requested_component_id"

  current_branch="$(git -C "$vendor_abs" branch --show-current)"
  vendor_head="$(git -C "$vendor_abs" rev-parse HEAD)"
  if [[ -n "$(git -C "$vendor_abs" status --short)" ]]; then
    vendor_status="dirty"
  fi

  echo "Component: $component_id"
  echo "Type: $component_type"
  echo "Vendor path: $component_vendor_path"
  echo "Patches path: $component_patches_path"
  echo "Install dir: $component_install_dir"
  echo "Vendor HEAD: $vendor_head"
  echo "Current branch: ${current_branch:-detached}"
  echo "Vendor status: $vendor_status"

  if [[ -f "$state_file" ]]; then
    load_edit_state "$component_id"
    echo "Edit session: active"
    echo "Base ref: $EDIT_BASE_REF"
    echo "Active edit branch: $EDIT_BRANCH_NAME"
  else
    echo "Edit session: inactive"
  fi
}

show_status() {
  local requested_component_id="${1:-}"
  local current_component_id=""
  local current_branch=""
  local session_state="inactive"

  if [[ -n "$requested_component_id" ]]; then
    print_component_status "$requested_component_id"
    return 0
  fi

  load_component_manifest
  printf 'COMPONENT\tEDIT_SESSION\tBRANCH\tVENDOR_PATH\n'
  for current_component_id in "${component_ids[@]}"; do
    require_component "$current_component_id"
    ensure_vendor_repo "$current_component_id"
    session_state="inactive"
    if [[ -f "$state_file" ]]; then
      load_edit_state "$current_component_id"
      session_state="active:$EDIT_BRANCH_NAME"
    fi

    current_branch="$(git -C "$vendor_abs" branch --show-current)"
    printf '%s\t%s\t%s\t%s\n' \
      "$component_id" \
      "$session_state" \
      "${current_branch:-detached}" \
      "$component_vendor_path"
  done
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  start)
    if [[ $# -lt 1 || $# -gt 2 ]]; then
      usage
      exit 1
    fi
    start_edit "$1" "${2:-}"
    ;;
  finish)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    finish_edit "$1"
    ;;
  abort)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    abort_edit "$1"
    ;;
  refresh)
    if [[ $# -lt 1 || $# -gt 2 ]]; then
      usage
      exit 1
    fi
    refresh_patches "$1" "${2:-}"
    ;;
  status)
    if [[ $# -gt 1 ]]; then
      usage
      exit 1
    fi
    show_status "${1:-}"
    ;;
  list)
    if [[ $# -ne 0 ]]; then
      usage
      exit 1
    fi
    list_components
    ;;
  *)
    usage
    exit 1
    ;;
esac