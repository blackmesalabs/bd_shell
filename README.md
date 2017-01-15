# bd_shell
"Backdoor Shell" a UNIX like shell for writing and reading 32bit registers in a FPGA/ASIC

bd_shell is written in Windows Powershell and may be optionally "compiled" into a .NET exe file.

It interfaces to hardware either directly over FTDI USB ( Poke or Mesa Protocol ) or optionally

interfaces using TCP/IP sockets to bd_server.py which then interfaces to the hardware.

Using bd_server.py has the advantage of supporting multiple client applications access the

hardware simultaneously.


