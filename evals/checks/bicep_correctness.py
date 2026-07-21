"""
Bicep correctness evaluator checks.

All checks are file-type aware:
- Orchestrator checks (subscription scope, resource group resource, module scope)
  only apply when the file contains module declarations.
- Storage checks only apply when Microsoft.Storage/storageAccounts is present.
- Private endpoint checks only apply when Microsoft.Network/private... is present.
"""
from __future__ import annotations

import re

from evals.framework import CheckResult, evaluator


def _has_modules(response: str) -> bool:
    """Return True if the Bicep content contains module declarations."""
    return bool(re.search(r"^\s*module\s+\w+", response, re.MULTILINE))


def _has_storage(response: str) -> bool:
    return "Microsoft.Storage/storageAccounts" in response


def _has_private_networking(response: str) -> bool:
    return bool(re.search(r"Microsoft\.Network/private(Endpoints|DnsZones)", response))


# ---------------------------------------------------------------------------
# Orchestrator-level checks (only apply to files with module declarations)
# ---------------------------------------------------------------------------

@evaluator
def subscription_scope_declared(response: str) -> CheckResult:
    """
    Orchestrator main.bicep MUST declare targetScope = 'subscription'.
    Only checked when the file contains module declarations.
    """
    if not _has_modules(response):
        return CheckResult(name="subscription_scope_declared", passed=True, score=1.0,
                           reason="Not an orchestrator file — check skipped.")
    passed = bool(re.search(r"targetScope\s*=\s*['\"]subscription['\"]", response))
    return CheckResult(
        name="subscription_scope_declared",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "targetScope = 'subscription' not found.",
    )


@evaluator
def resource_group_resource_declared(response: str) -> CheckResult:
    """
    Orchestrator must declare a resource group resource.
    Only checked when the file contains module declarations.
    """
    if not _has_modules(response):
        return CheckResult(name="resource_group_resource_declared", passed=True, score=1.0,
                           reason="Not an orchestrator file — check skipped.")
    passed = bool(re.search(
        r"resource\s+\w+\s+'Microsoft\.Resources/resourceGroups@",
        response,
    ))
    return CheckResult(
        name="resource_group_resource_declared",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "No 'Microsoft.Resources/resourceGroups@...' resource found.",
    )


@evaluator
def modules_have_scope_rg(response: str) -> CheckResult:
    """
    Every module declaration in an orchestrator MUST have 'scope: rg' (or scope: <rgVar>).

    Uses a line-based approach — NOT brace-matching regex — because Bicep template
    literals like ${environment} contain '}' which breaks regex brace counting.
    """
    if not _has_modules(response):
        return CheckResult(name="modules_have_scope_rg", passed=True, score=1.0,
                           reason="Not an orchestrator file — check skipped.")

    lines = response.split("\n")
    module_starts = [
        i for i, line in enumerate(lines)
        if re.match(r"\s*module\s+\w+", line)
    ]

    missing_scope: list[int] = []
    for idx, start in enumerate(module_starts):
        end = module_starts[idx + 1] if idx + 1 < len(module_starts) else start + 30
        block_text = "\n".join(lines[start: min(end, start + 30)])
        if not re.search(r"^\s*scope\s*:", block_text, re.MULTILINE):
            missing_scope.append(idx + 1)  # 1-based module index

    passed = len(missing_scope) == 0
    return CheckResult(
        name="modules_have_scope_rg",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else f"Module(s) missing 'scope:': indices {missing_scope}",
    )


@evaluator
def no_resource_group_location_function(response: str) -> CheckResult:
    """
    Subscription-scoped templates must NOT use resourceGroup().location.
    That function is invalid at subscription scope.
    Only checked when the file contains module declarations (orchestrator).
    """
    if not _has_modules(response):
        return CheckResult(name="no_resource_group_location_function", passed=True, score=1.0,
                           reason="Not an orchestrator file — check skipped.")
    found = bool(re.search(r"resourceGroup\(\)\.location", response))
    return CheckResult(
        name="no_resource_group_location_function",
        passed=not found,
        score=0.0 if found else 1.0,
        reason="resourceGroup().location is invalid in subscription-scoped template." if found else "",
    )


@evaluator
def deploy_command_is_sub_create(response: str) -> CheckResult:
    """
    When a deployment command appears in the Bicep file comment header or
    inline documentation, it MUST be 'az deployment sub create', NOT 'group create'.
    Only checked when the file contains module declarations (orchestrator).
    """
    if not _has_modules(response):
        return CheckResult(name="deploy_command_is_sub_create", passed=True, score=1.0,
                           reason="Not an orchestrator file — check skipped.")
    has_sub_create = "az deployment sub create" in response
    has_group_create = "az deployment group create" in response
    if has_group_create:
        return CheckResult(
            name="deploy_command_is_sub_create",
            passed=False,
            score=0.0,
            reason="'az deployment group create' found — must use 'az deployment sub create'.",
        )
    if not has_sub_create:
        return CheckResult(
            name="deploy_command_is_sub_create",
            passed=False,
            score=0.0,
            reason="'az deployment sub create' not found in orchestrator.",
        )
    return CheckResult(name="deploy_command_is_sub_create", passed=True, score=1.0)


# ---------------------------------------------------------------------------
# Storage-level checks
# ---------------------------------------------------------------------------

@evaluator
def storage_public_access_disabled(response: str) -> CheckResult:
    """publicNetworkAccess must be 'Disabled' for storage accounts."""
    if not _has_storage(response):
        return CheckResult(name="storage_public_access_disabled", passed=True, score=1.0,
                           reason="No storage account resource — check skipped.")
    passed = bool(re.search(r"publicNetworkAccess\s*:\s*['\"]Disabled['\"]", response))
    return CheckResult(
        name="storage_public_access_disabled",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "publicNetworkAccess: 'Disabled' not found.",
    )


@evaluator
def shared_key_access_disabled(response: str) -> CheckResult:
    """allowSharedKeyAccess must be false for storage accounts."""
    if not _has_storage(response):
        return CheckResult(name="shared_key_access_disabled", passed=True, score=1.0,
                           reason="No storage account resource — check skipped.")
    passed = bool(re.search(r"allowSharedKeyAccess\s*:\s*false", response))
    return CheckResult(
        name="shared_key_access_disabled",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "allowSharedKeyAccess: false not found.",
    )


# ---------------------------------------------------------------------------
# Private networking checks
# ---------------------------------------------------------------------------

@evaluator
def private_endpoint_present(response: str) -> CheckResult:
    """Microsoft.Network/privateEndpoints must be declared."""
    if not _has_private_networking(response):
        return CheckResult(name="private_endpoint_present", passed=True, score=1.0,
                           reason="No private networking resources — check skipped.")
    passed = "Microsoft.Network/privateEndpoints" in response
    return CheckResult(
        name="private_endpoint_present",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "Microsoft.Network/privateEndpoints not found.",
    )


@evaluator
def private_dns_zone_linked(response: str) -> CheckResult:
    """Microsoft.Network/privateDnsZones/virtualNetworkLinks must be declared."""
    if not _has_private_networking(response):
        return CheckResult(name="private_dns_zone_linked", passed=True, score=1.0,
                           reason="No private networking resources — check skipped.")
    passed = "Microsoft.Network/privateDnsZones/virtualNetworkLinks" in response
    return CheckResult(
        name="private_dns_zone_linked",
        passed=passed,
        score=1.0 if passed else 0.0,
        reason="" if passed else "Microsoft.Network/privateDnsZones/virtualNetworkLinks not found.",
    )
