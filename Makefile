.PHONY: all generate build bench bench-complexity bench-scaling bench-validate bench-format \
       memory clean clean-all help check-deps baseline ci-check ci-quick

# Configuration
# Local dev: caffeine_lang is a sibling directory
# CI: caffeine_lang is checked out as a subdirectory
CAFFEINE_ROOT := $(or $(realpath ../caffeine_lang),$(realpath ./caffeine_lang))
CAFFEINE_CLI  := $(CAFFEINE_ROOT)/caffeine_cli
CORPUS        := $(CURDIR)/corpus
RESULTS       := $(CURDIR)/results
BASELINE      := $(CURDIR)/baseline
BENCH         := $(CURDIR)/bin/caffeine-prod
WARMUP        := 5
RUNS          := 15
THRESHOLD     := 20

# Shorthand: compile a corpus scale quietly
# Usage: $(call compile,corpus_subdir)
define compile
$(BENCH) compile $(CORPUS)/$(1)/blueprints.caffeine $(CORPUS)/$(1)/expectations/ --quiet
endef

# --- Targets ---

help: ## Show this help
	@echo "Caffeine Benchmark Suite"
	@echo "========================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-deps: ## Check that required tools are installed
	@command -v hyperfine >/dev/null 2>&1 || { echo "ERROR: hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@command -v gleam >/dev/null 2>&1 || { echo "ERROR: gleam not found"; exit 1; }
	@command -v deno >/dev/null 2>&1 || { echo "ERROR: deno not found. Install: https://docs.deno.com/runtime/getting_started/installation/"; exit 1; }
	@test -d $(CORPUS) || { echo "ERROR: corpus/ not found. Run 'make generate' first."; exit 1; }

build: ## Build the caffeine compiler (production-equivalent Deno binary)
	@cd $(CAFFEINE_CLI) && gleam build --target javascript
	@cd $(CAFFEINE_ROOT) && deno compile --no-check \
		--allow-read --allow-write --allow-env --allow-run \
		--include lsp_server.ts \
		--output $(BENCH) main.mjs
	@echo "Built $(BENCH)"

generate: ## (Dev) Regenerate corpus files, then commit them
	python3 $(CURDIR)/generate_corpus.py
	@echo "Remember to commit corpus/"

$(RESULTS):
	@mkdir -p $(RESULTS)

all: check-deps build bench ## Build and run all benchmarks

# --- Benchmarks ---

bench: bench-complexity bench-scaling bench-validate ## Run all benchmarks

bench-complexity: check-deps build $(RESULTS) ## Benchmark by blueprint complexity
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/complexity.json \
		--export-markdown $(RESULTS)/complexity.md \
		-n "small (2 bp, 4 exp)"      '$(call compile,small)' \
		-n "medium (5 bp, 24 exp)"    '$(call compile,medium)' \
		-n "large (20 bp, 120 exp)"   '$(call compile,large)' \
		-n "huge (50 bp, 600 exp)"    '$(call compile,huge)' \
		-n "insane (50 bp, ~6K exp)"  '$(call compile,insane)' \
		-n "absurd (50 bp, ~25K exp)" '$(call compile,absurd)'
	@cat $(RESULTS)/complexity.md

bench-scaling: check-deps build $(RESULTS) ## Benchmark by expectation count
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/scaling.json \
		--export-markdown $(RESULTS)/scaling.md \
		-n "10 expectations"   '$(call compile,exp_scale_10)' \
		-n "50 expectations"   '$(call compile,exp_scale_50)' \
		-n "100 expectations"  '$(call compile,exp_scale_100)' \
		-n "500 expectations"  '$(call compile,exp_scale_500)' \
		-n "1000 expectations" '$(call compile,exp_scale_1000)' \
		-n "2500 expectations" '$(call compile,exp_scale_2500)' \
		-n "5000 expectations" '$(call compile,exp_scale_5000)'
	@cat $(RESULTS)/scaling.md

bench-validate: check-deps build $(RESULTS) ## Compare compile vs validate (large corpus)
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/validate.json \
		--export-markdown $(RESULTS)/validate.md \
		-n "compile (large)"  '$(call compile,large)' \
		-n "validate (large)" '$(BENCH) validate $(CORPUS)/large/blueprints.caffeine $(CORPUS)/large/expectations/ --quiet'
	@cat $(RESULTS)/validate.md

bench-format: check-deps build $(RESULTS) ## Benchmark the formatter
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/format.json \
		--export-markdown $(RESULTS)/format.md \
		-n "format small" '$(BENCH) format $(CORPUS)/small/ --check --quiet' \
		-n "format large" '$(BENCH) format $(CORPUS)/large/ --check --quiet' \
		-n "format huge"  '$(BENCH) format $(CORPUS)/huge/ --check --quiet'
	@cat $(RESULTS)/format.md

memory: check-deps build ## Measure peak memory (requires gtime)
	@command -v gtime >/dev/null 2>&1 || { echo "ERROR: gtime not found. Install: brew install gnu-time"; exit 1; }
	@echo "=== Peak Memory Usage ==="
	@for scale in small medium large huge insane absurd; do \
		printf "%-10s" "$$scale:"; \
		gtime -v $(BENCH) compile $(CORPUS)/$$scale/blueprints.caffeine $(CORPUS)/$$scale/expectations/ --quiet \
			2>&1 | grep "Maximum resident" || echo "failed"; \
	done
	@echo ""
	@for count in 10 50 100 500 1000 2500 5000; do \
		printf "%-10s" "exp_$$count:"; \
		gtime -v $(BENCH) compile $(CORPUS)/exp_scale_$$count/blueprints.caffeine $(CORPUS)/exp_scale_$$count/expectations/ --quiet \
			2>&1 | grep "Maximum resident" || echo "failed"; \
	done

# --- CI & Regression Detection ---

baseline: bench ## Save current results as baseline (commit this!)
	rm -rf $(BASELINE) && mkdir -p $(BASELINE)
	cp $(RESULTS)/*.json $(BASELINE)/
	@echo "Baseline saved. Commit baseline/ to track regressions."

ci-check: check-deps build $(RESULTS) ## CI: benchmark and compare against baseline
	@test -d $(BASELINE) || { echo "ERROR: No baseline. Run 'make baseline' first."; exit 1; }
	$(MAKE) bench
	@echo ""
	@echo "=== Comparing against baseline (threshold: $(THRESHOLD)%) ==="
	@python3 $(CURDIR)/compare.py $(BASELINE)/complexity.json $(RESULTS)/complexity.json --threshold $(THRESHOLD)
	@python3 $(CURDIR)/compare.py $(BASELINE)/scaling.json $(RESULTS)/scaling.json --threshold $(THRESHOLD)

ci-quick: check-deps build $(RESULTS) ## CI: fast check (complexity only, fewer runs)
	@test -d $(BASELINE) || { echo "ERROR: No baseline. Run 'make baseline' first."; exit 1; }
	$(MAKE) bench-complexity WARMUP=3 RUNS=8
	@python3 $(CURDIR)/compare.py $(BASELINE)/complexity.json $(RESULTS)/complexity.json --threshold $(THRESHOLD)

# --- Cleanup ---

clean: ## Remove results (keeps corpus and baseline)
	rm -rf $(RESULTS)

clean-all: clean ## Remove results AND baseline
	rm -rf $(BASELINE)
