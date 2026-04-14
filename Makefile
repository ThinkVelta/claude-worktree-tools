.PHONY: lint lint-md lint-sh test ci clean

# ---------------------------------------------------------------------------
# Linting
# ---------------------------------------------------------------------------

lint: lint-md lint-sh  ## Run all linters

lint-md:  ## Lint markdown files with markdownlint-cli2
	npx --yes markdownlint-cli2 "**/*.md" "#node_modules" "#.claude"

lint-sh:  ## Check shell scripts with shellcheck and bash -n
	bash -n templates/wt-setup.sh
	@command -v shellcheck >/dev/null 2>&1 && shellcheck templates/wt-setup.sh || echo "shellcheck not installed, skipping"

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------

test:  ## Run the smoke test suite
	bash test.sh tmp/test-make

# ---------------------------------------------------------------------------
# CI (lint + test)
# ---------------------------------------------------------------------------

ci: lint test  ## Run lint and tests (used in CI)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean:  ## Remove test artifacts
	@echo "Remove tmp/ manually if needed"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
