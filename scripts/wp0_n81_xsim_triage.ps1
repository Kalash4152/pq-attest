# WP-0 N-8.1 XSim crash triage. READ-ONLY on RTL, TB, scripts and the original
# evidence: it COPIES the preserved snapshot into logs\wp0_triage_<ts>\ and runs
# xsim there. Writes only inside that new folder.
#
# Question it answers: tb_ni_n81 finished 115/0 PASS, then xsim.exe died with
# EXCEPTION_ACCESS_VIOLATION at '## quit' (exit 1). Which launch ingredient
# triggers the teardown crash, and is it deterministic?
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Root = 'C:\vivado_verilog_proj\NOC_PQATTEST'
$Viv  = if ($env:XILINX_VIVADO) { $env:XILINX_VIVADO } else { 'C:\xilinx_vivado\Vivado\2024.1' }
$Bin  = Join-Path $Viv 'bin'
if (-not (Test-Path -LiteralPath (Join-Path $Bin 'xsim.bat'))) { throw "xsim.bat not found under $Bin" }
$env:PATH = "$Bin;$env:PATH"

$Run = Get-ChildItem -LiteralPath "$Root\logs" -Directory -Filter 'wp0_n81_*' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Src = Join-Path $Run.FullName 'n81_ni_m0w16\generated'
if (-not (Test-Path -LiteralPath (Join-Path $Src 'xsim.dir\tb_ni_n81_behav'))) { throw "No compiled snapshot in $Src" }

$Out = Join-Path $Root ('logs\wp0_triage_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Ws  = Join-Path $Out 'ws'
New-Item -ItemType Directory -Path $Ws | Out-Null
Copy-Item -Path (Join-Path $Src 'xsim.dir'), (Join-Path $Src 'xsim.ini'), (Join-Path $Src 'protoinst_files') -Destination $Ws -Recurse
Get-ChildItem -LiteralPath $Ws -Recurse -Filter 'hs_err*' | Remove-Item -Force

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Ws 'rq.tcl'), "run 25ms`nquit`n", $utf8)   # harness batch, exact
[IO.File]::WriteAllText((Join-Path $Ws 'r.tcl'),  "run 25ms`n",        $utf8)   # no explicit quit

$Key = '-key {Behavioral:sim_1:Functional:tb_ni_n81}'
$Pi  = '-protoinst "protoinst_files/design_1.protoinst"'
$Variants = [ordered]@{
  'V1a_exact'         = "$Key -tclbatch rq.tcl $Pi"
  'V1b_exact_repeat'  = "$Key -tclbatch rq.tcl $Pi"
  'V2_no_protoinst'   = "-tclbatch rq.tcl"
  # V3 (tclbatch without quit) removed: xsim waits at its Tcl prompt forever.
  'V4_runall_R'       = "-R"
}

$rows = @()
foreach ($name in $Variants.Keys) {
  Get-ChildItem -LiteralPath $Ws -Filter 'hs_err*' | Remove-Item -Force
  $log = "$name.log"
  $cmd = "call xsim tb_ni_n81_behav $($Variants[$name]) -wdb $name.wdb -log $log"
  $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /s /c `"$cmd`"" -WorkingDirectory $Ws `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Out "$name.stdout.txt") `
        -RedirectStandardError (Join-Path $Out "$name.stderr.txt")
  $text  = if (Test-Path (Join-Path $Ws $log)) { Get-Content -Raw (Join-Path $Ws $log) } else { '' }
  $text += Get-Content -Raw (Join-Path $Out "$name.stdout.txt")
  $hs    = @(Get-ChildItem -LiteralPath $Ws -Filter 'hs_err*.log').Count -gt 0
  if ($hs) { $d = New-Item -ItemType Directory -Path (Join-Path $Out "$name.hs_err"); Get-ChildItem -LiteralPath $Ws -Filter 'hs_err*' | Move-Item -Destination $d.FullName }
  $rows += [pscustomobject]@{
    variant = $name; exit = $p.ExitCode; crash = ($hs -or $text -match 'EXCEPTION_ACCESS_VIOLATION')
    checks  = if ($text -match 'CHECKS : (\d+)') { $Matches[1] } else { '-' }
    errors  = if ($text -match 'ERRORS : (\d+)') { $Matches[1] } else { '-' }
    result  = if ($text -match 'RESULT : (\w+)') { $Matches[1] } else { '-' }
  }
}
$rows | Format-Table -AutoSize | Out-String | Tee-Object -FilePath (Join-Path $Out 'triage_summary.txt')
"TRIAGE_DIR=$Out"
