"""
PM behaviour evaluator checks.

Validates that the migration-project-manager agent behaves correctly in common
scenarios: not stalling when the user is already signed in, defaulting to
australiaeast, and not unnecessarily invoking AWS Phase 1 for Azure-only tasks.
"""
from __future__ import annotations

import re

from evals.framework import CheckResult, evaluator


@evaluator
def no_stall_on_signed_in(response: str) -> CheckResult:
    """
    When the user says they are already signed in, the PM must NOT ask for
    the subscription ID — it should run 'az account show' instead.

    Regression: 2026-07-21-pm-stall
    """
    stall_patterns = [
        r"could you provide your azure subscription",
        r"please provide.*?subscription\s*id",
        r"need.*?subscription\s*id",
        r"what is your.*?subscription",
        r"provide.*?subscription\s*(id|identifier)",
        r"share.*?subscription\s*id",
    ]
    for pattern in stall_patterns:
        if re.search(pattern, response, re.IGNORECASE):
            return CheckResult(
                name="no_stall_on_signed_in",
                passed=False,
                score=0.0,
                reason=f"PM asked for subscription ID (matched: {pattern!r}). "
                       "Should use 'az account show' instead.",
            )
    return CheckResult(name="no_stall_on_signed_in", passed=True, score=1.0)


@evaluator
def uses_az_account_show(response: str) -> CheckResult:
    """PM must reference 'az account show' to discover the active subscription."""
    passed = "az account show" in response.lower()
    return CheckResult(
        name="uses_az_account_show",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "'az account show' not found in response.",
    )


@evaluator
def defaults_region_australiaeast(response: str) -> CheckResult:
    """PM must default to 'australiaeast' when no region is specified."""
    passed = "australiaeast" in response.lower()
    return CheckResult(
        name="defaults_region_australiaeast",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "'australiaeast' not referenced in response.",
    )


@evaluator
def proceeds_without_all_inputs(response: str) -> CheckResult:
    """
    PM should proceed with sensible defaults rather than asking many questions.
    At most 1 question mark is acceptable.

    Scoring: score = max(0.0, 1.0 - max(0, question_count - 1) * 0.3)
    """
    question_count = response.count("?")
    score = max(0.0, 1.0 - max(0, question_count - 1) * 0.3)
    passed = score >= 0.5
    return CheckResult(
        name="proceeds_without_all_inputs",
        passed=passed,
        score=score,
        reason=(
            f"{question_count} question mark(s) found. Expected ≤ 1."
            if not passed else ""
        ),
    )


@evaluator
def skips_aws_discovery_for_direct_azure(response: str) -> CheckResult:
    """
    For direct Azure deployment tasks the PM must NOT invoke AWS Phase 1.

    Passes if 'aws discovery' or 'phase 1' appear only alongside 'skip',
    or do not appear at all.
    """
    lower = response.lower()
    triggers = ["aws discovery", "phase 1"]
    for trigger in triggers:
        idx = lower.find(trigger)
        while idx != -1:
            # Check ±60 chars around the trigger for a 'skip' indicator
            window = lower[max(0, idx - 60): idx + len(trigger) + 60]
            if "skip" not in window:
                return CheckResult(
                    name="skips_aws_discovery_for_direct_azure",
                    passed=False,
                    score=0.0,
                    reason=f"PM invoked '{trigger}' without indicating it should be skipped "
                           "for a direct Azure task.",
                )
            idx = lower.find(trigger, idx + 1)
    return CheckResult(name="skips_aws_discovery_for_direct_azure", passed=True, score=1.0)
