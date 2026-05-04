#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./component-common.sh
source "$script_dir/component-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  prepare-components.sh [component-id]
EOF
}

reset_generated_tree() {
  ensure_generated_tree
  rm -rf "$render_work_dir"
  mkdir -p "$render_work_dir"
  find "$generated_dir" -mindepth 1 ! -name '.gitignore' -exec rm -rf {} +
}

render_current_component() {
  render_component_to_generated
}

render_all_components() {
  load_component_manifest
  reset_generated_tree

  if [[ "${#component_ids[@]}" -eq 0 ]]; then
    echo "Initialized an empty generated tree at $generated_dir"
    return 0
  fi

  for_each_component render_current_component
  echo "Rendered component output into $generated_dir"
}

render_requested_component() {
  local requested_component_id="$1"

  require_component "$requested_component_id"
  render_component_to_generated
  echo "Rendered $component_id into $generated_dir/$component_install_dir"
}

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

if [[ $# -eq 1 ]]; then
  render_requested_component "$1"
else
  render_all_components
fi