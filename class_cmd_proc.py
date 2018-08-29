#!python3
###############################################################################
# Source file : class_cmd_proc.py
# Language    : Python 3.3 or Python 3.5
# Author      : Kevin Hubbard
# Description : Process bd_shell commands
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
# -----------------------------------------------------------------------------
# History :
#   08.28.2018 : khubbard : Created
###############################################################################
import sys;
from common_functions import file2list;
from common_functions import list2file;


class cmd_proc:
  def __init__ ( self, bd, prom, var_dict ):
    self.bd          = bd;
    self.prom        = prom;
    self.cmd_history = [];
    self.var_dict    = var_dict;
    return;

  def proc( self, cmd_str ):
    rts = [];
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    cmd_txt = words[0];

    # Command History stuff
    if ( cmd_str != "" and cmd_str[0] != "!" ):
      self.cmd_history += [ cmd_str ];

    # Check to see if this is a history command ( again, may want to replace ).
    if ( cmd_txt == "h" or cmd_txt == "history" ):
      rts = ["%d %s" % (i+1,str) for (i,str) in enumerate(self.cmd_history)];# 
      return rts;
    if ( cmd_txt == "!!" or cmd_txt[0] == "!" ):
      if ( cmd_txt == "!!" ):
        cmd_str = self.cmd_history[-1];
      else:
        cmd_str = self.cmd_history[int(cmd_txt[1:],10)-1];
      words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
      cmd_txt = words[0];

    cmd_str = cmd_str.replace("=", " = ");

    # Check for "> filename" or ">> filename"
    pipe_file = None; cat_file = None;
    if ( ">" in cmd_str and ">>" not in cmd_str ):
      cmd_str = cmd_str.replace(">", " > ");
      words = " ".join(cmd_str.split()).split('>') + [None] * 4;
      cmd_str = words[0];
      pipe_file = words[1];
      pipe_file = pipe_file.replace(" ", "");
    elif ( ">>" in cmd_str ):
      cmd_str = cmd_str.replace(">>", " >> ");
      words = " ".join(cmd_str.split()).split('>>') + [None] * 4;
      cmd_str = words[0];
      cat_file = words[1];
      cat_file = cat_file.replace(" ", "");

    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    cmd_txt = words[0];

    # Check to see if this is a variable command 1st as may want to replace
    if ( words[1] == "=" ):
      self.var_dict[ words[0] ] = words[2];
      # convert "mesa_subslot = e" to command "mesa_subslot e"
      if ( words[0][0:5] == "mesa_" ):
        cmd_str = cmd_str.replace("=","");
        words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
        cmd_txt = words[0];
    elif ( cmd_txt == "print" ):
      rts = print("%s" % self.var_dict[ words[1] ]);
    elif ( cmd_txt == "env" ):
      for key in self.var_dict:
        rts += ["%-16s : %s" % ( key, self.var_dict[key] ) ];
    else:
      # If any variables are in the command line, replace key with value
      for key in self.var_dict:
        cmd_str = cmd_str.replace(key,self.var_dict[key]);
      words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
      cmd_txt = words[0];


    if ( cmd_txt == "source" ):
      if ( os.path.exists( words[1]) ):
        cmd_list = file2list( words[1]);
        for cmd_str in cmd_list:
          rts1 = self.proc( cmd_str );
          if ( rts1 != None ):
            rts += rts1;

    # Shell Commands that Mimic UNIX shells
    if ( cmd_txt == "h" or cmd_txt == "?" or cmd_txt == "help" ):
      rts = self.cmd_help();
    elif ( cmd_txt == "q" or cmd_txt == "quit" ):
      sys.exit();
    elif ( cmd_txt == "vi" ):
      rts = self.cmd_vi( cmd_str );
    elif ( cmd_txt == "more" ):
      rts = self.cmd_more( cmd_str );
    elif ( cmd_txt == "ls" ):
      rts = self.cmd_ls( cmd_str );
    elif ( cmd_txt[0:5] == "sleep" ):
      rts = self.cmd_sleep( cmd_str );

    # PROM Commands
    elif ( cmd_txt == "prom_dump" ):
      rts = self.cmd_prom_dump( cmd_str );
    elif ( cmd_txt == "prom_load" ):
      rts = self.cmd_prom_load( cmd_str );
    elif ( cmd_txt == "prom_root" ):
      rts = self.cmd_prom_root();
    elif ( cmd_txt == "prom_id" ):
      rts = self.cmd_prom_id( cmd_str );

    # MesaBus Commands
    elif ( cmd_txt == "mesa_slot" ):
      if hasattr( self.bd, 'slot'):
        self.bd.slot = int( words[1], 16 );       # Local Serial Port
      else:
        self.bd.set_slot( int( words[1], 16 ));   # TCP to bd_server
    elif ( cmd_txt == "mesa_subslot" ):
      if hasattr( self.bd, 'subslot'):
        self.bd.subslot = int( words[1], 16 );    # Local Serial Port
      else:
        self.bd.set_subslot( int( words[1], 16 ));# TCP to bd_server

    # LocalBus Commands
    if ( cmd_txt == "r" or cmd_txt == "read" ):
      rts = self.cmd_read( cmd_str );
    elif ( cmd_txt == "w" or cmd_txt == "write" ):
      rts = self.cmd_write( cmd_str );

    # Send results to a file for ">" and ">>" piping
    if ( pipe_file != None ):
      list2file( pipe_file, rts );
      rts = [];
    if ( cat_file != None ):
      list2file( cat_file, rts, concat = True );
      rts = [];

    return rts;


  ##################################
  # Shell Stuff
  def cmd_help( self ):
    vers = "2018.08.27";
    r = [];
    r+=["###################################################################"];
    r+=["# bd_shell "+vers+" by Kevin M. Hubbard @ Black Mesa Labs. GPLv3"];
    r+=["# Hardware Local Bus Access commands                               "];
    r+=["#  r addr              : Read from addr                            "];
    r+=["#  r addr num_dwords   : Read num_dwords starting at addr          "];
    r+=["#  w addr data         : Write data to addr                        "];
    r+=["#  w addr data data    : Write multiple data to addr               "];
    r+=["# PROM Access commands                                             "];
    r+=["#  prom_root           : Unlock slot-0 if locked                   "];
    r+=["#  prom_dump addr      : Dump sector at addr                       "];
    r+=["#  prom_load file addr : Load PROM from top.bin file to addr       "];
    r+=["#                        Note: addr may also be slot0 or slot1     "];
    r+=["# Mesa Bus Access commands                                         "];
    r+=["#  mesa_slot = n       : Assign mesa_slot to n                     "];
    r+=["#  mesa_subslot = n    : Assign mesa_subslot to n                  "];
    r+=["# File commands                                                    "];
    r+=["#  source file         : Source a bd_shell script                  "];
    r+=["# Shell commands                                                   "];
    r+=["#  env                 : List all variables                        "];
    r+=["#  foo = bar           : Assign value bar to variable foo          "];
    r+=["#  print foo           : Display value of variable foo             "];
    r+=["#  sleep n             : Pause for n seconds                       "];
    r+=["#  sleep_ms n          : Pause for n milliseconds                  "];
    r+=["#  more filename       : Display contents of filename              "];
    r+=["#  vi filename         : Edit filename with default editor         "];
    r+=["#  > filename          : Pipe a command result to filename         "];
    r+=["#  >> filename         : Concat a command result to filename       "];
    r+=["#  ? or help           : Display this help screen                  "];
    r+=["#  quit                : Exit bd_shell                             "];
    r+=["###################################################################"];
    return r;

  def cmd_vi( self, cmd_str ):
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    import os;
    os.system( words[1] );# Note, this is blocking. Works on Windows only
    rts = [];
    return rts;

  def cmd_more( self, cmd_str ):
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    rts = file2list( words[1] );
    return rts;

  def cmd_ls( self, cmd_str ):
    import os;
    rts = [];
    for ( root, dirs, files ) in os.walk("."):
      rts += dirs;
      rts += files;
    return rts;

  def cmd_sleep( bd, prom, cmd_str ):
    rts = [];
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    dur = int(words[1],16);
    if ( words[0] == "sleep_ms" ):
      dur = dur / 1000.0;
    sleep( dur );
    return rts;


  ##################################
  # PROM Stuff
  def cmd_prom_id( self, cmd_str ):
    rts = [];
    (vendor_id, prom_size_mb ) = self.prom.prom_id();
    timestamp = self.prom.prom_timestamp();
    slot_size = self.prom.prom_slotsize();
    import time;
    means = time.ctime(timestamp)

    rts += [ ("Manufacturer: %s" % vendor_id    ) ];
    rts += [ ("Size: %d Mb"      % prom_size_mb ) ];
    rts += [ ("Slot_Size: %08x"  % slot_size    ) ];
    rts += [ ("Timestamp: %08x : %s " % (timestamp,means) ) ];
    return rts;

  def cmd_prom_dump( self, cmd_str ):
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    addr = int(words[1],16);
    rts = self.prom.prom_dump( addr = addr );
    txt_rts = [ "%08x" % each for each in rts ];# list comprehension
    return txt_rts;

  # "prom_load top.bin slot1" or "prom_load top.bin 00200000"
  def cmd_prom_load( self, cmd_str ):
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    if ( words[2][0:4] == "slot" ):
      slot_size = self.prom.prom_slotsize();
      addr = slot_size * int(words[2][4], 10 );
    else:
      addr = int( words[2], 16 );
    bitstream = file2list( words[1], binary = True );
    print("Loading %s to address %08x" % ( words[1], addr ) );
    rts = self.prom.prom_load( addr, bitstream );
    return rts;

  def cmd_prom_root( ):
    rts = self.prom.prom_root();
    return rts;


  ##################################
  # LocalBus Stuff
  def cmd_read( self, cmd_str ):
    rts = [];
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    addr = int(words[1],16);
    num_dwords = words[2];
    if ( num_dwords == None ):
      num_dwords = 1;
    else:
      num_dwords = int( num_dwords, 16 );
    rts = self.bd.rd( addr, num_dwords );
    txt_rts = [ "%08x" % each for each in rts ];# list comprehension
    return txt_rts;

  def cmd_write( self, cmd_str ):
    rts = [];
    words = " ".join(cmd_str.split()).split(' ') + [None] * 4;
    addr = int(words[1],16);
    data_list = [ int( each,16) for each in filter(None,words[2:]) ];
    rts = self.bd.wr( addr, data_list );
    return rts;

# EOF
