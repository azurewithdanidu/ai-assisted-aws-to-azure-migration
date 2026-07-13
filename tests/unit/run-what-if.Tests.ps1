#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for run-what-if.ps1 — static analysis only (no Azure calls).
#>
Describe "run-what-if.ps1" {
    BeforeAll {
        $script:ScriptPath = "$PSScriptRoot/../../skills/what-if-validation/scripts/run-what-if.ps1"
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
        foreach ($param in @("ResourceGroup", "Environment")) {
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

    Context "Output directory" {
        It "should reference the outputs/deployment-validation path" {
            $script:Content | Should -Match "outputs[/\\]deployment-validation"
        }
    }
}
