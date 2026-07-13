#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for smoke-test.ps1 — static analysis only (no Azure calls).
#>
Describe "smoke-test.ps1" {
    $Script = "$PSScriptRoot/../../skills/deployment-validation/scripts/smoke-test.ps1"

    Context "File exists" {
        It "should exist at the expected path" {
            $Script | Should -Exist
        }
    }

    Context "Syntax check" {
        It "should parse without errors" {
            $errors = @()
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $Script, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }

    Context "Required parameters" {
        foreach ($param in @("ResourceGroup", "Environment", "FunctionAppName", "KeyVaultName")) {
            It "should declare -$param parameter" {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    $Script, [ref]$null, [ref]$null)
                $params = $ast.FindAll(
                    { $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
                $paramNames = $params | ForEach-Object { $_.Name.VariablePath.UserPath }
                $paramNames | Should -Contain $param
            }
        }
    }

    Context "Check coverage" {
        It "should test at least an HTTP endpoint check" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "(http|health|Invoke-WebRequest|curl)"
        }

        It "should test Key Vault access" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "keyvault|KeyVault"
        }
    }
}
