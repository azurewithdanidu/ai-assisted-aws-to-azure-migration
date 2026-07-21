"""
Eval runner — iterative evaluation loop with Wilson score confidence intervals.

Suites
------
pm-behaviour     : fixture-based, uses PM behaviour checks
deploy-commands  : fixture-based, uses deploy command checks
bicep-correctness: fixture-based (or real workspace files if present), uses Bicep checks

Fixture inversion
-----------------
For items where expect_pass=False (BAD fixtures):
  actual_pass = item_result.passed == expect_pass
  i.e. a BAD fixture that FAILS the checks counts as PASS (evaluator is working).

Wilson CI
---------
wilson_ci(passed, total, confidence=0.95) using z=1.96.
"""
from __future__ import annotations

import json
import math
import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any

from evals.framework import EvalItem, ItemResult, LocalEvaluator
from evals.checks import pm_behavior, bicep_correctness, deploy_commands
from evals.fixtures import conversations as conv_fixtures
from evals.fixtures import bicep_samples as bicep_fixtures


# ---------------------------------------------------------------------------
# Wilson score confidence interval
# ---------------------------------------------------------------------------

def wilson_ci(passed: int, total: int, confidence: float = 0.95) -> tuple[float, float]:
    """
    Return (lower, upper) Wilson score confidence interval.
    Uses z=1.96 for 95% confidence.
    """
    if total == 0:
        return (0.0, 1.0)
    z = 1.96
    p = passed / total
    n = total
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half_width = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return (max(0.0, centre - half_width), min(1.0, centre + half_width))


# ---------------------------------------------------------------------------
# Suite definitions
# ---------------------------------------------------------------------------

def _pm_items() -> list[tuple[EvalItem, bool]]:
    """Return (item, expect_pass) pairs for the pm-behaviour suite."""
    fixtures_map = {
        "GOOD_PM_SIGNED_IN_RESPONSE": conv_fixtures.GOOD_PM_SIGNED_IN_RESPONSE,
        "BAD_PM_SIGNED_IN_STALLS": conv_fixtures.BAD_PM_SIGNED_IN_STALLS,
        "BAD_PM_MANY_QUESTIONS": conv_fixtures.BAD_PM_MANY_QUESTIONS,
        "BAD_PM_INVOKES_AWS_DISCOVERY": conv_fixtures.BAD_PM_INVOKES_AWS_DISCOVERY,
    }
    pairs = []
    for name, response in fixtures_map.items():
        expect_pass = conv_fixtures.PM_SIGNED_IN_EXPECTATIONS[name]
        item = EvalItem(
            query=conv_fixtures.SIGNED_IN_QUERY,
            response=response,
            metadata={"fixture": name, "expect_pass": expect_pass},
        )
        pairs.append((item, expect_pass))
    return pairs


def _deploy_items() -> list[tuple[EvalItem, bool]]:
    """Return (item, expect_pass) pairs for the deploy-commands suite."""
    fixtures_map = {
        "GOOD_DEPLOY_RESPONSE": conv_fixtures.GOOD_DEPLOY_RESPONSE,
        "BAD_DEPLOY_GROUP_CREATE": conv_fixtures.BAD_DEPLOY_GROUP_CREATE,
        "BAD_DEPLOY_NO_LOCATION": conv_fixtures.BAD_DEPLOY_NO_LOCATION,
    }
    pairs = []
    for name, response in fixtures_map.items():
        expect_pass = conv_fixtures.DEPLOY_EXPECTATIONS[name]
        item = EvalItem(
            query="Deploy the infrastructure to Azure",
            response=response,
            metadata={"fixture": name, "expect_pass": expect_pass},
        )
        pairs.append((item, expect_pass))
    return pairs


def _bicep_items() -> list[tuple[EvalItem, bool]]:
    """Return (item, expect_pass) pairs for the bicep-correctness suite."""
    fixtures_map = {
        "GOOD_MAIN_BICEP": bicep_fixtures.GOOD_MAIN_BICEP,
        "GOOD_STORAGE_BICEP": bicep_fixtures.GOOD_STORAGE_BICEP,
        "GOOD_PRIVATE_ENDPOINT_BICEP": bicep_fixtures.GOOD_PRIVATE_ENDPOINT_BICEP,
        "BAD_MAIN_BICEP_RG_SCOPE": bicep_fixtures.BAD_MAIN_BICEP_RG_SCOPE,
        "BAD_MAIN_BICEP_MISSING_MODULE_SCOPE": bicep_fixtures.BAD_MAIN_BICEP_MISSING_MODULE_SCOPE,
        "BAD_STORAGE_BICEP_PUBLIC_ACCESS": bicep_fixtures.BAD_STORAGE_BICEP_PUBLIC_ACCESS,
    }
    pairs = []
    for name, response in fixtures_map.items():
        expect_pass = bicep_fixtures.BICEP_EXPECTATIONS[name]
        item = EvalItem(
            query="Generate Bicep template",
            response=response,
            metadata={"fixture": name, "expect_pass": expect_pass},
        )
        pairs.append((item, expect_pass))
    return pairs


# ---------------------------------------------------------------------------
# Core run function
# ---------------------------------------------------------------------------

@dataclass
class SuiteResult:
    name: str
    passed: int
    total: int
    ci_lower: float
    ci_upper: float
    item_details: list[dict]

    @property
    def pass_rate(self) -> float:
        return self.passed / self.total if self.total else 0.0


