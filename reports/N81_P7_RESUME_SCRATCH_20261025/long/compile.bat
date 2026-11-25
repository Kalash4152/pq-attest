@echo off
call "C:/xilinx_vivado/Vivado/2024.1/bin/xvlog.bat" --relax -d PQ_MAC_ON -prj sources.prj -log xvlog.log
exit /b %errorlevel%
