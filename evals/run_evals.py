"""
CLI entry point for the Cloud Avengers eval framework.

Usage
-----
  python3 -m evals.run_evals [options]

Options
-------
  --fixture        Run fixture self-test (verify evaluators catch known-bad samples).
                   Exit 0 = all pass, 2 = fixture self-test failed.
  --report PATH    Path to JSON report for iteration history (default: evals/evals-report.json).
  --threshold N    Pass rate threshold 0–1 (default: 0.9).
  --repetitions N  Run fixtures N times for non-determinism check (default: 1).

Exit codes
----------
  0  Converged (pass rate >= threshold)
  1  Not converged
  2  Fixture self-test failed
"""
from __future__ import annotations

import argparse
import sys

from evals.runner import (
    append_iteration,
    load_report,
    print_summary,
    run_all_suites,
    save_report,
)


def run_fixture_selftest() -> bool:
    """
    Run the fixture self-test: verify that evaluators correctly catch known-bad samples.

    Returns True if all self-tests pass, False otherwise.
    Exits with code 2 on failure when called from the CLI.
    """
    print("Running fixture self-test …")
    suites = run_all_suites()

    all_pass = True
    for suite in suites:
        for detail in suite.item_details:
            fixture_name = detail["fixture"]
            expect_pass = detail["expect_pass"]
            actual_pass = detail["actual_pass"]
            item_passed = detail["item_passed"]

            if not actual_pass:
                all_pass = False
                print(
                    f"  ✗ SELF-TEST FAILED: {fixture_name}\n"
                    f"    expect_pass={expect_pass}, item_passed={item_passed}\n"
                    f"    Failing checks:"
                )
                for fc in detail["failing_checks"]:
                    print(f"      → {fc['check']}: {fc['reason']}")
            else:
                print(f"  ✓ {fixture_name}")

    if all_pass:
        print("\n✅ All fixture self-tests passed.")
    else:
        print("\n❌ Fixture self-test FAILED — evaluator logic has bugs.")
    return all_pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Cloud Avengers migration pipeline evaluator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--fixture",
        action="store_true",
        help="Run fixture self-test to verify evaluators catch known-bad samples.",
    )
    parser.add_argument(
        "--report",
        default="evals/evals-report.json",
        metavar="PATH",
        help="Path to JSON report for iteration history (default: evals/evals-report.json).",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.9,
        metavar="N",
        help="Pass rate threshold 0–1 (default: 0.9).",
    )
    parser.add_argument(
        "--repetitions",
        type=int,
        default=1,
        metavar="N",
        help="Run fixtures N times for non-determinism check (default: 1).",
    )
    args = parser.parse_args(argv)

    if args.fixture:
        ok = run_fixture_selftest()
        return 0 if ok else 2

    # Normal eval run
    suites = run_all_suites()
    converged = print_summary(suites, args.threshold)

    # Show trend from previous runs
    report = load_report(args.report)
    if report["iterations"]:
        prev = report["iterations"][-1]
        print(
            f"\n  Trend: previous run {prev['pass_rate']:.0%} → this run "
            f"{sum(s.passed for s in suites) / max(1, sum(s.total for s in suites)):.0%}"
        )

    report = append_iteration(report, suites, args.threshold)
    save_report(args.report, report)
    print(f"\n  Report written to: {args.report}")

    return 0 if converged else 1


if __name__ == "__main__":
    sys.exit(main())
