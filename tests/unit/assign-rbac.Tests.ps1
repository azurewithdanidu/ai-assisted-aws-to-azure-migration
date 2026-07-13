#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for assign-rbac.ps1 — static analysis only (no Azure calls).
#>
Describe "assign-rbac.ps1" {
    BeforeAll {
        $script:ScriptPath = "$PSScriptRoot/../../skills/azure-auth-patterns/scripts/assign-rbac.ps1"
        $script:Content    = Get-Content $script:ScriptPath -Raw -ErrorAction SilentlyContinue
    }

    Context "File exists" {
        It "should exist at the expected path" {
            $script:ScriptPath | Should -Exist
        }
    }

    Context "Syntax check" {
        It "should parse without errors" {
            $errors = @()
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }

    Context "Role GUID map" {
        $expectedRoles = @{
            StorageBlobDataContributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
            StorageBlobDataReader      = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
            KeyVaultSecretsUser        = "4633458b-17de-408a-b874-0445c86b69e6"
            ServiceBusDataSender       = "69a216fc-b8fb-44d8-bc22-1f3c2cd27a39"
            ServiceBusDataReceiver     = "4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0"
            Contributor                = "b24988ac-6180-42a0-ab88-20f7382dd24c"
            Reader                     = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
        }

        foreach ($roleName in $expectedRoles.Keys) {
            It "should contain GUID for $roleName ($($expectedRoles[$roleName]))" -TestCases @(
                @{ RoleGuid = $expectedRoles[$roleName] }
            ) {
                param($RoleGuid)
                $script:Content | Should -Match $RoleGuid
            }
        }
    }

    Context "Idempotency" {
        It "should check for existing assignment before creating" {
            $script:Content | Should -Match "role assignment list"
        }
    }

    Context "Required parameters" {
        foreach ($param in @("PrincipalId", "Scope", "Role")) {
            It "should declare -$param parameter" -TestCases @(@{ ParamName = $param }) {
                param($ParamName)
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    $script:ScriptPath, [ref]$null, [ref]$null)
                $params = $ast.FindAll(
                    { $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
                $paramNames = $params | ForEach-Object { $_.Name.VariablePath.UserPath }
                $paramNames | Should -Contain $ParamName
            }
        }
    }
}
