.PHONY: all generate download bench bench-complexity bench-scaling bench-validate bench-format \
       memory clean clean-all help check-deps baseline ci-check ci-quick

# Configuration
REPO          := Brickell-Research/caffeine_lang
VERSION       ?= latest
CORPUS        := $(CURDIR)/corpus
RESULTS       := $(CURDIR)/results
BASELINE      := $(CURDIR)/baseline
WARMUP        := 5
RUNS          := 15
THRESHOLD     := 20

# Binary resolution: VERSION=local uses whatever `caffeine` is on PATH,
# otherwise downloads from GitHub Releases.
ifeq ($(VERSION),local)
  BENCH := $(shell command -v caffeine 2>/dev/null)
  ifeq ($(BENCH),)
    $(error caffeine not found on PATH. Install it or use VERSION=latest)
  endif
else
  BENCH := $(CURDIR)/bin/caffeine
endif

# Auto-detect platform and architecture
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  PLATFORM := macos
else ifeq ($(UNAME_S),Linux)
  PLATFORM := linux
else
  $(error Unsupported OS: $(UNAME_S))
endif

ifeq ($(UNAME_M),arm64)
  ARCH := arm64
else ifeq ($(UNAME_M),aarch64)
  ARCH := arm64
else ifeq ($(UNAME_M),x86_64)
  ARCH := x64
else
  $(error Unsupported architecture: $(UNAME_M))
endif

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
	@echo "Usage: make bench [VERSION=latest|x.y.z|local]"
	@echo "  VERSION=latest (default) downloads the latest release."
	@echo "  VERSION=x.y.z downloads that specific version."
	@echo "  VERSION=local uses the caffeine binary already on your PATH."
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-deps: ## Check that required tools are installed
	@command -v hyperfine >/dev/null 2>&1 || { echo "ERROR: hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@command -v gh >/dev/null 2>&1 || { echo "ERROR: gh (GitHub CLI) not found. Install: brew install gh"; exit 1; }
	@test -d $(CORPUS) || { echo "ERROR: corpus/ not found. Run 'make generate' first."; exit 1; }

download: check-deps ## Download caffeine binary from GitHub Releases
ifeq ($(VERSION),local)
	@echo "Using local binary: $(BENCH)"
	@$(BENCH) --help | head -1
else
	@mkdir -p $(CURDIR)/bin
	@if [ "$(VERSION)" = "latest" ]; then \
		TAG=$$(gh release view --repo $(REPO) --json tagName -q .tagName); \
	else \
		TAG="v$(VERSION)"; \
	fi; \
	VER=$${TAG#v}; \
	ASSET="caffeine-$${VER}-$(PLATFORM)-$(ARCH).tar.gz"; \
	echo "Downloading $$ASSET from $(REPO) ($$TAG)..."; \
	gh release download "$$TAG" --repo $(REPO) --pattern "$$ASSET" --dir $(CURDIR)/bin --clobber; \
	tar -xzf $(CURDIR)/bin/$$ASSET -C $(CURDIR)/bin; \
	mv $(CURDIR)/bin/caffeine-$${VER}-$(PLATFORM)-$(ARCH) $(BENCH); \
	chmod +x $(BENCH); \
	rm -f $(CURDIR)/bin/$$ASSET; \
	echo "Ready: $(BENCH) ($$TAG)"
endif

generate: ## (Dev) Regenerate corpus files, then commit them
	python3 $(CURDIR)/generate_corpus.py
	@echo "Remember to commit corpus/"

$(RESULTS):
	@mkdir -p $(RESULTS)

all: download bench ## Download and run all benchmarks

# --- Benchmarks ---

bench: bench-complexity bench-scaling bench-validate ## Run all benchmarks

bench-complexity: check-deps download $(RESULTS) ## Benchmark by blueprint complexity
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

bench-scaling: check-deps download $(RESULTS) ## Benchmark by expectation count
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

bench-validate: check-deps download $(RESULTS) ## Compare compile vs validate (large corpus)
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/validate.json \
		--export-markdown $(RESULTS)/validate.md \
		-n "compile (large)"  '$(call compile,large)' \
		-n "validate (large)" '$(BENCH) validate $(CORPUS)/large/blueprints.caffeine $(CORPUS)/large/expectations/ --quiet'
	@cat $(RESULTS)/validate.md

bench-format: check-deps download $(RESULTS) ## Benchmark the formatter
	hyperfine --warmup $(WARMUP) --runs $(RUNS) \
		--export-json $(RESULTS)/format.json \
		--export-markdown $(RESULTS)/format.md \
		-n "format small" '$(BENCH) format $(CORPUS)/small/ --check --quiet' \
		-n "format large" '$(BENCH) format $(CORPUS)/large/ --check --quiet' \
		-n "format huge"  '$(BENCH) format $(CORPUS)/huge/ --check --quiet'
	@cat $(RESULTS)/format.md

memory: check-deps download ## Measure peak memory (requires gtime)
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

ci-check: download $(RESULTS) ## CI: benchmark and compare against baseline
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

ci-quick: download $(RESULTS) ## CI: fast check (complexity only, fewer runs)
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

clean-all: clean ## Remove results, baseline, AND downloaded binary
	rm -rf $(BASELINE) $(CURDIR)/bin
