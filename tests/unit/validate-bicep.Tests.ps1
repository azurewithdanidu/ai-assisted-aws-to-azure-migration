#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for validate-bicep.ps1 — static analysis only (no Azure calls).
#>
Describe "validate-bicep.ps1" {
    BeforeAll {
        $script:ScriptPath = "$PSScriptRoot/../../skills/iac-transformation/scripts/validate-bicep.ps1"
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

    Context "Core behaviours" {
        It "should call az bicep build" {
            $script:Content | Should -Match "bicep build"
        }

        It "should call az bicep restore" {
            $script:Content | Should -Match "bicep restore"
        }

        It "should recurse over .bicep files" {
            $script:Content | Should -Match "\.bicep"
        }
    }
}
