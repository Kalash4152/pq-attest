param([string]$TB)
# Run an already elaborated bench as a standalone XSim executable (no front-end socket).
$W = Join-Path $PSScriptRoot $TB
$V = 'C:\xilinx_vivado\Vivado\2024.1'
$env:PATH = "$env:PATH;$V\lib\win64.o;$V\lib\win64.o\Default;$V\tps\mingw\6.2.0\win64.o\nt\x86_64-w64-mingw32\lib"
New-Item -ItemType File -Force "$W\empty_stdin.txt" | Out-Null
"START $TB $(Get-Date -Format s)"
$p = Start-Process -FilePath "$W\xsim.dir\sim\axsim.exe" -WorkingDirectory $W -NoNewWindow -PassThru -Wait `
  -RedirectStandardInput "$W\empty_stdin.txt" -RedirectStandardOutput "$W\out_xsim.txt" -RedirectStandardError "$W\err_xsim.txt"
"AXSIM_EXIT $($p.ExitCode)"
Select-String -Path "$W\out_xsim.txt", "$W\err_xsim.txt" -Pattern 'CHECKS|ERRORS|RESULT|TB_TIMEOUT|\[FAIL\]|\[PASS\]|FATAL|ERROR' | ForEach-Object { $_.Line }
"END $(Get-Date -Format s)"
