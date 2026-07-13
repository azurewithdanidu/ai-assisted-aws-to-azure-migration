#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for verify-security.ps1 — static analysis only (no Azure calls).
#>
Describe "verify-security.ps1" {
    $Script = "$PSScriptRoot/../../skills/shared/scripts/verify-security.ps1"

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

    Context "Security checks coverage" {
        $content = Get-Content $Script -Raw

        It "should check publicNetworkAccess on Storage" {
            $content | Should -Match "publicNetworkAccess"
        }

        It "should check allowBlobPublicAccess" {
            $content | Should -Match "allowBlobPublicAccess"
        }

        It "should check Key Vault softDelete" {
            $content | Should -Match "enableSoftDelete"
        }

        It "should check Key Vault purgeProtection" {
            $content | Should -Match "enablePurgeProtection"
        }

        It "should check Function App httpsOnly" {
            $content | Should -Match "httpsOnly"
        }

        It "should check TLS version" {
            $content | Should -Match "(minTlsVersion|tls)"
        }
    }

    Context "Output report" {
        It "should write a security report file" {
            $content = Get-Content $Script -Raw
            $content | Should -Match "security-report"
        }
    }

    Context "Required parameters" {
        foreach ($param in @("ResourceGroup")) {
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
}
