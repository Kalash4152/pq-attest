@echo off
call "C:/xilinx_vivado/Vivado/2024.1/bin/xsim.bat" n81 -tclbatch sim.tcl -log simulate.log
exit /b %errorlevel%
