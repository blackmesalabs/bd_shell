"Backdoor Shell" a UNIX like shell for writing and reading 32bit registers in a 
FPGA/ASIC. Typically the physical interface is a 1 Mbps 3-wire UART connectioni
using a $20 FTDI TTL-232R-3V3 cable, but other interfaces such as PCIe are also
supported. A TCP server application bd_server.py may be used to communicate to
the hardware allowing multiple clients such as bd_shell and sump2 to access
simultaneously over a single physical connection.

The original bd_shell was written in Windows Powershell and may be optionally
"compiled" into a .NET exe file. This Powershell version has been ported to 
Python3 so that it may run on non-Windows platforms and also be easily upgraded
and expanded by adding custom user add on modules written in Python.


README.md               : This file
bd_shell.py             : Top level Python3 script for Command Line.
bd_shell.ini            : Configuration file for bd_shell.py
class_cmd_proc.py       : User Text Command Processing 
class_lb_link.py        : Access to LocalBus over MesaBus over serial
class_ft600_usb_link.py : Access to serial over USB3 FT600 type connection
class_uart_usb_link.py  : Access to serial over USB COM type connection
class_mesa_bus.py       : Access to MesaBus over serial
class_lb_tcp_link.py    : Access to LocalBus over TCP link to bd_server.py
class_spi_prom.py       : Access to spi_prom.v over LocalBus
common_functions.py     : Low Level File Input and Output functions

bd_shell.ps1            : Deprecated .NET PowerShell version of bd_shell. 

bd_server.py            : TCP Server for sharing hardware with multiple clients
