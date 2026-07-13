#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for smoke-test.ps1 — static analysis only (no Azure calls).
#>
Describe "smoke-test.ps1" {
    BeforeAll {
        $script:ScriptPath = "$PSScriptRoot/../../skills/deployment-validation/scripts/smoke-test.ps1"
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

    Context "Required parameters" {
        foreach ($param in @("ResourceGroup", "Environment", "FunctionAppName", "KeyVaultName")) {
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

    Context "Check coverage" {
        It "should test at least an HTTP endpoint check" {
            $script:Content | Should -Match "(http|health|Invoke-WebRequest|curl)"
        }

        It "should test Key Vault access" {
            $script:Content | Should -Match "keyvault|KeyVault"
        }
    }
}
