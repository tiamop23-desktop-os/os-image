#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="$repo_root/manifests/components.yml"
edit_state_dir="$repo_root/.work/edit-sessions"
generated_dir="$repo_root/bluebuild/files/generated"
render_work_dir="$repo_root/.work/render"

component_manifest_loaded=0

component_id=""
component_type=""
component_vendor_path=""
component_patches_path=""
component_install_dir=""
component_build_command=""
component_build_output=""
component_post_install_command=""
vendor_abs=""
patches_abs=""
state_file=""
COMPONENT_ID=""
EDIT_BASE_REF=""
EDIT_BRANCH_NAME=""

declare -ag component_ids=()
declare -Ag component_type_by_id=()
declare -Ag component_vendor_path_by_id=()
declare -Ag component_patches_path_by_id=()
declare -Ag component_install_dir_by_id=()
declare -Ag component_build_command_by_id=()
declare -Ag component_build_output_by_id=()
declare -Ag component_post_install_command_by_id=()
declare -Ag component_id_by_vendor_path=()

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

fail() {
  echo "$*" >&2
  return 1
}

derive_component_vendor_path() {
  local component_id="$1"
  local component_type="$2"

  case "$component_type" in
    gnome-extension)
      printf 'vendor/extensions/%s' "$component_id"
      ;;
    *)
      fail "Unsupported component type '$component_type' for $component_id"
      return 1
      ;;
  esac
}

derive_component_patches_path() {
  local component_id="$1"
  local component_type="$2"

  case "$component_type" in
    gnome-extension)
      printf 'patches/extensions/%s' "$component_id"
      ;;
    *)
      fail "Unsupported component type '$component_type' for $component_id"
      return 1
      ;;
  esac
}

register_component() {
  local component_id="$1"
  local component_type="$2"
  local component_vendor_path="$3"
  local component_patches_path="$4"
  local component_install_dir="$5"
  local component_build_command="$6"
  local component_build_output="$7"
  local component_post_install_command="$8"

  [[ -n "$component_id" ]] || return 0

  if [[ -z "$component_type" || -z "$component_install_dir" ]]; then
    fail "Component definition is incomplete in $manifest_path: $component_id"
    return 1
  fi

  if [[ -z "$component_vendor_path" ]]; then
    component_vendor_path="$(derive_component_vendor_path "$component_id" "$component_type")" || return 1
  fi

  if [[ -z "$component_patches_path" ]]; then
    component_patches_path="$(derive_component_patches_path "$component_id" "$component_type")" || return 1
  fi

  component_ids+=("$component_id")
  component_type_by_id["$component_id"]="$component_type"
  component_vendor_path_by_id["$component_id"]="$component_vendor_path"
  component_patches_path_by_id["$component_id"]="$component_patches_path"
  component_install_dir_by_id["$component_id"]="$component_install_dir"
  component_build_command_by_id["$component_id"]="$component_build_command"
  component_build_output_by_id["$component_id"]="$component_build_output"
  component_post_install_command_by_id["$component_id"]="$component_post_install_command"
  component_id_by_vendor_path["$component_vendor_path"]="$component_id"
}

load_component_manifest() {
  local line=""
  local current_id=""
  local current_type=""
  local current_vendor_path=""
  local current_patches_path=""
  local current_install_dir=""
  local current_build_command=""
  local current_build_output=""
  local current_post_install_command=""

  if [[ "$component_manifest_loaded" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -f "$manifest_path" ]]; then
    fail "Component manifest not found: $manifest_path"
    return 1
  fi

  component_ids=()
  component_type_by_id=()
  component_vendor_path_by_id=()
  component_patches_path_by_id=()
  component_install_dir_by_id=()
  component_build_command_by_id=()
  component_build_output_by_id=()
  component_post_install_command_by_id=()
  component_id_by_vendor_path=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]id:[[:space:]]*(.+)$ ]]; then
      register_component "$current_id" "$current_type" "$current_vendor_path" "$current_patches_path" "$current_install_dir" "$current_build_command" "$current_build_output" "$current_post_install_command" || return 1
      current_id="$(trim "${BASH_REMATCH[1]}")"
      current_type=""
      current_vendor_path=""
      current_patches_path=""
      current_install_dir=""
      current_build_command=""
      current_build_output=""
      current_post_install_command=""
    elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
      current_type="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^[[:space:]]*vendor_path:[[:space:]]*(.+)$ ]]; then
      current_vendor_path="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^[[:space:]]*patches_path:[[:space:]]*(.+)$ ]]; then
      current_patches_path="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^[[:space:]]*install_dir:[[:space:]]*(.+)$ ]]; then
      current_install_dir="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^[[:space:]]*build_command:[[:space:]]*(.+)$ ]]; then
      current_build_command="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^[[:space:]]*build_output:[[:space:]]*(.+)$ ]]; then
      current_build_output="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^[[:space:]]*post_install_command:[[:space:]]*(.+)$ ]]; then
      current_post_install_command="$(trim "${BASH_REMATCH[1]}")"
    fi
  done < "$manifest_path"

  register_component "$current_id" "$current_type" "$current_vendor_path" "$current_patches_path" "$current_install_dir" "$current_build_command" "$current_build_output" "$current_post_install_command" || return 1
  component_manifest_loaded=1
}

