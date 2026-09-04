$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'Install-Office.ps1'
$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
Copy-Item -LiteralPath $source -Destination (Join-Path $PSScriptRoot 'public/o') -Force
Write-Output 'Installer validated and copied to public/o.'
