#!/usr/bin/env bash
# Build the local caffeine binary and bench it against the 5.5.0 baseline.
# Intended as a perf feedback loop while iterating on caffeine source.
#
# Usage:
#   ./bench-local.sh                   # quick (small/medium/large, warmup 2, runs 5)
#   ./bench-local.sh --scope medium    # adds huge, warmup 5, runs 15
#   ./bench-local.sh --no-build        # skip rebuild (use existing dist/caffeine-local)
#   ./bench-local.sh --baseline X.Y.Z  # compare against results-X.Y.Z/<scope>.json instead of 5.5.0

set -euo pipefail
cd "$(dirname "$0")"

CAFFEINE_REPO="${CAFFEINE_REPO:-/home/rob/Desktop/BrickellResearch/caffeine}"
SCOPE="quick"
BUILD=1
BASELINE="5.5.0"

while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$SCOPE" in
  quick)  WARMUP=2; RUNS=5;  BENCHES="small medium large" ;;
  medium) WARMUP=5; RUNS=15; BENCHES="small medium large huge" ;;
  *) echo "unknown --scope: $SCOPE (use quick|medium)" >&2; exit 2 ;;
esac

BIN="$CAFFEINE_REPO/dist/caffeine-local"

if [ "$BUILD" = 1 ]; then
  echo "==> building local caffeine ($CAFFEINE_REPO)"
  ( cd "$CAFFEINE_REPO" \
    && bun install >/dev/null \
    && ( cd caffeine_lsp && gleam build --target javascript >/dev/null ) \
    && ( cd caffeine_cli && gleam build --target javascript >/dev/null ) \
    && mkdir -p dist \
    && bun build --compile --minify --bytecode \
       --target=bun-linux-x64 \
       --outfile "$BIN" main.mjs )
fi

"$BIN" --version

CORPUS="$PWD/corpus"
OUT="$PWD/results-local"
rm -rf "$OUT" && mkdir -p "$OUT"

cmds=()
for b in $BENCHES; do
  case "$b" in
    small)  cmds+=(-n "small (2 m, 4 exp)"    "$BIN compile $CORPUS/small/measurements/  $CORPUS/small/expectations/  --quiet") ;;
    medium) cmds+=(-n "medium (5 m, 24 exp)"  "$BIN compile $CORPUS/medium/measurements/ $CORPUS/medium/expectations/ --quiet") ;;
    large)  cmds+=(-n "large (20 m, 120 exp)" "$BIN compile $CORPUS/large/measurements/  $CORPUS/large/expectations/  --quiet") ;;
    huge)   cmds+=(-n "huge (50 m, 600 exp)"  "$BIN compile $CORPUS/huge/measurements/   $CORPUS/huge/expectations/   --quiet") ;;
  esac
done

echo "==> benching local ($SCOPE: warmup $WARMUP, runs $RUNS)"
hyperfine --warmup "$WARMUP" --runs "$RUNS" \
  --export-json "$OUT/$SCOPE.json" \
  --export-markdown "$OUT/$SCOPE.md" \
  "${cmds[@]}"

BASELINE_FILE="results-$BASELINE/$SCOPE.json"
if [ ! -f "$BASELINE_FILE" ]; then
  echo "warning: baseline $BASELINE_FILE not found — skipping comparison" >&2
  exit 0
fi

echo
echo "==> comparison: local vs $BASELINE"
python3 compare.py "$BASELINE_FILE" "$OUT/$SCOPE.json" --threshold 10 || true