set_component_context() {
  local requested_component_id="$1"

  if [[ -z "${component_vendor_path_by_id[$requested_component_id]:-}" ]]; then
    return 1
  fi

  component_id="$requested_component_id"
  component_type="${component_type_by_id[$requested_component_id]}"
  component_vendor_path="${component_vendor_path_by_id[$requested_component_id]}"
  component_patches_path="${component_patches_path_by_id[$requested_component_id]}"
  component_install_dir="${component_install_dir_by_id[$requested_component_id]}"
  component_build_command="${component_build_command_by_id[$requested_component_id]:-}"
  component_build_output="${component_build_output_by_id[$requested_component_id]:-}"
  component_post_install_command="${component_post_install_command_by_id[$requested_component_id]:-}"
  vendor_abs="$repo_root/$component_vendor_path"
  patches_abs="$repo_root/$component_patches_path"
  state_file="$edit_state_dir/$requested_component_id.env"
}

resolve_component() {
  local requested_component_id="$1"

  load_component_manifest || return 1
  set_component_context "$requested_component_id"
}

require_component() {
  local requested_component_id="$1"

  if ! resolve_component "$requested_component_id"; then
    fail "Component not found in manifest: $requested_component_id"
    return 1
  fi
}

resolve_component_by_vendor_path() {
  local search_vendor_path="$1"
  local requested_component_id=""

  load_component_manifest || return 1
  requested_component_id="${component_id_by_vendor_path[$search_vendor_path]:-}"
  if [[ -z "$requested_component_id" ]]; then
    return 1
  fi

  set_component_context "$requested_component_id"
}

for_each_component() {
  local callback="$1"
  local current_component_id=""

  load_component_manifest || return 1

  for current_component_id in "${component_ids[@]}"; do
    set_component_context "$current_component_id" || return 1
    "$callback" "$current_component_id" || return 1
  done
}

ensure_vendor_repo() {
  local component_id="$1"

  if [[ ! -d "$vendor_abs" ]]; then
    fail "Vendor repository not found for $component_id: $component_vendor_path"
    return 1
  fi

  if ! git -C "$vendor_abs" rev-parse --git-dir >/dev/null 2>&1; then
    fail "Vendor path is not a git repository: $component_vendor_path"
    return 1
  fi
}

require_clean_vendor_repo() {
  if [[ -n "$(git -C "$vendor_abs" status --short)" ]]; then
    fail "Vendor repository has uncommitted changes: $component_vendor_path"
    return 1
  fi
}

write_edit_state() {
  local component_id="$1"
  local base_ref="$2"
  local branch_name="$3"
  local tmp_file=""

  mkdir -p "$edit_state_dir"
  tmp_file="$(mktemp "$edit_state_dir/${component_id}.tmp.XXXXXX")"
  printf 'COMPONENT_ID=%q\nEDIT_BASE_REF=%q\nEDIT_BRANCH_NAME=%q\n' \
    "$component_id" "$base_ref" "$branch_name" > "$tmp_file"
  mv "$tmp_file" "$state_file"
}

load_edit_state() {
  local expected_component_id="$1"

  if [[ ! -f "$state_file" ]]; then
    fail "No active edit session found for $expected_component_id"
    return 1
  fi

  COMPONENT_ID=""
  EDIT_BASE_REF=""
  EDIT_BRANCH_NAME=""

  # shellcheck disable=SC1090
  source "$state_file"

  if [[ -z "$COMPONENT_ID" || -z "$EDIT_BASE_REF" || -z "$EDIT_BRANCH_NAME" ]]; then
    fail "Edit session state is incomplete for $expected_component_id: $state_file"
    return 1
  fi

  if [[ "$COMPONENT_ID" != "$expected_component_id" ]]; then
    fail "Edit session state does not match component $expected_component_id: $state_file"
    return 1
  fi

  if [[ -n "$vendor_abs" ]] && ! git -C "$vendor_abs" rev-parse --verify "$EDIT_BASE_REF^{commit}" >/dev/null 2>&1; then
    fail "Edit session base ref no longer exists for $expected_component_id: $EDIT_BASE_REF"
    return 1
  fi
}

clear_edit_state() {
  rm -f "$state_file"
}

patch_commit_oid_from_file() {
  local patch_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^From[[:space:]]+([0-9a-f]{7,40})[[:space:]] ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$patch_file"

  return 1
}

apply_patches_to_repo() {
  local repo_path="$1"
  local patches_dir="$2"
  local component_name="$3"
  local patch_file=""
  local patch_commit_oid=""

  if [[ ! -d "$patches_dir" ]]; then
    return 0
  fi

  while IFS= read -r -d '' patch_file; do
    patch_commit_oid="$(patch_commit_oid_from_file "$patch_file" || true)"
    if [[ -n "$patch_commit_oid" ]] && git -C "$repo_path" merge-base --is-ancestor "$patch_commit_oid" HEAD >/dev/null 2>&1; then
      continue
    fi

    if ! git -C "$repo_path" am --3way "$patch_file" >/dev/null; then
      git -C "$repo_path" am --abort >/dev/null 2>&1 || true
      fail "Failed to apply patch for $component_name: $(basename "$patch_file"). The vendor checkout may already include those commits, or the patch queue no longer matches the pinned base."
      return 1
    fi
  done < <(find "$patches_dir" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)
}

