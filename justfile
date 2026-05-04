set shell := ["bash", "-euo", "pipefail", "-c"]

recipe_path := "bluebuild/recipes/main.yml"
prepare_components_script := "./scripts/prepare-components.sh"
component_edit_script := "./scripts/component-edit.sh"
bluebuild_check := "command -v bluebuild >/dev/null 2>&1 || { echo \"bluebuild CLI is not installed\" >&2; exit 1; }"

default:
	@just --list

setup:
	@just install-git-hooks
	@just sync-submodules
	@just prepare

prepare component='':
	@if [[ -n "{{component}}" ]]; then \
		bash {{prepare_components_script}} "{{component}}"; \
	else \
		bash {{prepare_components_script}}; \
	fi

generate:
	@{{bluebuild_check}}
	bluebuild generate -d "{{recipe_path}}"

build:
	@{{bluebuild_check}}
	bluebuild build "{{recipe_path}}"

switch:
	@{{bluebuild_check}}
	bluebuild switch "{{recipe_path}}"

sync-submodules:
	git submodule sync --recursive
	git submodule update --init --recursive

install-git-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
	@echo "Configured git hooks path to .githooks"

update-submodules:
	git submodule update --remote --merge --recursive

component-list:
	bash {{component_edit_script}} list

component-status component='':
	@if [[ -n "{{component}}" ]]; then \
		bash {{component_edit_script}} status "{{component}}"; \
	else \
		bash {{component_edit_script}} status; \
	fi

component-edit component branch='':
	bash {{component_edit_script}} start "{{component}}" "{{branch}}"

component-finish component:
	bash {{component_edit_script}} finish "{{component}}"

component-abort component:
	bash {{component_edit_script}} abort "{{component}}"

refresh-patches component base_ref='':
	bash {{component_edit_script}} refresh "{{component}}" "{{base_ref}}"

clean-generated:
	rm -rf bluebuild/files/generated/*
	mkdir -p bluebuild/files/generated