def _run_suite(
    name: str,
    items_with_expectations: list[tuple[EvalItem, bool]],
    evaluator: LocalEvaluator,
) -> SuiteResult:
    """Run one suite, apply fixture inversion, return SuiteResult."""
    passed_count = 0
    total_count = 0
    item_details = []

    for item, expect_pass in items_with_expectations:
        result = evaluator.evaluate([item])
        item_result = result.item_results[0]

        # Fixture inversion: BAD fixture that FAILS checks = evaluator working = PASS
        actual_pass = item_result.passed == expect_pass
        if actual_pass:
            passed_count += 1
        total_count += 1

        failing = [
            {"check": c.name, "reason": c.reason, "score": c.score}
            for c in item_result.failing_checks()
        ]
        item_details.append({
            "fixture": item.metadata.get("fixture", ""),
            "expect_pass": expect_pass,
            "item_passed": item_result.passed,
            "actual_pass": actual_pass,
            "score": item_result.score,
            "failing_checks": failing,
        })

    ci_lower, ci_upper = wilson_ci(passed_count, total_count)
    return SuiteResult(
        name=name,
        passed=passed_count,
        total=total_count,
        ci_lower=ci_lower,
        ci_upper=ci_upper,
        item_details=item_details,
    )


def run_all_suites() -> list[SuiteResult]:
    """Run all three suites and return results."""
    pm_evaluator = LocalEvaluator(
        pm_behavior.no_stall_on_signed_in,
        pm_behavior.uses_az_account_show,
        pm_behavior.defaults_region_australiaeast,
        pm_behavior.proceeds_without_all_inputs,
        pm_behavior.skips_aws_discovery_for_direct_azure,
        name="pm-behaviour",
    )

    deploy_evaluator = LocalEvaluator(
        deploy_commands.uses_deployment_sub_create,
        deploy_commands.no_deployment_group_create,
        deploy_commands.deploy_cmd_has_location_flag,
        deploy_commands.deploy_cmd_has_parameters_flag,
        deploy_commands.what_if_mentioned,
        name="deploy-commands",
    )

    bicep_evaluator = LocalEvaluator(
        bicep_correctness.subscription_scope_declared,
        bicep_correctness.resource_group_resource_declared,
        bicep_correctness.modules_have_scope_rg,
        bicep_correctness.no_resource_group_location_function,
        bicep_correctness.deploy_command_is_sub_create,
        bicep_correctness.storage_public_access_disabled,
        bicep_correctness.shared_key_access_disabled,
        bicep_correctness.private_endpoint_present,
        bicep_correctness.private_dns_zone_linked,
        name="bicep-correctness",
    )

    return [
        _run_suite("pm-behaviour", _pm_items(), pm_evaluator),
        _run_suite("deploy-commands", _deploy_items(), deploy_evaluator),
        _run_suite("bicep-correctness", _bicep_items(), bicep_evaluator),
    ]


# ---------------------------------------------------------------------------
# Report persistence
# ---------------------------------------------------------------------------

def load_report(path: str) -> dict:
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {"iterations": []}


def save_report(path: str, report: dict) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        json.dump(report, f, indent=2)


def append_iteration(report: dict, suites: list[SuiteResult], threshold: float) -> dict:
    total_passed = sum(s.passed for s in suites)
    total_items = sum(s.total for s in suites)
    ci_lower, ci_upper = wilson_ci(total_passed, total_items)
    converged = (total_passed / total_items >= threshold) if total_items else False

    iteration = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total_passed": total_passed,
        "total_items": total_items,
        "pass_rate": total_passed / total_items if total_items else 0.0,
        "ci_lower": ci_lower,
        "ci_upper": ci_upper,
        "converged": converged,
        "threshold": threshold,
        "suites": [
            {
                "name": s.name,
                "passed": s.passed,
                "total": s.total,
                "pass_rate": s.pass_rate,
                "ci_lower": s.ci_lower,
                "ci_upper": s.ci_upper,
                "items": s.item_details,
            }
            for s in suites
        ],
    }
    report["iterations"].append(iteration)
    return report


# ---------------------------------------------------------------------------
# Console output helpers
# ---------------------------------------------------------------------------

def print_summary(suites: list[SuiteResult], threshold: float) -> bool:
    """Print summary to console. Returns True if converged."""
    total_passed = sum(s.passed for s in suites)
    total_items = sum(s.total for s in suites)
    ci_lower, ci_upper = wilson_ci(total_passed, total_items)
    pass_rate = total_passed / total_items if total_items else 0.0
    converged = pass_rate >= threshold

    print("\n" + "=" * 60)
    print("EVAL RESULTS SUMMARY")
    print("=" * 60)
    for s in suites:
        status = "✅" if s.pass_rate >= threshold else "❌"
        print(
            f"  {status} {s.name:<25} {s.passed}/{s.total} "
            f"({s.pass_rate:.0%})  CI [{s.ci_lower:.1%}, {s.ci_upper:.1%}]"
        )
        for detail in s.item_details:
            if not detail["actual_pass"]:
                icon = "  ✗"
                print(f"      {icon} {detail['fixture']} (expect_pass={detail['expect_pass']})")
                for fc in detail["failing_checks"]:
                    print(f"          → {fc['check']}: {fc['reason']}")

    print("-" * 60)
    overall_status = "✅ CONVERGED" if converged else "❌ NOT CONVERGED"
    print(
        f"  {overall_status}  {total_passed}/{total_items} ({pass_rate:.0%})  "
        f"CI [{ci_lower:.1%}, {ci_upper:.1%}]  threshold={threshold:.0%}"
    )
    print("=" * 60)
    return converged
