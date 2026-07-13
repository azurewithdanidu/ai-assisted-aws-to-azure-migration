#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for verify-security.ps1 — static analysis only (no Azure calls).
#>
Describe "verify-security.ps1" {
    BeforeAll {
        $script:ScriptPath = "$PSScriptRoot/../../skills/azure-security-patterns/scripts/verify-security.ps1"
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

    Context "Security checks coverage" {
        It "should check publicNetworkAccess on Storage" {
            $script:Content | Should -Match "publicNetworkAccess"
        }

        It "should check allowBlobPublicAccess" {
            $script:Content | Should -Match "allowBlobPublicAccess"
        }

        It "should check Key Vault softDelete" {
            $script:Content | Should -Match "enableSoftDelete"
        }

        It "should check Key Vault purgeProtection" {
            $script:Content | Should -Match "enablePurgeProtection"
        }

        It "should check Function App httpsOnly" {
            $script:Content | Should -Match "httpsOnly"
        }

        It "should check TLS version" {
            $script:Content | Should -Match "(minTlsVersion|tls)"
        }
    }

    Context "Output report" {
        It "should write a security report file" {
            $script:Content | Should -Match "security-report"
        }
    }

    Context "Required parameters" {
        It "should declare -ResourceGroup parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath, [ref]$null, [ref]$null)
            $params = $ast.FindAll(
                { $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
            $paramNames = $params | ForEach-Object { $_.Name.VariablePath.UserPath }
            $paramNames | Should -Contain "ResourceGroup"
        }
    }
}
