#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for validate-bicep.ps1 — static analysis only (no Azure calls).
#>
Describe "validate-bicep.ps1" {
    $Script = "$PSScriptRoot/../../skills/iac-transformation/scripts/validate-bicep.ps1"

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

    Context "Core behaviours" {
        It "should call az bicep build" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "bicep build"
        }

        It "should call az bicep restore" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "bicep restore"
        }

        It "should recurse over .bicep files" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "\.bicep"
        }
    }
}
