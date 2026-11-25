param([Parameter(Mandatory=$true)][string]$Spec)
$ErrorActionPreference = 'Stop'
$job = Get-Content -LiteralPath $Spec -Raw | ConvertFrom-Json
# Delegate native process tree supervision to the preserved, proven WP-0 helper.
# Its hidden Diagnostics.Process captures separate stdout/stderr and timeout.
& (Join-Path $PSScriptRoot 'wp0_support.ps1') -Mode RunBat -Path $job.bat `
  -WorkingDirectory $job.cwd -LogPrefix $job.logPrefix -TimeoutSeconds $job.timeout
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
