param([string]$ProjectRoot = 'C:\vivado_verilog_proj\NOC_PQATTEST')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'wp0_support.ps1') -Mode Baseline -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