apply_existing_patches() {
  apply_patches_to_repo "$vendor_abs" "$patches_abs" "$component_id"
}

export_patch_series() {
  local repo_path="$1"
  local patches_dir="$2"
  local base_ref="$3"
  local component_name="$4"
  local commit_tip=""

  if ! git -C "$repo_path" rev-parse --verify "$base_ref^{commit}" >/dev/null 2>&1; then
    fail "Base ref not found for $component_name: $base_ref"
    return 1
  fi

  commit_tip="$(git -C "$repo_path" rev-list --max-count=1 "$base_ref"..HEAD)"
  if [[ -z "$commit_tip" ]]; then
    fail "No commits found between $base_ref and HEAD for $component_name"
    return 1
  fi

  mkdir -p "$patches_dir"
  find "$patches_dir" -maxdepth 1 -type f -name '*.patch' -delete
  git -C "$repo_path" format-patch --output-directory "$patches_dir" "$base_ref"..HEAD >/dev/null
}

ensure_generated_tree() {
  mkdir -p "$generated_dir" "$render_work_dir"
  printf '*\n!.gitignore\n' > "$generated_dir/.gitignore"
}

cleanup_component_worktree() {
  local component_work_dir="$1"

  git -C "$vendor_abs" worktree remove --force "$component_work_dir" >/dev/null 2>&1 || true
}

run_component_shell_command() {
  local command_kind="$1"
  local shell_command="$2"
  local component_work_dir="$3"
  local destination_dir="$4"

  if ! (
    export COMPONENT_WORK_DIR="$component_work_dir"
    export COMPONENT_DEST="$destination_dir"
    cd "$component_work_dir"
    bash -euo pipefail -c "$shell_command"
  ) >/dev/null; then
    fail "Failed to run $command_kind for $component_id"
    return 1
  fi
}

install_component_build_output() {
  local component_work_dir="$1"
  local destination_dir="$2"
  local output_path="$component_work_dir/$component_build_output"

  if [[ -z "$component_build_output" ]]; then
    fail "Component $component_id defines a build command but no build output"
    return 1
  fi

  if [[ -d "$output_path" ]]; then
    tar -C "$output_path" -cf - . | tar -xf - -C "$destination_dir"
    return 0
  fi

  if [[ ! -f "$output_path" ]]; then
    fail "Build output not found for $component_id: $component_build_output"
    return 1
  fi

  case "$output_path" in
    *.zip)
      unzip -oq "$output_path" -d "$destination_dir"
      ;;
    *.tar)
      tar -xf "$output_path" -C "$destination_dir"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$output_path" -C "$destination_dir"
      ;;
    *)
      fail "Unsupported build output for $component_id: $component_build_output"
      return 1
      ;;
  esac
}

install_component_source_tree() {
  local component_work_dir="$1"
  local destination_dir="$2"

  git -C "$component_work_dir" archive --format=tar HEAD | tar -xf - -C "$destination_dir"
}

render_component_to_generated() {
  local component_work_dir=""
  local destination_dir=""

  [[ -n "$component_id" ]] || return 0

  if [[ "$component_type" != "gnome-extension" ]]; then
    fail "Unsupported component type '$component_type' for $component_id"
    return 1
  fi

  ensure_vendor_repo "$component_id" || return 1
  ensure_generated_tree

  component_work_dir="$render_work_dir/$component_id"
  destination_dir="$generated_dir/$component_install_dir"

  rm -rf "$component_work_dir" "$destination_dir"
  mkdir -p "$component_work_dir" "$destination_dir"
  cleanup_component_worktree "$component_work_dir"
  git -C "$vendor_abs" worktree add --force --detach "$component_work_dir" HEAD >/dev/null

  if ! apply_patches_to_repo "$component_work_dir" "$patches_abs" "$component_id"; then
    cleanup_component_worktree "$component_work_dir"
    return 1
  fi

  if [[ -n "$component_build_command" ]]; then
    if ! run_component_shell_command "build command" "$component_build_command" "$component_work_dir" "$destination_dir"; then
      cleanup_component_worktree "$component_work_dir"
      return 1
    fi
  fi

  if [[ -n "$component_build_output" ]]; then
    if ! install_component_build_output "$component_work_dir" "$destination_dir"; then
      cleanup_component_worktree "$component_work_dir"
      return 1
    fi
  elif ! install_component_source_tree "$component_work_dir" "$destination_dir"; then
    cleanup_component_worktree "$component_work_dir"
    return 1
  fi

  if [[ -n "$component_post_install_command" ]]; then
    if ! run_component_shell_command "post-install command" "$component_post_install_command" "$component_work_dir" "$destination_dir"; then
      cleanup_component_worktree "$component_work_dir"
      return 1
    fi
  fi

  cleanup_component_worktree "$component_work_dir"
}
