# perf

Benchmark suite for the [Caffeine](https://github.com/Brickell-Research/caffeine_lang) compiler. Runs the `caffeine` binary on your `PATH` against a pre-generated corpus of `.caffeine` files at various scales and reports timing via [hyperfine](https://github.com/sharkdp/hyperfine).

No compiler source checkout, no Gleam toolchain, no build step. Just install and run.

## Prerequisites

```
brew install hyperfine
```

You'll also need `caffeine` on your PATH. Use [cvm](https://github.com/Brickell-Research/cvm) (Caffeine Version Manager) to install and switch between versions:

```bash
cvm install latest
cvm use 4.6.2
```

## Quick Start

```bash
# Benchmark whatever caffeine version is active
make bench

# Switch versions and compare
cvm use 4.5.1
make bench
# save results, switch, re-run, then compare
```

## What It Benchmarks

Three suites, all using hyperfine for statistical rigor (warmup runs, multiple iterations, outlier detection):

**Complexity** (`make bench-complexity`) — Scales blueprint and expectation count together:

| Corpus | Blueprints | Expectations |
|--------|-----------|--------------|
| small | 2 | 4 |
| medium | 5 | 24 |
| large | 20 | 120 |
| huge | 50 | 600 |
| insane | 50 | ~6,000 |
| absurd | 50 | ~25,000 |

**Scaling** (`make bench-scaling`) — Holds blueprints constant, isolates expectation count: 10, 50, 100, 500, 1000, 2500, 5000.

**Validate** (`make bench-validate`) — Compares `compile` vs `validate` on the large corpus to see how much time is spent in codegen vs. the frontend.

There's also `make bench-format` and `make memory` (requires `brew install gnu-time`) if you want to go deeper.

## Regression Detection

The idea: save benchmark results as a baseline, then compare future runs against it. If anything regresses beyond a threshold (default 20%), `compare.py` flags it.

```bash
# Run benchmarks and save as baseline
make baseline

# Later: run benchmarks and compare
make ci-check
```

On CI this happens automatically. If no baseline exists yet, the regression check is skipped and the results are uploaded as an artifact you can download and commit as `baseline/`.

## Regenerating the Corpus

The corpus is checked into the repo so benchmarks are reproducible without any Caffeine toolchain. If you need to regenerate:

```bash
make generate   # requires python3
```

## All Targets

```
make help
```
