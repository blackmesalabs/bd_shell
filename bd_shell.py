#!python3
###############################################################################
# Source file : bd_shell.py    
# Language    : Python 3.3 or Python 3.5
# Author      : Kevin Hubbard    
# Description : Backdoor Shell, a UNIX shell like interface for writing and
#               reading FPGA and ASIC registers sitting on a 32bit Local Bus.
# License     : GPLv3
#      This program is free software: you can redistribute it and/or modify
#      it under the terms of the GNU General Public License as published by
#      the Free Software Foundation, either version 3 of the License, or
#      (at your option) any later version.
#
#      This program is distributed in the hope that it will be useful,
#      but WITHOUT ANY WARRANTY; without even the implied warranty of
#      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#      GNU General Public License for more details.
#
#      You should have received a copy of the GNU General Public License
#      along with this program.  If not, see <http://www.gnu.org/licenses/>.
#                                                               
# PySerial for Python3 from:
#   https://pypi.python.org/pypi/pyserial/
# -----------------------------------------------------------------------------
# History :
#   01.01.2018 : khubbard : Created. Offshoot from original .NET Powershell 
# TODO: Need to figure out clean way to get slot and subslot working over TCP
###############################################################################
import sys;
import select;
import socket;
import time;
import os;
import random;
from time import sleep;

import class_cmd_proc;

import class_spi_prom;      # Access to spi_prom.v over LocalBus
import class_lb_link;       # Access to LocalBus over MesaBus over serial
import class_lb_tcp_link;   # Access to LocalBus over TCP link to bd_server.py
import class_mesa_bus;      # Access to MesaBus over serial
import class_uart_usb_link; # Access to serial over USB COM type connection
import class_ft600_usb_link;# Access to serial over USB3 FT600 type connection


def main():
  args = sys.argv + [None]*3;# args[0] is bd_shell.py
  var_dict = {};
  cmd_history = [];

  # If INI file exists, load it, otherwise create a default one and use it
  file_name = os.path.join( os.getcwd(), "bd_shell.ini");
  if ( ( os.path.exists( file_name ) ) == False ):
    ini_list =  ["bd_connection   = usb       # usb,usb3,pi_spi,tcp",
                 "bd_protocol     = mesa      # mesa,poke",
                 "tcp_port        = 21567     # 21567    ",
                 "tcp_ip_addr     = 127.0.0.1 # 127.0.0.1",
                 "usb_port        = COM4      # ie COM4",
                 "baudrate        = 921600    # ie 921600",
                 "mesa_slot       = 00        # ie 00",
                 "mesa_subslot    = 0         # ie 0",    ];
    ini_file = open ( file_name, 'w' );
    for each in ini_list:
      ini_file.write( each + "\n" );
    ini_file.close();
    
  if ( ( os.path.exists( file_name ) ) == True ):
    ini_file = open ( file_name, 'r' );
    ini_list = ini_file.readlines();
    for each in ini_list:
      words = " ".join(each.split()).split(' ') + [None] * 4;
      if ( words[1] == "=" ):
        var_dict[ words[0] ] = words[2];

  # Assign var_dict values to legacy variables. Error checking would be nice.
  bd_connection =     var_dict["bd_connection"];
  com_port      =     var_dict["usb_port"];
  baudrate      = int(var_dict["baudrate"],10);
  mesa_slot     = int(var_dict["mesa_slot"],16);
  mesa_subslot  = int(var_dict["mesa_subslot"],16);
  tcp_ip_addr   =     var_dict["tcp_ip_addr"];
  tcp_port      = int(var_dict["tcp_port"],10);
    
  if ( bd_connection == "tcp" ):
    bd  = class_lb_tcp_link.lb_tcp_link( ip = tcp_ip_addr, port = tcp_port );
  elif ( bd_connection == "usb" ):
    usb = class_uart_usb_link.uart_usb_link( port_name=com_port,
                                             baudrate=baudrate  );
    mb  = class_mesa_bus.mesa_bus( phy_link=usb );
    bd  = class_lb_link.lb_link( mesa_bus=mb, slot=mesa_slot, 
                                 subslot=mesa_subslot );
 
  prom = class_spi_prom.spi_prom( lb_link = bd );

  cmd  = class_cmd_proc.cmd_proc( bd, prom, var_dict );

  # If there is no argument, then sit in a loop CLI style 
  if ( args[1] == None ):
    cmd_str = None;
    while ( cmd_str != "" ):
      print("bd>",end="");
      cmd_str = input();
      rts = cmd.proc( cmd_str );
      if ( rts != None ):
        for each in rts:
          print("%s" % each );
    return;
  # If args[1] is a file, open it and process one line at a time
  elif ( os.path.exists( args[1] ) ):
    cmd_list = file2list( args[1] );
    for cmd_str in cmd_list: 
      rts = cmd.proc( cmd_str );
      if ( rts != None ):
        for each in rts:
          print("%s" % each );
  else:
  # If args[1] is not a file, just process the single command line args
    arg_str = filter( None, args[1:] );
    cmd_str = "";
    for each in arg_str:
      cmd_str += each + " ";
    rts = cmd.proc( cmd_str );
    if ( rts != None ):
      for each in rts:
        print("%s" % each );
  return;


###############################################################################
try:
  if __name__=='__main__': main()
except KeyboardInterrupt:
  print('Break!')
# EOF
