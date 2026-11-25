# Windows-only helper validation; no Vivado, Git or RTL operations.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try {
    foreach ($script in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
        $tokens = $null; $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
        if (@($parseErrors).Count -ne 0) { throw "PowerShell syntax error in $($script.Name): $parseErrors" }
    }
    $testRoot = Join-Path $env:TEMP ('pq_wp0_selfcheck_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $helper = Join-Path $PSScriptRoot 'wp0_support.ps1'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $sample = Join-Path $testRoot 'sample.txt'
    [IO.File]::WriteAllText($sample,'WP0_SELF_CHECK_ONLY',$utf8)
    $actual = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Mode Hash -Path $sample
    if ($LASTEXITCODE -ne 0 -or $actual -ne (Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash) {
        throw 'SHA256 helper check failed.'
    }
    $paths = Join-Path $testRoot 'paths.txt'
    $manifest = Join-Path $testRoot 'manifest.tsv'
    [IO.File]::WriteAllText($paths,($sample + "`n"),$utf8)
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Mode Manifest -InputList $paths -OutputPath $manifest
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Manifest helper check failed.' }
    foreach ($case in @('pass','exit7','timeout')) {
        $bat = Join-Path $testRoot ($case + '.bat')
        switch ($case) {
            'pass' { $body = "@echo off`r`necho WP0_DUMMY_OK`r`necho WP0_DUMMY_STDERR 1>&2`r`nexit /b 0`r`n" }
            'exit7' { $body = "@echo off`r`nexit /b 7`r`n" }
            'timeout' { $body = "@echo off`r`nping.exe -n 6 127.0.0.1 >nul`r`nexit /b 0`r`n" }
        }
        [IO.File]::WriteAllText($bat,$body,$utf8)
        $prefix = Join-Path $testRoot $case
        $limit = if ($case -eq 'timeout') { 1 } else { 10 }
        # Failures are intentional here. Capture child stderr without turning it
        # into a parent terminating NativeCommandError under Windows PowerShell.
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Mode RunBat -Path $bat -WorkingDirectory $testRoot -LogPrefix $prefix -TimeoutSeconds $limit 2> ($prefix + '.helper_stderr.txt')
        $code = $LASTEXITCODE
        $ErrorActionPreference = $savedPreference
        $statusPath = $prefix + '.status.json'
        if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) { throw "Missing $case process status." }
        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        if ($case -eq 'pass' -and ($code -ne 0 -or $status.exitCode -ne 0 -or $status.timedOut)) { throw 'Successful-process check failed.' }
        if ($case -eq 'exit7' -and ($code -eq 0 -or $status.exitCode -ne 7 -or $status.timedOut)) { throw 'Nonzero-exit rejection check failed.' }
        if ($case -eq 'timeout' -and ($code -eq 0 -or -not $status.timedOut)) { throw 'Wall-timeout rejection check failed.' }
    }
    Write-Output 'WP0_HELPER_SELF_CHECK=PASS (syntax, SHA256, manifest, process success/failure/timeout)'
    Write-Output "SELF_CHECK_EVIDENCE=$testRoot"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.ToString())
    exit 1
}
