#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for run-what-if.ps1 — static analysis only (no Azure calls).
#>
Describe "run-what-if.ps1" {
    $Script = "$PSScriptRoot/../../skills/deployment-validation/scripts/run-what-if.ps1"

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
        It "should declare -ResourceGroup parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Script, [ref]$null, [ref]$null)
            $params = $ast.FindAll(
                { $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
            $paramNames = $params | ForEach-Object { $_.Name.VariablePath.UserPath }
            $paramNames | Should -Contain "ResourceGroup"
        }

        It "should declare -Environment parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Script, [ref]$null, [ref]$null)
            $params = $ast.FindAll(
                { $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
            $paramNames = $params | ForEach-Object { $_.Name.VariablePath.UserPath }
            $paramNames | Should -Contain "Environment"
        }
    }

    Context "Output directory" {
        It "should reference the outputs/deployment-validation path" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "outputs[/\\]deployment-validation"
        }
    }
}
