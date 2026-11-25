@echo off
call "C:/xilinx_vivado/Vivado/2024.1/bin/xelab.bat" --incr --relax --debug typical --mt 2 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip --snapshot n81 xil_defaultlib.tb_noc_n81_p7 xil_defaultlib.glbl -log xelab.log
exit /b %errorlevel%
