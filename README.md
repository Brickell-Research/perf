# perf

Benchmark suite for the [Caffeine](https://github.com/Brickell-Research/caffeine_lang) compiler. Downloads a release binary from GitHub, runs it against a pre-generated corpus of `.caffeine` files at various scales, and reports timing via [hyperfine](https://github.com/sharkdp/hyperfine).

No compiler source checkout, no Gleam toolchain, no build step. Just download and run.

## Prerequisites

```
brew install hyperfine gh
```

That's it. `gh` needs to be authenticated (`gh auth login`) so it can pull release assets.

## Quick Start

```bash
# Benchmark the latest release
make bench

# Benchmark a specific version
make bench VERSION=4.5.1

# Benchmark whatever's on your PATH (e.g. from Homebrew)
make bench VERSION=local
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
