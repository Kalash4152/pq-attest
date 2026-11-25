param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Hash','Manifest','Baseline','RunBat')][string]$Mode,
    [string]$Path,
    [string]$InputList,
    [string]$OutputPath,
    [string]$ProjectRoot,
    [string]$WorkingDirectory,
    [string]$LogPrefix,
    [ValidateRange(1,7200)][int]$TimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8([string]$File, [string]$Text) {
    [IO.File]::WriteAllText($File, $Text, $utf8)
}
function Get-Manifest([string[]]$Files) {
    $rows = foreach ($file in ($Files | Sort-Object -Unique)) {
        if ($file -match "[\r\n\t]") { throw 'A source path contains a control character.' }
        $item = Get-Item -LiteralPath $file
        if ($item.PSIsContainer) { throw "Expected a file: $file" }
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "${hash}`t$($item.Length)`t$($item.FullName)"
    }
    return (($rows -join "`n") + "`n")
}
function Git-Text([string]$Root, [string[]]$GitArgs) {
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $text = & git -C $Root @GitArgs 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') failed: $text" }
    return (($text | ForEach-Object { "$_" }) -join "`n")
}
try {
    switch ($Mode) {
        'Hash' {
            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        'Manifest' {
            $files = [IO.File]::ReadAllLines($InputList) | Where-Object { $_.Length -gt 0 }
            if (@($files).Count -eq 0) { throw 'Empty manifest input.' }
            Write-Utf8 $OutputPath (Get-Manifest $files)
        }
        'Baseline' {
            $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
            $xpr = Join-Path $root 'NOC_PQATTEST.xpr'
            $router = Join-Path $root 'NOC_PQATTEST.srcs\sources_1\new\noc_router.sv'
            foreach ($required in @($xpr,$router)) {
                if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing $required" }
            }
            $head = Git-Text $root @('rev-parse','HEAD')
            $branch = Git-Text $root @('branch','--show-current')
            # Capture status before creating the evidence directory.
            $status = Git-Text $root @('status','--porcelain=v1','--untracked-files=all')
            $log = Git-Text $root @('log','-12','--date=iso-strict','--format=%H %ad %s')
            $diff = Git-Text $root @('diff','--','NOC_PQATTEST.xpr')
            $id = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
            $out = Join-Path $root "logs\wp0_baseline_$id"
            New-Item -ItemType Directory -Path $out | Out-Null
            $files = @($xpr)
            foreach ($dir in @('NOC_PQATTEST.srcs\sources_1\new','NOC_PQATTEST.srcs\sim_1\new','scripts','synth','docs\decisions')) {
                $full = Join-Path $root $dir
                if (Test-Path -LiteralPath $full -PathType Container) {
                    $files += Get-ChildItem -LiteralPath $full -Recurse -File |
                        Where-Object { $_.Extension -in @('.sv','.svh','.v','.vh','.tcl','.ps1','.xdc','.md') } |
                        ForEach-Object { $_.FullName }
                }
            }
            $statusDoc = Join-Path $root 'docs\STATUS.md'
            if (Test-Path -LiteralPath $statusDoc -PathType Leaf) { $files += $statusDoc }
            Write-Utf8 (Join-Path $out 'sha256.tsv') (Get-Manifest $files)
            Write-Utf8 (Join-Path $out 'git_status.txt') ($status + "`n")
            Write-Utf8 (Join-Path $out 'git_log.txt') ($log + "`n")
            Write-Utf8 (Join-Path $out 'xpr.diff') ($diff + "`n")
            Write-Utf8 (Join-Path $out 'identity.txt') "UTC=$([DateTime]::UtcNow.ToString('o'))`nROOT=$root`nHEAD=$head`nBRANCH=$branch`nPowerShell=$($PSVersionTable.PSVersion)`n"
            $backup = Join-Path $out 'backup'
            New-Item -ItemType Directory -Path $backup | Out-Null
            Copy-Item -LiteralPath $xpr -Destination $backup
            foreach ($script in @('n81_xsim.tcl','n6_mutation.tcl','wp0_common.tcl','wp0_support.ps1','capture_baseline.ps1','verify_wp0.ps1')) {
                $old = Join-Path $root "scripts\$script"
                if (Test-Path -LiteralPath $old -PathType Leaf) { Copy-Item -LiteralPath $old -Destination $backup }
            }
            Write-Output "BASELINE_SAVED=$out"
            Write-Output "HEAD=$head"
        }
        'RunBat' {
            $bat = (Resolve-Path -LiteralPath $Path).Path
            $cwd = (Resolve-Path -LiteralPath $WorkingDirectory).Path
            if ([IO.Path]::GetExtension($bat) -ne '.bat') { throw 'RunBat accepts a generated .bat only.' }
            if ([IO.Path]::GetDirectoryName($bat) -ne $cwd) { throw 'Batch file must be in its run directory.' }
            if ($bat -match '[\r\n"%!&^|<>]') { throw 'Unsupported cmd.exe metacharacter in batch path.' }
            if ($env:XILINX_VIVADO) {
                $bin = Join-Path $env:XILINX_VIVADO 'bin'
                if (Test-Path -LiteralPath $bin -PathType Container) { $env:PATH = "$bin;$env:PATH" }
            }
            $start = [DateTime]::UtcNow
            $p = New-Object Diagnostics.Process
            $p.StartInfo.FileName = $env:ComSpec
            $p.StartInfo.Arguments = '/d /s /c ""' + $bat + '""'
            $p.StartInfo.WorkingDirectory = $cwd
            $p.StartInfo.UseShellExecute = $false
            $p.StartInfo.CreateNoWindow = $true
            $p.StartInfo.RedirectStandardOutput = $true
            $p.StartInfo.RedirectStandardError = $true
            $timedOut = $false
            $started = $false
            $exitCode = -1
            try {
                $started = $p.Start()
                if (-not $started) { throw 'Process did not start.' }
                $stdoutTask = $p.StandardOutput.ReadToEndAsync()
                $stderrTask = $p.StandardError.ReadToEndAsync()
                if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
                    $timedOut = $true
                    & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
                    if (-not $p.WaitForExit(10000)) { throw 'Timed-out job could not be terminated.' }
                }
                $p.WaitForExit()
                $exitCode = $p.ExitCode
                if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask),10000)) {
                    throw 'Process exited but redirected output did not close; INVALID.'
                }
                Write-Utf8 ($LogPrefix + '.stdout.log') $stdoutTask.Result
                Write-Utf8 ($LogPrefix + '.stderr.log') $stderrTask.Result
            } finally {
                if ($started -and -not $p.HasExited) {
                    & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
                    $p.WaitForExit(10000) | Out-Null
                }
                $record = [ordered]@{bat=$bat; startUTC=$start.ToString('o'); endUTC=[DateTime]::UtcNow.ToString('o'); exitCode=$exitCode; timedOut=$timedOut; timeoutSeconds=$TimeoutSeconds}
                Write-Utf8 ($LogPrefix + '.status.json') ($record | ConvertTo-Json)
                $p.Dispose()
            }
            if ($timedOut) { throw "WALL_TIMEOUT: $bat" }
            if ($exitCode -ne 0) { throw "PROCESS_EXIT_$($exitCode): $bat" }
            Write-Output 'PROCESS_OK'
        }
    }
} catch {
    [Console]::Error.WriteLine($_.ToString())
    exit 1
}
