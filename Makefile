.PHONY: help prepare lint test ci clean

# pre-commit runs through `uvx`, not through a project venv. This repo has no
# Python source of its own — uv is purely the delivery mechanism for a
# version-pinned, ephemeral pre-commit, and nothing here touches package.json.
# uv caches the environment after the first invocation, and every linter behind
# pre-commit is pinned in .pre-commit-config.yaml.
PRE_COMMIT := uvx pre-commit@4.4.0

# The smoke tests scribble real git repos into a scratch dir (gitignored via
# `tmp/`). Naming it once here keeps `test` and `clean` honest about the same
# path; override with `make test TEST_DIR=...`.
TEST_DIR ?= tmp/test-make

# `help` is the first non-`.PHONY` target, so bare `make` prints the table.
# The awk one-liner scans every target line of the form `<name>: ... ## <desc>`
# and renders it. Annotate every new target with `## <one-line description>` to
# make it self-documenting.
help: ## Show available commands
	@echo ""
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Run 'make prepare' once per clone, and 'make lint' before committing."
	@echo ""

prepare: ## Install the git hooks (pre-commit + commit-msg)
	$(PRE_COMMIT) install --install-hooks

# One entry point for every linter: markdown, shell (shellcheck + shfmt),
# YAML/JSON hygiene and workflow correctness all live in
# .pre-commit-config.yaml, so this is byte-identical to what the git hook and
# CI run — there is no second, drifting copy of the lint command line.
# Note: the markdownlint / shfmt / whitespace hooks REWRITE files and report a
# failure when they do. Re-run after a fixing pass.
lint: ## Run every pre-commit hook over the whole tree
	$(PRE_COMMIT) run --all-files

test: ## Run the smoke test suite (override the scratch dir with TEST_DIR=...)
	bash test.sh "$(TEST_DIR)"

ci: lint test ## Run lint and tests (the full local equivalent of CI)

clean: ## Report the scratch dir to remove (never deletes anything itself)
	@echo "Remove '$(TEST_DIR)' manually if you want a clean slate."
