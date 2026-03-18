.PHONY: all generate bench bench-quick bench-complexity bench-scaling bench-validate bench-format \
       memory clean clean-all help check-deps baseline ci-check ci-quick

# Configuration
BENCH         := $(shell command -v caffeine 2>/dev/null)
CORPUS        := $(CURDIR)/corpus
RESULTS       := $(CURDIR)/results
BASELINE      := $(CURDIR)/baseline
WARMUP        := 5
RUNS          := 15
THRESHOLD     := 20

# Shorthand: compile a corpus scale quietly
define compile
$(BENCH) compile $(CORPUS)/$(1)/measurements/ $(CORPUS)/$(1)/expectations/ --quiet
endef

# --- Targets ---

help: ## Show this help
	@echo "Caffeine Benchmark Suite"
	@echo "========================"
	@echo ""
	@echo "Usage: make bench"
	@echo "  Uses the caffeine binary on your PATH."
	@echo "  Install caffeine via: cvm install latest"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-deps: ## Check that required tools are installed
	@command -v caffeine >/dev/null 2>&1 || { echo "ERROR: caffeine not found. Install: cvm install latest"; exit 1; }
	@command -v hyperfine >/dev/null 2>&1 || { echo "ERROR: hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@test -d $(CORPUS) || { echo "ERROR: corpus/ not found. Run 'make generate' first."; exit 1; }

generate: ## (Dev) Regenerate corpus files, then commit them
	python3 $(CURDIR)/generate_corpus.py
	@echo "Formatting generated corpus..."
	@for dir in $(CORPUS)/*/; do \
		$(BENCH) format "$$dir" --quiet 2>/dev/null || true; \
	done
	@echo "Remember to commit corpus/"

$(RESULTS):
	@mkdir -p $(RESULTS)

all: bench ## Run all benchmarks

# --- Benchmarks ---

bench: bench-complexity bench-scaling bench-validate ## Run all benchmarks

bench-quick: check-deps $(RESULTS) ## Quick benchmark (3 scales, fewer runs)
	hyperfine --warmup 2 --runs 5 \
		--export-json $(RESULTS)/quick.json \
		--export-markdown $(RESULTS)/quick.md \
		-n "small (2 m, 4 exp)"    '$(call compile,small)' \
		-n "medium (5 m, 24 exp)"  '$(call compile,medium)' \
		-n "large (20 m, 120 exp)" '$(call compile,large)'
	@cat $(RESULTS)/quick.md

bench-complexity: check-deps $(RESULTS) ## Benchmark by measurement complexity
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/complexity.json \
		--export-markdown $(RESULTS)/complexity.md \
		-n "small (2 m, 4 exp)"      '$(call compile,small)' \
		-n "medium (5 m, 24 exp)"    '$(call compile,medium)' \
		-n "large (20 m, 120 exp)"   '$(call compile,large)' \
		-n "huge (50 m, 600 exp)"    '$(call compile,huge)' \
		-n "insane (50 m, ~6K exp)"  '$(call compile,insane)' \
		-n "absurd (50 m, ~25K exp)" '$(call compile,absurd)'
	@cat $(RESULTS)/complexity.md

bench-scaling: check-deps $(RESULTS) ## Benchmark by expectation count
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

bench-validate: check-deps $(RESULTS) ## Compare compile vs validate (large corpus)
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/validate.json \
		--export-markdown $(RESULTS)/validate.md \
		-n "compile (large)"  '$(call compile,large)' \
		-n "validate (large)" '$(BENCH) validate $(CORPUS)/large/measurements/ $(CORPUS)/large/expectations/ --quiet'
	@cat $(RESULTS)/validate.md

bench-format: check-deps $(RESULTS) ## Benchmark the formatter
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/format.json \
		--export-markdown $(RESULTS)/format.md \
		-n "format small" '$(BENCH) format $(CORPUS)/small/ --check --quiet' \
		-n "format large" '$(BENCH) format $(CORPUS)/large/ --check --quiet' \
		-n "format huge"  '$(BENCH) format $(CORPUS)/huge/ --check --quiet'
	@cat $(RESULTS)/format.md

memory: check-deps ## Measure peak memory (requires gtime)
	@command -v gtime >/dev/null 2>&1 || { echo "ERROR: gtime not found. Install: brew install gnu-time"; exit 1; }
	@echo "=== Peak Memory Usage ==="
	@for scale in small medium large huge insane absurd; do \
		printf "%-10s" "$$scale:"; \
		gtime -v $(BENCH) compile $(CORPUS)/$$scale/measurements/ $(CORPUS)/$$scale/expectations/ --quiet \
			2>&1 | grep "Maximum resident" || echo "failed"; \
	done
	@echo ""
	@for count in 10 50 100 500 1000 2500 5000; do \
		printf "%-10s" "exp_$$count:"; \
		gtime -v $(BENCH) compile $(CORPUS)/exp_scale_$$count/measurements/ $(CORPUS)/exp_scale_$$count/expectations/ --quiet \
			2>&1 | grep "Maximum resident" || echo "failed"; \
	done

# --- CI & Regression Detection ---

baseline: bench ## Save current results as baseline (commit this!)
	rm -rf $(BASELINE) && mkdir -p $(BASELINE)
	cp $(RESULTS)/*.json $(BASELINE)/
	@echo "Baseline saved. Commit baseline/ to track regressions."

ci-check: $(RESULTS) ## CI: benchmark and compare against baseline
	$(MAKE) bench
	@echo ""
	@echo "=== Comparing against baseline (threshold: $(THRESHOLD)%) ==="
	@for f in complexity.json scaling.json; do \
		if [ ! -f "$(BASELINE)/$$f" ]; then \
			echo "⚠ baseline/$$f not found — skipping"; \
			continue; \
		fi; \
		python3 $(CURDIR)/compare.py $(BASELINE)/$$f $(RESULTS)/$$f --threshold $(THRESHOLD); \
	done

ci-quick: $(RESULTS) ## CI: fast check (complexity only, fewer runs)
	$(MAKE) bench-complexity WARMUP=3 RUNS=8
	@for f in complexity.json; do \
		if [ ! -f "$(BASELINE)/$$f" ]; then \
			echo "⚠ baseline/$$f not found — skipping"; \
			continue; \
		fi; \
		python3 $(CURDIR)/compare.py $(BASELINE)/$$f $(RESULTS)/$$f --threshold $(THRESHOLD); \
	done

# --- Cleanup ---

clean: ## Remove results (keeps corpus and baseline)
	rm -rf $(RESULTS)

clean-all: clean ## Remove results and baseline
	rm -rf $(BASELINE)
