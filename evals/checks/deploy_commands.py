"""
Deploy command evaluator checks.

Validates that deployment commands use subscription-scope equivalents
(az deployment sub create / what-if) rather than resource-group-scope
commands that cannot create resource groups.

Regression: 2026-07-21 — az deployment group create used with subscription-scoped template.
"""
from __future__ import annotations

from evals.framework import CheckResult, evaluator


@evaluator
def uses_deployment_sub_create(response: str) -> CheckResult:
    """Response must contain 'az deployment sub create'."""
    passed = "az deployment sub create" in response
    return CheckResult(
        name="uses_deployment_sub_create",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "'az deployment sub create' not found.",
    )


@evaluator
def no_deployment_group_create(response: str) -> CheckResult:
    """Response must NOT contain 'az deployment group create'."""
    found = "az deployment group create" in response
    return CheckResult(
        name="no_deployment_group_create",
        passed=not found,
        score=0.0 if found else 1.0,
        reason="'az deployment group create' found — forbidden for subscription-scoped templates." if found else "",
    )


@evaluator
def deploy_cmd_has_location_flag(response: str) -> CheckResult:
    """
    The 'az deployment sub create' command must include '--location'.

    Uses a string-window approach — NOT multiline regex — to avoid
    catastrophic backtracking on large responses.
    """
    cmd_start = response.find("az deployment sub create")
    if cmd_start == -1:
        return CheckResult(
            name="deploy_cmd_has_location_flag",
            passed=False,
            score=0.0,
            reason="'az deployment sub create' not found; cannot check --location flag.",
        )
    cmd_window = response[cmd_start: cmd_start + 400]
    passed = "--location" in cmd_window
    return CheckResult(
        name="deploy_cmd_has_location_flag",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "'--location' flag missing from 'az deployment sub create'.",
    )


@evaluator
def deploy_cmd_has_parameters_flag(response: str) -> CheckResult:
    """The 'az deployment sub create' command must include '--parameters'."""
    cmd_start = response.find("az deployment sub create")
    if cmd_start == -1:
        return CheckResult(
            name="deploy_cmd_has_parameters_flag",
            passed=False,
            score=0.0,
            reason="'az deployment sub create' not found; cannot check --parameters flag.",
        )
    cmd_window = response[cmd_start: cmd_start + 400]
    passed = "--parameters" in cmd_window
    return CheckResult(
        name="deploy_cmd_has_parameters_flag",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "'--parameters' flag missing from 'az deployment sub create'.",
    )


@evaluator
def what_if_mentioned(response: str) -> CheckResult:
    """
    Response should mention 'az deployment sub what-if' or 'what-if'.

    Advisory check only: score=0.5 if missing (non-blocking, passed=True).
    """
    lower = response.lower()
    if "az deployment sub what-if" in lower or "what-if" in lower:
        return CheckResult(name="what_if_mentioned", passed=True, score=1.0)
    return CheckResult(
        name="what_if_mentioned",
        passed=True,  # advisory — non-blocking
        score=0.5,
        reason="'what-if' not mentioned (advisory — non-blocking).",
    )
