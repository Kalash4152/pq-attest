param([Parameter(Mandatory)][string]$ReplayRoot)

$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $ReplayRoot
try {
    $identity = Get-Content -LiteralPath 'REPLAY_IDENTITY.json' -Raw | ConvertFrom-Json
    $head = git rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $identity.commit -ne $head) { throw 'Replay commit mismatch.' }
    python -E scripts/dual_lane.py run --select I-T1
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
