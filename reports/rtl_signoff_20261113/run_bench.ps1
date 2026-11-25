param([string]$TB = 'tb_merged_closure')
# Fresh, out-of-tree XSim run of the merged closure bench on the current sources (audit, 13 Nov 2026). Writes only here.
$ErrorActionPreference = 'Continue'
$R = 'C:\vivado_verilog_proj\NOC_PQATTEST'; $B = 'C:\xilinx_vivado\Vivado\2024.1\bin'
$W = Join-Path $PSScriptRoot $TB; if (Test-Path $W) { Remove-Item -Recurse -Force $W }; New-Item -ItemType Directory $W | Out-Null; Set-Location $W
$line = (Select-String -Path "$R\scripts\merged_bitstream_sources.tcl" -Pattern 'sources \{').Line
$src = ($line -replace '.*sources \{', '' -replace '\}.*', '') -split ' ' | Where-Object { $_ } | ForEach-Object { Join-Path $R $_ }
Copy-Item "$R\sw\riscv\demo_fw_v2.hex" $W
$sv = $src | Where-Object { $_ -like '*.sv' }; $v = $src | Where-Object { $_ -like '*.v' }
$defs = @('-d', 'PQ_MAC_ON', '-d', '"CPU_TILE_MODULE=cpu_tile_noc"', '-d', 'REAL_CPU_TILE')
$inc = @('-i', "$R\vectors", '-i', "$R\sim_riscv\include")
"START $(Get-Date -Format s)"; "SOURCES $($src.Count) + $TB.sv"
& "$B\xvlog.bat" --relax @defs @inc $v 2>&1 | Out-File out_xvlog_v.txt
& "$B\xvlog.bat" --relax --sv @defs @inc $sv "$R\rtl\dual_lane\merged\$TB.sv" 2>&1 | Out-File out_xvlog_sv.txt
"XVLOG errors: " + (Select-String -Path out_xvlog_v.txt, out_xvlog_sv.txt -Pattern '^ERROR').Count + "  warnings: " + (Select-String -Path out_xvlog_v.txt, out_xvlog_sv.txt -Pattern '^WARNING').Count
& "$B\xelab.bat" $TB -s sim -timescale 1ns/1ps -relax --standalone 2>&1 | Out-File out_xelab.txt
"XELAB errors: " + (Select-String -Path out_xelab.txt -Pattern '^ERROR').Count + "  warnings: " + (Select-String -Path out_xelab.txt -Pattern '^WARNING').Count
& (Join-Path $PSScriptRoot 'run_ax.ps1') -TB $TB
Select-String -Path out_xsim.txt -Pattern 'CHECKS|ERRORS|RESULT|TB_TIMEOUT|FAIL|PASS ' | Select-Object -Last 30 | ForEach-Object { $_.Line }
"END $(Get-Date -Format s)"




