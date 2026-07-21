"""
Core evaluation framework for the Cloud Avengers migration pipeline.

Mirrors the Microsoft Agent Framework evaluation API:
https://learn.microsoft.com/en-us/agent-framework/agents/evaluation

Pure Python >= 3.10, no external dependencies.
"""
from __future__ import annotations

import functools
import inspect
import re
from dataclasses import dataclass, field
from typing import Any, Callable


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class EvalItem:
    """A single evaluation item (query + response pair)."""
    query: str = ""
    response: str = ""
    expected_output: str = ""
    conversation: list[dict] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)


@dataclass
class CheckResult:
    """Result produced by a single evaluator check."""
    name: str
    passed: bool
    score: float = 1.0
    reason: str = ""

    def __post_init__(self) -> None:
        if not self.passed and self.score == 1.0:
            self.score = 0.0


@dataclass
class ItemResult:
    """Aggregated result for one EvalItem across all checks."""
    item: EvalItem
    checks: list[CheckResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(c.passed for c in self.checks)

    @property
    def score(self) -> float:
        if not self.checks:
            return 1.0
        return sum(c.score for c in self.checks) / len(self.checks)

    def failing_checks(self) -> list[CheckResult]:
        return [c for c in self.checks if not c.passed]


@dataclass
class EvalResults:
    """Aggregated results for one evaluation run."""
    provider: str
    item_results: list[ItemResult] = field(default_factory=list)

    @property
    def passed(self) -> int:
        return sum(1 for r in self.item_results if r.passed)

    @property
    def total(self) -> int:
        return len(self.item_results)

    @property
    def pass_rate(self) -> float:
        return self.passed / self.total if self.total else 0.0

    def raise_for_status(self, threshold: float = 0.9) -> None:
        if self.pass_rate < threshold:
            raise EvalNotPassedError(
                f"Pass rate {self.pass_rate:.1%} below threshold {threshold:.1%} "
                f"({self.passed}/{self.total} passed)"
            )


class EvalNotPassedError(Exception):
    """Raised when EvalResults.raise_for_status() fails."""


# ---------------------------------------------------------------------------
# @evaluator decorator
# ---------------------------------------------------------------------------

_INJECTABLE = {"query", "response", "expected_output", "conversation", "metadata"}


def evaluator(fn: Callable) -> Callable:
    """
    Decorator that turns a plain function into an evaluator check.

    The decorated function declares only the parameters it needs from EvalItem
    (any subset of: query, response, expected_output, conversation, metadata).
    The decorator injects those values automatically.

    Return value can be:
      bool         — True/False → CheckResult(passed=…, score=1.0 or 0.0)
      float        — ≥ 0.5 → passed=True, else False
      CheckResult  — returned as-is (name is set to fn.__name__ if blank)
      dict         — keys: passed (bool), score (float, optional), reason (str, optional)
    """
    sig = inspect.signature(fn)
    param_names = list(sig.parameters.keys())
    injectable = [p for p in param_names if p in _INJECTABLE]

    @functools.wraps(fn)
    def wrapper(item: EvalItem) -> CheckResult:
        kwargs = {p: getattr(item, p) for p in injectable}
        raw = fn(**kwargs)

        if isinstance(raw, CheckResult):
            if not raw.name:
                raw.name = fn.__name__
            return raw
        if isinstance(raw, dict):
            passed = bool(raw.get("passed", True))
            score = float(raw.get("score", 1.0 if passed else 0.0))
            reason = str(raw.get("reason", ""))
            return CheckResult(name=fn.__name__, passed=passed, score=score, reason=reason)
        if isinstance(raw, float):
            passed = raw >= 0.5
            return CheckResult(name=fn.__name__, passed=passed, score=raw)
        # bool (or truthy/falsy)
        passed = bool(raw)
        return CheckResult(name=fn.__name__, passed=passed, score=1.0 if passed else 0.0)

    wrapper._is_evaluator = True  # type: ignore[attr-defined]
    return wrapper


# ---------------------------------------------------------------------------
# Factory check builders
# ---------------------------------------------------------------------------

def keyword_check(*keywords: str) -> Callable[[EvalItem], CheckResult]:
    """Return an evaluator that passes when response contains ALL keywords (case-insensitive)."""
    def _check(item: EvalItem) -> CheckResult:
        resp = item.response.lower()
        missing = [kw for kw in keywords if kw.lower() not in resp]
        passed = len(missing) == 0
        reason = f"Missing keywords: {missing}" if missing else ""
        return CheckResult(
            name=f"keyword_check({', '.join(keywords)})",
            passed=passed,
            score=1.0 if passed else 0.0,
            reason=reason,
        )
    _check._is_evaluator = True  # type: ignore[attr-defined]
    return _check


def no_keyword_check(*keywords: str) -> Callable[[EvalItem], CheckResult]:
    """Return an evaluator that passes when response contains NONE of the keywords."""
    def _check(item: EvalItem) -> CheckResult:
        resp = item.response.lower()
        found = [kw for kw in keywords if kw.lower() in resp]
        passed = len(found) == 0
        reason = f"Forbidden keywords found: {found}" if found else ""
        return CheckResult(
            name=f"no_keyword_check({', '.join(keywords)})",
            passed=passed,
            score=1.0 if passed else 0.0,
            reason=reason,
        )
    _check._is_evaluator = True  # type: ignore[attr-defined]
    return _check


def regex_check(pattern: str, flags: int = re.IGNORECASE) -> Callable[[EvalItem], CheckResult]:
    """Return an evaluator that passes when response matches the regex pattern."""
    compiled = re.compile(pattern, flags)

    def _check(item: EvalItem) -> CheckResult:
        passed = bool(compiled.search(item.response))
        reason = "" if passed else f"Pattern not found: {pattern!r}"
        return CheckResult(
            name=f"regex_check({pattern!r})",
            passed=passed,
            score=1.0 if passed else 0.0,
            reason=reason,
        )
    _check._is_evaluator = True  # type: ignore[attr-defined]
    return _check


def no_regex_check(pattern: str, flags: int = re.IGNORECASE) -> Callable[[EvalItem], CheckResult]:
    """Return an evaluator that passes when response does NOT match the regex pattern."""
    compiled = re.compile(pattern, flags)

    def _check(item: EvalItem) -> CheckResult:
        matched = compiled.search(item.response)
        passed = matched is None
        reason = f"Forbidden pattern found: {matched.group()!r}" if matched else ""
        return CheckResult(
            name=f"no_regex_check({pattern!r})",
            passed=passed,
            score=1.0 if passed else 0.0,
            reason=reason,
        )
    _check._is_evaluator = True  # type: ignore[attr-defined]
    return _check


# ---------------------------------------------------------------------------
# LocalEvaluator
# ---------------------------------------------------------------------------

class LocalEvaluator:
    """
    Runs a list of evaluator checks against a list of EvalItems.

    Parameters
    ----------
    *checks:
        Callables decorated with @evaluator or produced by keyword_check etc.
    name:
        Human-readable name for this evaluator (used in reports).
    num_repetitions:
        Run each item this many times and aggregate (for non-determinism testing).
        Currently all checks are deterministic, so this is always 1 in practice.
    """

    def __init__(self, *checks: Callable, name: str = "LocalEvaluator", num_repetitions: int = 1) -> None:
        self.checks = list(checks)
        self.name = name
        self.num_repetitions = max(1, num_repetitions)

    def evaluate(self, items: list[EvalItem]) -> EvalResults:
        results = EvalResults(provider=self.name)
        for item in items:
            check_results: list[CheckResult] = []
            for check in self.checks:
                for _ in range(self.num_repetitions):
                    cr = check(item)
                    check_results.append(cr)
            results.item_results.append(ItemResult(item=item, checks=check_results))
        return results
