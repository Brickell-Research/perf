#!/usr/bin/env bash
# Build the local caffeine binary and bench it head-to-head against a
# cvm-installed release binary in the SAME hyperfine invocation, so the
# comparison is apples-to-apples regardless of system state at run time.
# Intended as a perf feedback loop while iterating on caffeine source.
#
# Usage:
#   ./bench-local.sh                   # quick (small/medium/large, warmup 2, runs 5)
#   ./bench-local.sh --scope medium    # adds huge, warmup 5, runs 15
#   ./bench-local.sh --no-build        # skip rebuild (use existing dist/caffeine-local)
#   ./bench-local.sh --baseline X.Y.Z  # bench against ~/.cvm/versions/X.Y.Z/caffeine instead of 5.5.0

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

LOCAL_BIN="$CAFFEINE_REPO/dist/caffeine-local"
BASELINE_BIN="$HOME/.cvm/versions/$BASELINE/caffeine"

if [ ! -x "$BASELINE_BIN" ]; then
  echo "error: baseline binary not found at $BASELINE_BIN" >&2
  echo "       install it with: cvm install $BASELINE" >&2
  exit 2
fi

if [ "$BUILD" = 1 ]; then
  echo "==> building local caffeine ($CAFFEINE_REPO)"
  ( cd "$CAFFEINE_REPO" \
    && bun install >/dev/null \
    && ( cd caffeine_lsp && gleam build --target javascript >/dev/null ) \
    && ( cd caffeine_cli && gleam build --target javascript >/dev/null ) \
    && mkdir -p dist \
    && bun build --compile --minify --bytecode \
       --target=bun-linux-x64 \
       --outfile "$LOCAL_BIN" main.mjs )
fi

echo "==> binaries:"
printf '  baseline (%s): ' "$BASELINE"; "$BASELINE_BIN" --version
printf '  local:         '; "$LOCAL_BIN" --version

CORPUS="$PWD/corpus"
OUT="$PWD/results-local"
rm -rf "$OUT" && mkdir -p "$OUT"

# Build interleaved command list: for each corpus size, run baseline then local
# back-to-back so they share thermal/load conditions within the same hyperfine
# session. compare.py joins by name, so we strip the "baseline: "/"local: "
# prefixes when splitting the combined JSON below.
cmds=()
for b in $BENCHES; do
  case "$b" in
    small)  NAME="small (2 m, 4 exp)";    M="$CORPUS/small/measurements/";  E="$CORPUS/small/expectations/"  ;;
    medium) NAME="medium (5 m, 24 exp)";  M="$CORPUS/medium/measurements/"; E="$CORPUS/medium/expectations/" ;;
    large)  NAME="large (20 m, 120 exp)"; M="$CORPUS/large/measurements/";  E="$CORPUS/large/expectations/"  ;;
    huge)   NAME="huge (50 m, 600 exp)";  M="$CORPUS/huge/measurements/";   E="$CORPUS/huge/expectations/"   ;;
  esac
  cmds+=(-n "baseline: $NAME" "$BASELINE_BIN compile $M $E --quiet")
  cmds+=(-n "local: $NAME"    "$LOCAL_BIN compile $M $E --quiet")
done

echo "==> benching local vs $BASELINE ($SCOPE: warmup $WARMUP, runs $RUNS)"
hyperfine --warmup "$WARMUP" --runs "$RUNS" \
  --export-json "$OUT/$SCOPE.json" \
  --export-markdown "$OUT/$SCOPE.md" \
  "${cmds[@]}"

# Split the combined JSON into baseline + local files for compare.py.
# Stripping the prefix makes the bench names match across the two files,
# which is how compare.py joins them.
python3 - "$OUT/$SCOPE.json" "$OUT/$SCOPE.baseline.json" "$OUT/$SCOPE.local.json" <<'PY'
import json, sys
src, out_base, out_local = sys.argv[1:4]
with open(src) as f:
    data = json.load(f)

def split(prefix):
    out = []
    for r in data["results"]:
        if r["command"].startswith(prefix):
            r2 = dict(r)
            r2["command"] = r["command"][len(prefix):]
            out.append(r2)
    return {"results": out}

with open(out_base, "w") as f:
    json.dump(split("baseline: "), f, indent=2)
with open(out_local, "w") as f:
    json.dump(split("local: "), f, indent=2)
PY

echo
echo "==> comparison: local vs $BASELINE (same-run, apples-to-apples)"
python3 compare.py "$OUT/$SCOPE.baseline.json" "$OUT/$SCOPE.local.json" --threshold 10 || true
