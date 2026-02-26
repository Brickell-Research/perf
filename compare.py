#!/usr/bin/env python3
"""
Compare hyperfine benchmark results against a baseline.

Usage:
  python3 compare.py baseline.json current.json [--threshold 10]

Exit codes:
  0 = no regressions
  1 = regression detected (exceeds threshold)
  2 = error (missing files, parse error, etc.)
"""

import json
import sys
import argparse


def load_results(path):
    """Load hyperfine JSON and return {command_name: mean_seconds}."""
    with open(path) as f:
        data = json.load(f)
    return {r["command"]: r["mean"] for r in data["results"]}


def compare(baseline_path, current_path, threshold_pct):
    """Compare current results against baseline. Returns (passed, report_lines)."""
    try:
        baseline = load_results(baseline_path)
        current = load_results(current_path)
    except (FileNotFoundError, json.JSONDecodeError, KeyError) as e:
        return None, [f"Error loading results: {e}"]

    lines = []
    regressions = []
    max_name_len = max(len(n) for n in current) if current else 20

    lines.append(f"{'Benchmark':<{max_name_len}}  {'Baseline':>10}  {'Current':>10}  {'Change':>10}  Status")
    lines.append("-" * (max_name_len + 50))

    for name, current_mean in sorted(current.items()):
        if name not in baseline:
            lines.append(f"{name:<{max_name_len}}  {'N/A':>10}  {current_mean*1000:>9.1f}ms  {'new':>10}  --")
            continue

        baseline_mean = baseline[name]
        change_pct = ((current_mean - baseline_mean) / baseline_mean) * 100

        if change_pct > threshold_pct:
            status = f"REGRESSION (+{change_pct:.1f}%)"
            regressions.append((name, change_pct))
        elif change_pct < -threshold_pct:
            status = f"FASTER ({change_pct:.1f}%)"
        else:
            status = "OK"

        lines.append(
            f"{name:<{max_name_len}}  "
            f"{baseline_mean*1000:>9.1f}ms  "
            f"{current_mean*1000:>9.1f}ms  "
            f"{change_pct:>+9.1f}%  "
            f"{status}"
        )

    # Check for removed benchmarks
    for name in baseline:
        if name not in current:
            lines.append(f"{name:<{max_name_len}}  {baseline[name]*1000:>9.1f}ms  {'removed':>10}  {'N/A':>10}  --")

    lines.append("")
    if regressions:
        lines.append(f"FAILED: {len(regressions)} regression(s) exceeded {threshold_pct}% threshold:")
        for name, pct in regressions:
            lines.append(f"  - {name}: +{pct:.1f}%")
        return False, lines
    else:
        lines.append(f"PASSED: All benchmarks within {threshold_pct}% threshold.")
        return True, lines


def main():
    parser = argparse.ArgumentParser(description="Compare hyperfine benchmark results")
    parser.add_argument("baseline", help="Path to baseline hyperfine JSON")
    parser.add_argument("current", help="Path to current hyperfine JSON")
    parser.add_argument("--threshold", type=float, default=10.0,
                        help="Regression threshold in percent (default: 10)")
    args = parser.parse_args()

    passed, lines = compare(args.baseline, args.current, args.threshold)
    print("\n".join(lines))

    if passed is None:
        sys.exit(2)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
