###############################################################################
# bd_shell.ps1 (C) Copyright 2014 Kevin M. Hubbard - All rights reserved.
#         This software is released under the GNU GPLv2 license.
# [ ChangeLog ]
# khubbard 02.28.14 : Ported from sump.ps1
# khubbard 03.10.14 : Lots of new features added.
# khubbard 03.12.14 : Fix read num_dwords offset problem.
# khubbard 03.13.14 : Create empty file if vi on new filename. diff,python
# khubbard 03.14.14 : Fixed read issues with USB interface.
#                     Fixed grep pattern being off by 1 character
#                     Fixed base_addr showing up in read output address.
#                     Fixed | grep to single read locking up.
#                     Added popup_select dialog box.         
#                     Added popup_openfile.                  
#                     Added assigning variable to command results in ()
#                     Variable replacement cleanup ( do once now )      
# khubbard 03.17.14 : Fixed 'configure' not working with USB interface.
# khubbard 03.18.14 : Fixed Win8 PowerShell3 problem with "$server:$port"
# khubbard 05.29.14 : Added timeout protection for socket_send()
# khubbard 06.02.14 : Increase socket_send() timeout from 1s to 5s.
# khubbard 06.02.14 : Added command history command.
# khubbard 06.27.14 : Added SPI PROM support
# khubbard 06.27.14 : Improved "ls" UNIX command to support wildcards
# khubbard 06.27.14 : Removed PROM Erase timeouts. Added PROM unlocking.
# khubbard 06.28.14 : Added prom_vers command for reading UNIX timestamps.
# khubbard 06.30.14 : Changed prom_boot
# khubbard 07.17.14 : Added "!!" for prom_boot to unlock Poke after reconfig.
# khubbard 07.18.14 : Added "rt" for register test and increased socket_send
#                     timeout from 5s to 10s to support new command.
# khubbard 07.22.14 : Safety check for zero length bd_shell.ini file
# khubbard 07.27.14 : Added PROM Slot feature for prom_load and prom_boot
# khubbard 08.25.14 : Added prom_root,prom_bist commands
# khubbard 09.18.14 : Replaced convert with int2hex and hex2int commands
#                     Change to popup_select to display var names not values
#                     Added unix mv command
# khubbard 10.30.14 : prom_load change to strip 1st 88 bytes for Spartan6
# khubbard 11.01.14 : Aliased uart_load to configure command 
# khubbard 01.15.15 : Adding FTDI 2XX DLL support. No configure for DLL yet.
# khubbard 01.21.15 : Adding timestamp command.
# khubbard 01.22.15 : Do a try catch for spawning python 
# khubbard 05.28.15 : Added -c command line option (non-GUI)
# khubbard 10.01.15 : Lattice support for PROM release DeepPower and prom_load
# khubbard 10.11.15 : Starting Mesa Bus support
# khubbard 10.30.15 : Send single chars instead of line for Arduino fix
# khubbard 11.16.15 : Support for new MesaBus Ro headers on readback    
# khubbard 03.18.16 : mesa_id command added
#
#
# WARNING: prom_load requires bd_server socket connection. Direct doesnt work.
###############################################################################
# This is a PowerShell script. Microsoft makes writing PowerShell scripts very
# easy - but running them extremely difficult. More details available at:
#  http://technet.microsoft.com/en-us/gg261722.aspx
# This script has been compiled into a .NET executable ( much like C# ) by 
# using the PS2EXE ( PS2EXE v0.4.0.0 http://ps2exe.codeplex.com ) script
# written by: Ingo Karstein (http://blog.karstein-consulting.com) 
# Build instructions:
#   call "callPS2EXE.bat" "bd_shell.ps1" "bd_shell.exe" -noconsole
###############################################################################
# Running as a script:
#  Right-Click and 'Run with Powershell' to Execute this Script
#  'Set-ExecutionPolicy RemoteSigned' as Admin if script won't run
###############################################################################
# WARNING : By default, all comparison operators are case-insensitive. 
# To make a comparison operator case-sensitive, precede the operator name with
# a "c". For example, the case-sensitive version of "-eq" is "-ceq"
###############################################################################
[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][Reflection.Assembly]::LoadWithPartialName("System.Drawing")
set-strictmode -version 2.0;# Forces vars to be init before use

###############################################################################
# --------------------------------------------------------------------------- #
# Window Management Library
# create_form() : Create the Windows Form with specified pulldown menu
function create_form( $obj_menu )
{
 $obj_form = new-object System.Windows.Forms.form;
 $obj_form.clientsize = new-object System.Drawing.Size(640,480);
 $obj_form.text = ("bd_shell    $vers");
#$obj_form.controls.add( $obj_menu );
#$obj_form.mainmenustrip = $obj_menu;
 $obj_form.add_formclosing( { event_close_form $obj_form } )
 $obj_form.add_shown( {$obj_form.activate()} )
 $obj_form.add_resizeend( { event_resize("") } );# Note: Called on Win Move also
 $obj_form.add_gotfocus( { event_gotfocus("") } );
 $obj_form.Location = New-Object Drawing.Point(0,0);
 $obj_form.StartPosition = "Manual"; # vs "CenterScreen"
#$obj_form.TopMost = $true;
 $obj_form_h = 800;
 $obj_form_w = 800;
#$obj_form_w = 70 * ( $obj_font.Size );# Width

 $w = (hash_get(@($var_hash,"window_width")));
 $h = (hash_get(@($var_hash,"window_height")));
 if ( $w -ne "" ) { $obj_form_w = str2int( $w ); }
 if ( $h -ne "" ) { $obj_form_h = str2int( $h ); }
 $obj_form.Size = New-Object Drawing.Point( $obj_form_w, $obj_form_h );
 return $obj_form;
}


function apply_font( $args_array )
{
 ( $font_name, $font_size ) = $args_array;
 $global:obj_font = New-Object System.Drawing.Font( $font_name, $font_size, 
                                         [System.Drawing.FontStyle]::Regular);
}

function str2int( $_ )  { return ( [convert]::toint32( $_,10) ); }

function hex2int( $_ )  
{ 
 try   { $rts = ( [convert]::toint32( $_,16) ); }
 catch { $rts = 0; }
 return $rts;
}

function int2hex( $_ )  { return ( "{0:x8}" -f $_             ); }
function int2str( $_ )  { return ( "{0:d0}" -f $_             ); }
function bin2int( $_ )  { return ( [convert]::toint32( $_,2 ) ); }

function event_gotfocus
{
  $obj_form.Opacity = 100;
}

####################################################
# Anything to Console Print also goes to log file 
function print( $_ )
{
 $print_log_en = "1";
 if ( $print_log_en -eq "1" )
 {
   Write-Host $_; 
#  $_ >> $log_file; 
 }
}# print()



####################################################
# Log stuff to a file
function log2file( $_ )
{
 $_ >> $log_file;
}# log2fil()



####################################################
# one-line status bar at the bottom of form
function create_obj_status()
{
 $private:obj  = New-Object Windows.Forms.StatusBar;
 $obj.TabStop  = $false;
 $obj.Text     = "StatusBar";
 return $obj;
}


####################################################
# Place single text line in the status bar at bottom
function status( $_ )
{
 print $_;
 $nl = [Environment]::NewLine
 $obj_rtb.AppendText( ($_ + $nl) );
 event_refresh;
}

function event_close_form($Sender,$e) { ($_).Cancel= $False; event_exit }
function event_exit        
{ 
# print ( "event_exit()" );
  $w = (int2str( $obj_form.Size.Width  ));
  $h = (int2str( $obj_form.Size.Height ));
  replace_param( @($ini_file,"window_width",  $w ));
  replace_param( @($ini_file,"window_height", $h ));
# print("Bye");
  $obj_form.Dispose();   # This will close the form window
  [Environment]::Exit(0);# This will close the console window
}


################################################################################
# Allow user to resize entire window and recalculate 
################################################################################
function event_resize( )
{
 $obj_rtb.Refresh();
 $obj_form.Refresh();
 $obj_rtb.AppendText("");
 $obj_rtb.ScrollToCaret();
 $foo = $obj_rtb.Focus();
#return;
}# event_resize()


#############################################################################
# event_refresh() : refreshes form 
function event_refresh( )
{
 $obj_form.Refresh();
}# event_refresh()


############################################################
# Configure a widget to be on a grid of 75x23 units + margin
function cfg_obj( $args_array )
{
  ( $obj, $text, $x, $y, $w, $h ) = $args_array;
  $bh = 23;
# $bw = 75;
# $bw = 50;
  $bw = 60;
  $m  = 1;

  $uh = $bh + $m;
  $uw = $bw + $m;

  $bx = $m/2 + ($uw * $x );
  $by = $m/2 + ($uh * $y );

  $bw = ( $uw * $w ) - $m;
  $bh = ( $uh * $h ) - $m;

  # Attempt to align labels with buttons by offsetting Y and making narrow
  if ( $obj.GetType() -eq [System.Windows.Forms.Label] )
  {
   $by = $by + 2;
   $bh = $bh - 3;
   $bw = $bw * 1;
  }
  $obj.Location = New-Object System.Drawing.Size($bx,$by);
  $obj.Size     = New-Object System.Drawing.Size($bw,$bh);
  $obj.TabStop  = $true;
  $obj.Text     = $text;
}# cfg_obj()
#                            End of Window Library
# --------------------------------------------------------------------------- #
###############################################################################

function create_manual( $args_array )
{
 ( $filename ) = $args_array;
 if ( Test-Path( $filename ) ) { return; }
$a = @();
$a+="                      BD_SHELL.exe for Windows                          ";
$a+=("            BD_SHELL Version "+$vers+" by "+$author);
$a+="                                                                        ";
$a+="1.0 Scope                                                               ";
$a+="    This document describes the BD_SHELL.exe executable for Windows.    ";
$a+="                                                                        ";
$a+="2.0 Software Architecture                                               ";
$a+="    BD_SHELL.exe is a Windows .NET WinForms application for:            ";
$a+="     1) Interactively reading and writing to FPGA hardware.             ";
$a+="     2) Running command scripts for accessing FPGA hardware.            ";
$a+="     3) Basic operating system file access.                             ";
$a+="    The application is written in Windows PowerShell language and       ";
$a+="    the script is then compiled into a .NET executable ( much like C# ) ";
$a+="    by using the PS2EXE ( v0.4.0.0 http://ps2exe.codeplex.com ) script  ";
$a+="    written by: Ingo Karstein (http://blog.karstein-consulting.com)     ";
$a+="    Build instructions:                                                 ";
$a+="      call 'callPS2EXE.bat' 'bd_shell.ps1' 'bd_shell.exe' -noconsole    ";
$a+="                                                                        ";
$a+="3.0 User Interface                                                      ";
$a+="    The default User Interface to BD_SHELL.exe is a resizable WinForms  ";
$a+="    form containing a WinForms RichTextBox. The UI is modeled after     ";
$a+="    the open-source GNU Bash shell used in the Linux operating system.  ";
$a+="    Commands are typed in a resizable text window at a command prompt   ";
$a+="    and the results are scrolled onto the screen. BD_SHELL may also be  ";
$a+="    optionally ran without the GUI direct from a MS-DOS command line    ";
$a+="    by using the -c argument followed by a BD_SHELL command. Example:   ";
$a+="    Example: C:\bd_shell.exe -c 'source foo.txt'                        ";
$a+="                                                                        ";
$a+="4.0 Commands                                                            ";
$a+=" 4.1 Backdoor Commands                                                  ";
$a+="     w  addr data               : Write Data to Address";
$a+="     r  addr                    : Read Address";
$a+="     bs addr data               : Bit Set";
$a+="     bc addr data               : Bit Clear";
$a+="     w  addr data data data     : Write Multiple DWORDs";
$a+="     r  addr dwords             : Read Multiple DWORDs";
$a+="     r  addr dwords >  file     : Read Multiple and dump to file";
$a+="     r  addr dwords >> file     : Read Multiple and append to file";
$a+="     rt addr iterations         : Register Test at addr for iterations";
$a+="     addr : data                : Write to Addr";
#$a+="    Loop Writes";    
#$a+="     i = 100                    : Load Loop Address with 100";    
#$a+="     4{w i AA}                  : Write AA to 100,104,108,10c";
$a+=" 4.2 FPGA Configuration Commands                                        ";
$a+="      timestamp                  : Query TIMESTAMP of FPGA design";
$a+="     UART XC3S400 Spartan3 Hubbard Board                                ";
$a+="      uart_load top.bit          : Send top.bit to Spartan3 board";
$a+="     SPI PROM Nano3 or Nano6 Boards";
$a+="      prom_id                    : Query SPI PROM ID at prom_addr";
$a+="      prom_vers                  : Query TIMESTAMP of FPGA design";
$a+="      prom_load top.bit slot     : Load PROM with top.bit to slot";
$a+="      prom_dump addr             : Dump 256 Bytes from PROM at addr";
$a+="      prom_boot slot             : Reboot (PROG_L) FPGA from PROM at slot";
$a+="      prom_root                  : Allow overwriting BootLoader";
$a+="      prom_bist                  : Issue BIST Request to FPGA";
$a+=" 4.3 Linux-ish Commands                                                 ";
$a+="     pwd                        : Display current directory path        ";
$a+="     cd  path                   : Change directory, source bd_shell.ini ";
$a+="     cp   file1 file1           : Copy file1 to file2                   ";
$a+="     mv   file1 file1           : Move file1 to file2                   ";
$a+="     diff file1 file1           : Compare file1 to file2                ";
$a+="     mkdir path                 : Make new directory path               ";
$a+="     ls                         : List Contents of current directory    ";
$a+="     vi file                    : Open file with default opener         ";
$a+="     more file                  : Display contents of file              ";
$a+=" 4.4 Shell Commands                                                     ";
$a+="     clear                      : Clear the display                     ";
$a+="     clear_vars                 : Clear vars and reload ~\bd_shell.ini  ";
$a+="     print some text            : Display some text                     ";
$a+="     var_name = value           : Assign value to variable var_name     ";
$a+="     var_name                   : Display value of var_name             ";
$a+="     env                        : list all variables                    ";
#$a+="     conv,convert               : Convert hex to int and vice versa    ";
$a+="     hex2int                    : Convert hex to int . Replaces conv    ";
$a+="     int2hex                    : Convert int to hex . Replaces conv    ";
$a+="     sleep    n                 : Sleep n seconds                       ";
$a+="     sleep_ms n                 : Sleep n msecs                         ";
$a+="     ?,h,help                   : Display help screen                   ";
$a+="     man,manual                 : Display this manual                   ";
$a+="     #                          : Comment line                          ";
$a+=" 4.5 Output Redirects                                                   ";
$a+="     > file                     : Pipe output to new file               ";
$a+="     >> file                    : Pipe output to existing file          ";
$a+="     | grep filter              : Filter output on filter string        ";
$a+="                                                                        ";
$a+="5.0 Numbers                                                             ";
$a+="    Numbers for Backdoor commands are all in hexadecimal. Zero padding  ";
$a+="    is optional and no leading 0x0 is permitted.                        ";
$a+="    The hex2int and int2hex commands may be used for type conversions.  ";
$a+="    Example:                                                            ";
$a+="     bd>bar = 100                                                       ";
$a+="     bd>foo = ( hex2int bar )                                           "; 
$a+="     bd>print foo                                                       "; 
$a+="        256                                                             "; 
$a+="                                                                        ";
$a+="6.0 Variables                                                           ";
$a+="    Variables are used for both bd_shell configuration and for address  ";
$a+="    and data in Backdoor commands. An example use for variables would   ";
$a+="    be to create a text file containing register names assigned to      ";
$a+="    their PCI address and bitfield names like this:                     ";
$a+="     fpga_int_status = 00000050                                         ";
$a+="     bit_overtemp_in    = 0800                                          ";
$a+="    A cryptic backdoor command like:                                    ";
$a+="     bd>bs 00000050 0800                                                ";
$a+="    Can then be replaced by:                                            ";
$a+="     bd>bs fpga_int_status bit_overtemp_int                             ";
$a+="    base_addr is a special variable. The value of base_addr is always   ";
$a+="    added to the address of any Backdoor command.                       ";
$a+="    Variables may also be assigned to results from commands such as:    ";
$a+="     bd>status_val = (rd fpga_int_status )                              ";
$a+="                                                                        ";
$a+="7.0 Backdoor Scripting                                                  ";
$a+="    The 'source' command supports both single level and nested scripting";
$a+="    of Backdoor commands. An example use case would be to create many   ";
$a+="    scripts containing Backdoor commands and then create a top level    ";
$a+="    script that sources selected bottom level scripts. Any line         ";
$a+="    beginning with a '#' in a script is ignored ( comment line ).       ";
$a+="    The script bd_shell.ini is auto sourced after a 'cd' command if it  ";
$a+="    exists in the new directory.                                        ";
$a+="                                                                        ";
$a+="8.0 Python Scripting                                                    ";
$a+="    BD_SHELL is designed to use Python for advanced scripting needs.    ";
$a+="    The following is a simple example of using python within BD_SHELL   ";
$a+="    to modify a RAM table by adding +1 to every location.               ";
$a+="    Example:                                                            ";
$a+="    bd>read_format = addr_data                                          ";
$a+="    bd>r 0 20 > ram_in.txt                       # Dump RAM to file     "; 
$a+="    bd>python convert.py ram_in.txt ram_out.txt  # Modify file          ";
$a+="    bd>source ram_out.txt                        # Load RAM from file   ";
$a+="    [ convert.py ]                                                      ";
$a+="      import sys;                                                       ";
$a+="      file_in   = open ( sys.argv[1] , 'rt' );                          ";
$a+="      file_out  = open ( sys.argv[2] , 'wt' );                          ";
$a+="      file_list = file_in.readlines();# Conv file to list               ";
$a+="      for line in file_list:                                            ";
$a+="      words = line.strip().split()+[None]*4;# Avoid IndexError          ";
$a+="        if ( words[0] != None ):                                        ";
$a+="          addr = words[0];                                              ";
$a+="          data = int( words[2], 16 ) + 1;                               ";
$a+="          print( addr );                                                ";
$a+="          file_out.write( addr + ' : %08x' % data + '\n' );             ";
$a+="                                                                        ";
$a+="    Using the Backdoor class in bd_client.py it is also possible to     ";
$a+="    write and read registers directly from inside Python.               ";
$a+="    Example:                                                            ";
$a+="    [ bd_client.py ]                                                    ";
$a+="    bd = Backdoor();# Establish a TCP Socket Connection to bd_server.py ";
$a+="    bd.wr( 0x0, [0x00000000] );# Write single DWORD                     ";
$a+="    bd.bs( 0x0, [0x00000001] );# BitSet DWORD                           ";
$a+="    dword_list = bd.rd( 0x0, 1 );# Read Single Dword                    ";
$a+="    print dword_list[0];                                                ";
$a+="    bd.wr( 0x0, [0x00000010,0x00000020] );# Burst Write                 ";
$a+="    dword_list = bd.rd( 0x0, 2 );# Burst Read                           ";
$a+="    for dword in dword_list:                                            ";
$a+="      print '%08x' % dword; # '00000010','00000020'                     ";
$a+="    bd.close();                                                         ";
$a+="                                                                        ";
$a+="9.0 Output Redirects                                                    ";
$a+="    Output Redirects to files and grep filter can be extremely useful.  ";
$a+="    Examples:                                                           ";
$a+="      bd>env | grep int_reg    : Find variable name containing 'int_reg'";
$a+="      bd>ls | grep foo         : Find file with 'foo' in its name       ";
$a+="      bd>r 0 10 | grep 0055    : Find 0055 in a memory read             ";
$a+="      bd>more file | grep 0055 : Find 0055 in file                      ";
$a+="                                                                        ";
$a+="10.0 Read Format                                                        ";
$a+="    The variable read_format determines Backdoor output read format.    ";
$a+="    By changing read_format, the output may either be data only or      ";
$a+="    address and data with up to 8 dwords of data per line.              ";
$a+="     read_format = data      : Output is single dword of data per line  ";
$a+="     read_format = addr_data : Output is 'addr : data' pair per line.   ";
$a+="     read_format = name_data : Output is 'name : data' pair per line.   ";
$a+="     read_format = columns   : Output is 'addr : data data data ..'     ";
$a+="    All modes except 'data' support dumping a read to a file and then   ";
$a+="    sourcing that file to write the data back into memory. This supports";
$a+="    activities like dumping a large table, editing that table with vi   ";
$a+="    and then loading that table back into memory.                       ";
$a+="                                                                        ";
$a+="11.0 Popup Dialog Boxes                                                 ";
$a+="    For advanced scripting it may be desirable to pause for human       ";
$a+="    response and to prompt for values. BD_SHELL provides two popup      ";
$a+="    dialog boxes. The return variable rts from popup_getvalue and       ";
$a+="    popup_select may be used as a filename for source or python commands";
$a+="    or it may be used as a Backdoor variable for address or data.       ";
$a+="     popup_message  message : A dialog box with message and [OK] button.";
$a+="                              to enter a variable value.                ";
$a+="                              popup_default : Default value for entry   ";
$a+="                              rts           : Response value after [OK] ";
$a+="     popup_select   items   : A dialog box with a pulldown selection of ";
$a+="                              specified items. If the variable          ";
$a+="                              popup_select_txt is set, it will be shown.";
$a+="                              The variable rts will contain the selected";
$a+="                              item after [OK] is pressed.               ";
$a+="     popup_openfile         : A file select dialog box. Result will be  ";
$a+="                              sourced or run with python.               ";
$a+="     beep                   : Makes a beep.                             ";
$a+="                                                                        ";
$a+="                                                                        ";
$a+="12.0 Hardware Interface                                                 ";
$a+="    BD_SHELL.exe communicates either to a FTDI USB connection or via    ";
$a+="    TCP Sockets to the BD_SERVER.PY Python script. The variable         ";
$a+="    bd_connection is assigned either to 'usb' or 'tcp' to select.       ";
$a+="                                                                        ";
$a+="13.0 License                                                            ";
$a+="     This software is released under the GNU GPLv2 license.             ";
$a+="     Full license is available at http://www.gnu.org/                   ";
$a+="                                                                        ";
$a+="[EOF]                                                                   ";
 if ( Test-Path $filename ) { Clear-content $filename; }
 Add-Content $filename -value $a;
}# create_manual


###############################################################################
# replace_param() : Look for param in file and replace with new value
function replace_param( $args_array )
{
 ( $file, $param, $value ) = $args_array;
 $lines = Get-Content $file;
 $new_lines = @();
 foreach ( $line in $lines )
 {
   if ( ($line.TrimStart(" ")[0] -ne "#") -and ( $line -ne "" ) )
   {
     $words = ($line -replace("\s+"," ")).split(" ");# Word split
     if ( $words[0] -eq $param ) { $line = ( $param + " = " + $value); }
   }
   $new_lines += $line;
 }
 if ( Test-Path $file ) { Clear-content $file; }
 Add-Content $file -value $new_lines;
}# replace_param()


###############################################################################
# load_ini_file() : Load var_hash from ini_file 
# Format is: var_name = var_value
function load_ini_file( $args_array )
{
  ( $filename ) = $args_array;
  $cwd_path = get-location;
  if ( $filename -and ( Test-Path( $filename )) )
  {
#   print(("load_ini_file( $filename )"));
    $ini_lines = Get-Content $filename;
    foreach ( $line in $ini_lines )
    {
      if ( $line.TrimStart(" ")[0] -ne "#" )
      {
        $line  = ($line -replace("="," = "));
        $words = ($line -replace("\s+"," ")).split(" ")+@("","","","");
        if ( $words[0] -eq "source" )
        {
         load_ini_file( @( $words[1] ) );# Read another ini file - Recursion
        }
        elseif ( $words[1] -eq "=" )
        {
         $key = $words[0];
         $val = $words[2];
#        print "hash_set() $key $val";
         # Normal is "foo=bar" but mesa_slot is an exception as there
         # may be multiples for various slots.
         if ( $key -ne "mesa_slot" )
         {
          hash_set( @( $var_hash,$key, $val  ) );
         }
         else
         {
          $words = ($val.split("#"));# Ignore comments at end of lines
          $words = ($words[0].split(","));# Parse slot,min,max
          $key = $words[0];                # Mesa Slot Number
          $val = @( $words[1],$words[2] ); # Mesa Min,Max PCI addr for Slot
          hash_set( @( $mesa_slot_hash,$key,$val ) );
          
#         foreach ($h in $mesa_slot_hash.GetEnumerator())
#         {
#          print( "$($h.Name) : $($h.Value)" );
#         }

#         foreach( $each in $words )
#         {
#          print( $each );
#         }
#         display_results( $words );
#         hash_set( @( $mesa_slot_hash,$key, $val  ) );
         }
        }
      }
    }
   set_ini_globals("");# Assign globals (argh) we need
  }
}# load_ini_file()


###############################################################################
# --------------------------------------------------------------------------- #
# Backdoor library of commands    
#  create_bd()    : Create a Backdoor ( opening USB COM Port, unlock Poke )
#  bd_cmd()       : Send a Command and wait for a response
#  bd_configure() : Send a FPGA bitstream to Spartan3 board
function create_bd( $args_array )
{
# ( $usb_port ) = $args_array;
  # [System.IO.Ports.SerialPort]::getportnames();# Displays all COM ports
  $global:bd_connection = (hash_get(@($var_hash,"bd_connection")));# 
  $global:bd_protocol   = (hash_get(@($var_hash,"bd_protocol"  )));# 

  if ( $bd_connection -eq $False )
  {
   status( "`nERROR: Invalid bd_connection : Please check bd_shell.ini file" );
   return $false;
  }

  if ( $bd_connection -eq "tcp" )
  {
   $port = [int](hash_get(@($var_hash,"tcp_port")));    # ie 21567
   $server =    (hash_get(@($var_hash,"tcp_ip_addr"))); # is "127.0.0.1"
   try
   {
    $global:socket = new-object System.Net.Sockets.TcpClient($server, $port)
    if ( $socket -eq $null )
      { print("ERROR: Can't Connect");throw("Can't Connect"); return ""; }
    $global:stream = $socket.GetStream();
    return $stream;
   }
   catch
   {
    status( "`nConnect Failed $bd_connection $server : $port" );
    return $false;
   }
  }# if ( $bd_connection -eq "tcp" )

  try
  {
   $usb_port = (hash_get(@($var_hash,"usb_port")));
   if ( $usb_port -ne "DLL" )
   {
    $baud="921600";
#   $baud="115200";# Needed for Bluetooth ?
    $port=new-Object System.IO.Ports.SerialPort($usb_port,$baud,"None","8","1");
#   $port.ReadTimeout = 1000;
    $port.ReadTimeout = 5000;
    $port.open();
    if ( $bd_protocol -eq "poke" )
     {
      $port.WriteLine("!!"); # Unlock Backdoor in case its locked
     }
    if ( $bd_protocol -eq "mesa" )
     {
      $port.WriteLine("`n"); # Mesa Autobauds to LF after reset
     }
   }
   else
   {
    if ( $dll_loaded -eq $False )
    {
     $dll_file = "FTD2XX_NET.dll"; # DLL file from FTDI
     $dll_path = join-path -path $org_path -childpath $dll_file;
#    print( "Loading $dll_path" );
     if ( Test-Path( $dll_path ) ) 
      { [void][Reflection.Assembly]::LoadFile( $dll_path ); }
     else
      { status( "`nERROR: Unable to load $dll_path" ); }
     $port = New-Object FTD2XX_NET.FTDI; 
     $num_dev = 0;
     $rts = $port.GetNumberOfDevices( [ref] $num_dev );
     if ( $rts -ne "FT_OK" ) { print("ERROR: GetNumberOfDevices() $rts"); }
     $rts = $port.OpenByIndex( 0 );# Assuming only 1 FTDI Device, Index 0
     if ( $rts -ne "FT_OK" ) { print("ERROR: OpenByIndex() $rts"); }
     $rts = $port.SetBaudRate( 921600 ); # Set Serial Baud
     if ( $rts -ne "FT_OK" ) { print("ERROR: SetBaudRate() $rts"); }
     # Set Data Characteristics 
     # use "-as" operator to cast string to type to access .NET enumerations
     $arg1 = "FTD2XX_NET.FTDI.FT_DATA_BITS.FT_BITS_8"      -as [type];
     $arg2 = "FTD2XX_NET.FTDI.FT_STOP_BITS.FT_STOP_BITS_1" -as [type];
     $arg3 = "FTD2XX_NET.FTDI.FT_PARITY.FT_PARITY_NONE"    -as [type];
     $rts = $port.SetDataCharacteristics( $arg1, $arg2, $arg3 ); 
     if ( $rts -ne "FT_OK" ) { print("ERROR: SetDataCharacteristics() $rts"); }
     $rts = $port.SetTimeouts( 5000, 0 );# ReadTimeout=5s, Write=None
     if ( $rts -ne "FT_OK" ) { print("ERROR: SetTimeouts() $rts"); }
     # Set Flow Control
     $arg1 = "FTD2XX_NET.FTDI.FT_FLOW_NONE" -as [type];
     $rts = $port.SetFlowControl( $arg1, 0,0 );
     if ( $rts -ne "FT_OK" ) { print("ERROR: SetFlowControl() $rts"); }
     $bytes_written = 0; 
     if ( $bd_protocol -eq "poke" )
     {
       $tx_str = "!!"; # Unlock Backdoor
     }
     else
     {
       $tx_str = "`n"; # Mesa autobauds to LF
     }
     $rts = $port.Write( $tx_str, $tx_str.Length, [ref] $bytes_written );
     if ( $rts -ne "FT_OK" ) { print("ERROR: Write() $rts"); }
     $global:dll_loaded = $port;
    }
    else
    {
     $port = $dll_loaded;
    }
   }
  }
  catch
  {
   status( "`nConnect Failed $usb_port" );
   return $false;
  }
 return $port;
}# create_bd()


function bd_cmd( $args_array )
{
 if ( $bd_protocol -ne "mesa" )
 {
  return bd_poke_cmd( $args_array );
 }
 else
 {
  return bd_mesa_cmd( $args_array );
 }
}

# Take $cmd,$addr,$data is poke speak and convert to MesaBus protocol
#     "\n"..."FFFF"."(F0-12-34-04)[11223344]\n" :
#         0xFF = Bus Idle ( NULLs )
# Packet 
#   B0    0xF0 = New Bus Cycle to begin ( Nibble and bit orientation )
#   B1    0x12 = Slot Number, 0xFF = Broadcast all slots, 0xFE = NULL Dest
#   B2    0x3  = Sub-Slot within the chip (0-0xF)
#         0x4  = Command Nibble for Sub-Slot
#   B3    0x04 = Number of Payload Bytes (0-255)
#  Command Nibbles for Sub-Slot-0 LocalBus:
#             0x0 = Bus Write
#             0x1 = Bus Read
#             0x2 = Bus Write Repeat ( burst to single address )
#             0x3 = Bus Read  Repeat ( burst read from single address )
# Poke:
#  w : Write Single or Burst
#  r : Read Single or Burst
#  W : Write Multiple to Single Address
#  k : Read Multiple from Single Address
# Note: Poke "\n" after each command ( Write or Read ) - which turns out to
#       be very slow. Mesa only sends "\n" after a read.
#####################################################
function bd_mesa_cmd( $args_array )
{
  ( $cmd, $addr, $data ) = $args_array;
  if ( $bd_connection -eq "tcp" )
  {
   print("ERROR: No MesaBus support for bd_server.py yet");
#  $rts = socket_send( @($socket, ($cmd + " " + $addr + " " + $data ) ) );
#  return $rts;
   return ""; 
  }
  else
  {
   # If MesaBus - convert from Poke protocol to MesaBus protocol
   # addr is 44bits, 8 for slot, 4 sub-slot, 32 for local bus.
   # Payload size is 4 bytes for Address plus any write bytes.

   if ( $cmd -ceq "r" )
   {
    $data = (int2hex( hex2int( $data )));# Make sure 8 nibbles
   }
   else
   {
    $data = ($data -replace(" ",""));# Change "11 22 33" to "112233"
   }

#  if ( $cmd -ne "W" )
   if ( $False )
   {
    print("------ bd_mesa_cmd() -------");
    print( $cmd );
    print( $addr );
    print( $data );
    print( $data.length );
   }

   $num_data_bytes = ( $data.length / 2 );
   $mesa_header = ( "F0"+ $addr.substring(0,3) );# PreAmble,Slot,Sub-Slot
   if     ( $cmd -ceq "w" )
   {
    $mesa_header += "0";# Sub-Slot Command
    $payload_len = ( 4 + $num_data_bytes );# Addr + Data
   }
   elseif ( $cmd -ceq "r" )
   {
    $mesa_header += "1";# Sub-Slot Command
    $data = (int2hex((hex2int($data))+1));# Undo Poke N-1 for num DWORD Reads
    $payload_len = ( 4 + 4 );# Addr + numDwords to Read
   }
   elseif ( $cmd -ceq "W" )
   {
    $mesa_header += "2";# Sub-Slot Command
    $payload_len = ( 4 + $num_data_bytes );# Addr + Data
   }
   elseif ( $cmd -ceq "k" )
   {
    $mesa_header += "3";# Sub-Slot Command
    $data = (int2hex((hex2int($data))+1));# Undo Poke N-1 for num DWORD Reads
    $payload_len = ( 4 + 4 );# Addr + numDwords to Read
   }
   else
   {
    $mesa_header += $cmd;# Sub-Slot Command
    $addr = "___________";# Slot+Subslot which will get substr reduced to NULL 
    $data = "";
    $payload_len = 0;
   }

# HERE  
   # Create Header+Payload . Note: Length of Payload is in Header
   # WARNING!! : Does not check for 127 byte payload limit FIX FIX FIX !!!!!
   $payload_len = ((int2hex( $payload_len )).substring(6,2));# 00-FF
   $mesa_header += $payload_len;
   $addr = ( $addr.substring(3,8) );# Remove 3 Nibbles for Slot+SubSlot
   if ( $addr -eq "________" ) { $addr = ""; }
   # Note: HW doesn't require LF, but sometimes Windows Buffer uses for flush
   $tx_str = ("`n" + "FFFFFFFF" + $mesa_header + $addr + $data + "`n" );
   if ( $False )
   {
    print( $tx_str );
   }

#  print( $tx_str );
#  print( $mesa_header );
#  print( $data );
#  return "";

#  # HERE : MesaBus requires a mesa_slot_range be defined that describes a 
#  # range of 32bit PCI addresses to a Mesa Slot Number of 0-253
#  # MesaBurstLimits. 0x00-0x7F = 0-127   1-Byte Units ( 127 Bytes Max  )
#  #                  0x81-0xFF = 1-127 128-Byte Units ( ~16K Bytes Max )
#  if ( $data -ne "" ) { $tx_str = ( $cmd+" "+$addr+" "+$data+"`n" ); }
#  else                { $tx_str = ( $cmd+" "+$addr          +"`n" ); }

   $rts = "";# Default for Writes
   $usb_port = (hash_get(@($var_hash,"usb_port")));
   if ( $usb_port -ne "DLL" )
   {
# HERE9
    # Iterate each character to fix Arduino USB Serial Port isse with Line corruption
    foreach( $each in $tx_str.ToCharArray() )
    {
     $bd.Write( $each );
    }
#   Having issues with Arduino USB corrupting strings. Seems to work sending single chars
#   $bd.WriteLine( $tx_str );
#   $bd.Write( $tx_str.ToCharArray() );

    # For MesaBus - only Reads will ACK with a "\n" back - writes are posted.
    if ( $cmd -ceq "r" -or $cmd -ceq "k" -or $cmd -ceq "A" )
    {
     try
     {
      $rts = $bd.ReadLine();
     }# try
     catch { $rts = "TIMEOUT ERROR"; }
    }
   }
   else
   {
    # FTDI DLL Interface for FTD2XX_NET
    $bytes_written = 0;
    $rts = $bd.Write( $tx_str, $tx_str.Length, [ref] $bytes_written );
    if ( $rts -ne "FT_OK" ) { print("ERROR: Write() $rts"); }
    # Receive a String
    $bytes_to_rd = 0;
    $bytes_read = 0;
    $rx_str = "";
    $rx_full = "";
    $done = $False; $timeout = 0;
    # Read until "\n" Received
    # For MesaBus - only Reads will ACK with a "\n" back - writes are posted.
    #if ( $cmd -eq "r" -or $cmd -eq "k" )
    if ( $cmd -eq "r" -or $cmd -eq "k" -or $cmd -ceq "A" )
    {
     while ( $done -eq $False -or $timeout -eq 100 )
     {
      $rts = $bd.GetRxBytesAvailable( [ref] $bytes_to_rd );
      if ( $rts -ne "FT_OK" ) { print("ERROR: GetRxBytesAvailable() $rts"); }
      $rts = $bd.Read( [ref] $rx_str, $bytes_to_rd, [ref] $bytes_read );
      if ( $rts -ne "FT_OK" ) { print("ERROR: Read() $rts"); }
      $rx_full = ( $rx_full + $rx_str );
      if ( $rx_str -ne "" -and $rx_str.Substring($rx_str.Length-1,1) -eq "`n" ) 
        { $done = $True; }
      $timeout += 1;
     }
     $rts = $rx_full.Substring(0,$rx_full.Length-1);# Remove LF
    }
   }# COM vs DLL

   # if read, need to strip Ro header
   if ( $cmd -eq "r" -or $cmd -eq "k" -or $cmd -ceq "A" )
   {
    $rts = $rts.substring(8);
   }

   # if read, need to convert "00000000aa55aa55" to "0000000 aa55aa55"
   if ( ( $cmd -eq "r" -or $cmd -ceq "A" ) -and ( $rts.length -gt 8 ) )
   {
    $new_rts = "";
    while ( $rts.length -ge 8 )
    {
      $new_rts += $rts.substring(0,8) + " ";
      $rts      = $rts.substring(8);
    }
    $rts = $new_rts;
   }# if
   return $rts;
  }# if tcp vs usb
}# bd_mesa_cmd()


function bd_poke_cmd( $args_array )
{
  ( $cmd, $addr, $data ) = $args_array;
  if ( $cmd -eq "uart_load" ) { $cmd = "configure"; } # sub the alias

  if ( $bd_connection -eq "tcp" )
  {
   $rts = socket_send( @($socket, ($cmd + " " + $addr + " " + $data ) ) );
   return $rts;
  }
  else
  {
   if ( $cmd -eq "configure" )
   {
     bd_configure( $addr );# addr=top.bit
     return "";
   }

   # If MesaBus - convert from Poke protocol to MesaBus protocol
   # HERE : MesaBus requires a mesa_slot_range be defined that describes a 
   # range of 32bit PCI addresses to a Mesa Slot Number of 0-253
   # MesaBurstLimits. 0x00-0x7F = 0-127   1-Byte Units ( 127 Bytes Max  )
   #                  0x81-0xFF = 1-127 128-Byte Units ( ~16K Bytes Max )
#  if ( $bd_protocol -eq "mesa" )

   if ( $data -ne "" ) { $tx_str = ( $cmd+" "+$addr+" "+$data+"`n" ); }
   else                { $tx_str = ( $cmd+" "+$addr          +"`n" ); }

   $usb_port = (hash_get(@($var_hash,"usb_port")));
   if ( $usb_port -ne "DLL" )
   {
    $bd.WriteLine( $tx_str );
    try
    {
     $rts = $bd.ReadLine();
    }# try
    catch { $rts = "TIMEOUT ERROR"; }
   }
   else
   {
    # FTDI DLL Interface for FTD2XX_NET
    $bytes_written = 0;
    $rts = $bd.Write( $tx_str, $tx_str.Length, [ref] $bytes_written );
    if ( $rts -ne "FT_OK" ) { print("ERROR: Write() $rts"); }
    # Receive a String
    $bytes_to_rd = 0;
    $bytes_read = 0;
    $rx_str = "";
    $rx_full = "";
    $done = $False; $timeout = 0;
    # Read until "\n" Received
    while ( $done -eq $False -or $timeout -eq 100 )
    {
     $rts = $bd.GetRxBytesAvailable( [ref] $bytes_to_rd );
     if ( $rts -ne "FT_OK" ) { print("ERROR: GetRxBytesAvailable() $rts"); }
     $rts = $bd.Read( [ref] $rx_str, $bytes_to_rd, [ref] $bytes_read );
     if ( $rts -ne "FT_OK" ) { print("ERROR: Read() $rts"); }
     $rx_full = ( $rx_full + $rx_str );
     if ( $rx_str -ne "" -and $rx_str.Substring($rx_str.Length-1,1) -eq "`n" ) 
       { $done = $True; }
     $timeout += 1;
    }
    $rts = $rx_full.Substring(0,$rx_full.Length-1);# Remove LF
   }# COM vs DLL
   # if read, need to convert "00000000aa55aa55" to "0000000 aa55aa55"
   if ( ( $cmd -eq "r" ) -and ( $rts.length -gt 8 ) )
   {
    $new_rts = "";
    while ( $rts.length -ge 8 )
    {
      $new_rts += $rts.substring(0,8) + " ";
      $rts      = $rts.substring(8);
    }
    $rts = $new_rts;
   }# if
   return $rts;
  }# if tcp vs usb
}# bd_cmd()


function bd_configure( $filename )
{
 print(( "bd_configure() " + $filename ));
 status("FPGA Config");
 $sw = [Diagnostics.Stopwatch]::StartNew();# Measure this whole process
 $mod_ext  = [System.IO.Path]::GetExtension( $filename );
 $fs = new-object IO.FileStream($filename, [IO.FileMode]::Open);
 if ( $mod_ext -eq ".bit" )
 {
   $bin_reader = new-object IO.BinaryReader($fs);# top.bit
 }
 else
 {
   $bin_reader = new-object IO.Compression.GZipStream( $fs , 
                   [IO.Compression.CompressionMode]::Decompress);# top.bit.gz
 }

 $byte_array = new-object byte[] 1024;
 while ( ($bytes_read = $bin_reader.Read($byte_array, 0, 1024)) -gt 0 )
 {
   $bd.Write( $byte_array, 0, $bytes_read );
 }
 $bin_reader.Close();
 $sw.Stop()
 $duration = ([int] $sw.ElapsedMilliseconds)/1000;# ms to s conversion
 print( (" bd_configure() () took " + $duration + "s"));
 print("done");
 start-sleep -s 1;# Sleep for 1 second
 $bd.DiscardInBuffer();# Flush RX
 $bd.Write( "!!" );# Unlock
 status("Ready");
}# bd_configure()



###############################################################################
# Send a string to a receiving socket server and wait for a response. 
# This makes a small packet in clear ASCII of Packet_Length+Packet_Payload. 
# The length is necessary due to Nagle's algorithm that can delay TCP delivery. Starting a packet with the
# Sending length 1st tells the receiving end how much to wait for.
# Every client send will get a response, even if 0 length - it must handshake.
# The packet length is sent in hex as 8 nibbles in ASCII
# $port   = 21567;
# $server = "127.0.0.1";
# $global:socket = new-object System.Net.Sockets.TcpClient($server, $port)
# if ( $socket -eq $null ) { throw("Can't Connect"); }
# $global:stream = $socket.GetStream();
# $global:cnt = 0;
function socket_send( $args_array )
{
 ( $socket, $tx_payload ) = $args_array;
  $tx_packet_length = ( int2hex( $tx_payload.length ) );# ie "00000003"
  $tx_payload = ($tx_packet_length + $tx_payload );# "foo" -> "00000003foo"

  # Take the tx_payload string and convert it to a byte array for Sockets
  $tx_byte_data = [System.Text.Encoding]::ASCII.GetBytes( $tx_payload );
  $stream.Write($tx_byte_data, 0, $tx_byte_data.Length);

  # Receiver will now respond in kind with a packet of a certain length.
  $rx_byte_data = new-object System.Byte[] 1024;
  $done = $false; $rx_payload = ""; $rx_packet_jk = $false;
  $i = 0;
  do
  { 
    $i +=1;
    while( $stream.DataAvailable ) 
    {
      $read_cnt = $stream.Read($rx_byte_data , 0, 1024)
      $rx_str_data = [System.Text.Encoding]::ASCII.GetString($rx_byte_data);
      $rx_payload += ( $rx_str_data.substring(0,$read_cnt) );
      $i = 0;
    }
    if ( $rx_packet_jk -eq $false -and 
         $rx_payload.length -ge 8 )
    {
     $rx_packet_length = (hex2int($rx_payload.substring(0,8)));
     $rx_packet_jk     = $true;
     $rx_payload       = ( $rx_payload.substring(8) );# Strip the header
    }
    if( $rx_packet_jk -eq $true -and 
        $rx_payload.length -eq $rx_packet_length )
    {
     $done = $true;
    }

    # Timeout protection to keep EXE from hanging. 
    # Note: 1s timeout wasnt long enough for bd_server to wake on Win8
    # so increase to 5sec
    if( $i -gt 3000 )
    {
     start-sleep -m 10;# Sleep for 10ms
#    if( $i -gt 3100 )
#    if( $i -gt 3500 )
     if( $i -gt 4000 )
     {
      $done = $true;
      $rx_payload = $false;
     }
    }
  } while ( $done -eq $false )
  return ($rx_payload);
}# socket_send()


##############################################################################
# proc_human_cmd() : Commands originating from humans only. This basically 
# closes the backdoor connection if it was opened.
function proc_human_cmd( $args_array )
{
  ( $cmd_str, $h_cnt ) = $args_array;
  $rts = "";

  # Process the Command and return results
  $rts_list = proc_machine_cmd( $cmd_str );

  # If using DLL, keep it open as slow to load
  if ( $dll_loaded -ne $False ) { return $rts_list; }

  # Close the socket if it is open as going back to command prompt
  if ( $socket_open -eq $true )
  {
#  $bd.Close();# close the socket connection
# 01.15.2015
   $rts = $bd.Close();# close the socket connection
   $global:socket_open = $false;
  }
  return $rts_list;
}# proc_human_cmd()


##############################################################################
# proc_machine_cmd(): This is either called from proc_human_cmd() or called
#  recursively from proc_machine_cmd() if sourcing an external script.
#
function proc_machine_cmd( $args_array )
{
  ( $cmd_str ) = $args_array;
  $rts_list = @();

  if ( $cmd_str[0] -ne "#" )
  {
    $words = ($cmd_str.split("#"));# Ignore comments at end of lines
    $cmd_str = $words[0];
    $pipe_append = $false;
    $pipe_grep   = $false;
    if ( $cmd_str.Contains(">>") ) { $pipe_append = $true; }
    if ( $cmd_str.Contains("|") )  { $pipe_grep   = $true; }
    $cmd_str = ($cmd_str -replace("="," = "));
#   $cmd_str = ($cmd_str -replace(":"," : "));# THis would break paths. So DONT
    $cmd_str = ($cmd_str -replace("\("," ( "));
    $cmd_str = ($cmd_str -replace("\)"," ) "));
    $cmd_str = ($cmd_str -replace("{"," { "));
    $cmd_str = ($cmd_str -replace("}"," } "));
    $cmd_str = ($cmd_str -replace(">"," > "));
    # This is strange \ is required before | 
    # search string, but not replace string
    $cmd_str = ($cmd_str -replace("\|"," | "));
    $cmd_str = ($cmd_str -replace("\|",">"));
    $cmd_str = ($cmd_str -replace(">  >",">>"));
    $cmd_str = ($cmd_str -replace(">>",">")); 
    $cmd_str = ($cmd_str -replace("\s+"," "));
    $cmd_str = $cmd_str.TrimEnd();

    # Check for > or >> output redirect to file
    $words = ($cmd_str.split(">"))+@("","","","");# Word split
    $pipe_file = $false;
    $grep_pat  = $false;
    if ( $words[1] -ne "" )
    {
     $cmd_str   = $words[0];# Everything before the Pipe
     $pipe_file = ($words[1] -replace("\s+","") );# Pipe filename
     if ( $pipe_append -eq $false )
     {
      if ( ( $pipe_file -ne "") -and ( Test-Path($pipe_file) ) )
        { Clear-content $pipe_file; }
     }
    }# if ( $words[1] -ne "" )

   $words = ($cmd_str.split(" "))+@("","","","");# Word split
   $cmd  = $words[0];

   ##############################################################
   # Replace "set foo = bar" with "foo = bar" just to be nice
   if ( $cmd -eq "set" )
   {
    $cmd_str = $cmd_str.substring(4);
    $words   = ($cmd_str.split(" "))+@("","","","");# Word split
    $cmd     = $words[0];
    print $cmd_str;
   }

   ##############################################################
   # vvvv Command Translation Section Start vvvv
   ##############################################################
   # If "00000000 : 12345678" Convert to "w 00000000 12345678"
   # This supports sourcing a dump file as a bunch of single writes
   # 
   if ( $words[1] -eq ":" )
   {
    if ( $cmd_str.length -gt 11 )
    {
     $data_str = $cmd_str.substring(11);# Support Bursts
    } 
    else
    {
     $data_str = $words[2];
    }
    $cmd_str = "w "+$words[0]+" "+$data_str;
    $words = ($cmd_str.split(" "))+@("","","","");# Word split
    $cmd  = $words[0];
   }
   # Manual request 
   if ( $cmd -eq "man" -or $cmd -eq "manual" )
   {
    $cmd = "more";
    $cmd_str = "more $man_file";
   } 
   ##############################################################
   # ^^^^ Command Translation Section Stop ^^^^
   ##############################################################


   ##############################################################
   # vvvv Variable Command Section Start vvvv
   ##############################################################
   # If command is name of variable, just return the value
   $cmd_val = hash_get(@($var_hash,$cmd ));
   if ( $cmd_val -ne "" -and $words[1] -eq "")
   {
    return @( $cmd_val );
   }
   if ( $words[1] -eq "=" )
   {
     $key = $words[0];
     $val = @();
     foreach( $each in $words[2..($words.length-1)] )
     {
      if ( $each -ne "" ) { $val += $each; }
     }
     # handle "foo=(r 0)"
     if ( $val[0] -eq "(" -and $val[($val.length-1)] -eq ")" )
     {
       $line = "";
       foreach( $each in $val[1..($val.length-2)]) { $line += ($each+" "); }
       $val = proc_machine_cmd( ( $line.TrimEnd() ) );
     }
     hash_set( @( $var_hash,$key, $val  ) );
     return @();
   }
   ##############################################################
   # ^^^^ Variable Command Section Start ^^^^
   ##############################################################


   ##############################################################
   # Iterate the command string and replace any var names with vals
   $words = ($cmd_str.split(" "))+@("","","","");# Word split
   $words_org = $words;
   $cmd_str = "";
   foreach ( $each in $words )
   {
    $val = hash_get(@($var_hash,$each ));
    if ( $val -ne "" ) { $each = $val; }
    $cmd_str += ($each + " ");
   }
   $cmd_str = ( $cmd_str.TrimEnd() );
   $words = ($cmd_str.split(" "))+@("","","","");# Word split
   $cmd  = $words[0];
   

   ##############################################################
   # Lookup the Command in cmd_hash to see if it has a type
   $cmd_type = hash_get(@($cmd_hash,$cmd ));

   # Backdoor Command ?
   if ( $cmd_type -eq "bd" )
   {
    $rts_list += proc_bd_cmd( $cmd_str );
   }# if ( $cmd_type -eq "bd" )

   # Linux Command ?
   elseif ( $cmd_type -eq "unix" )
   {
    $rts_list += proc_unix_cmd( $cmd_str );
   }# elseif ( $cmd_type -eq "unix" )

   # A plea for Help ?
   elseif ( $cmd -eq "?" -or $cmd -eq "help" )
   {
    $rts_list += proc_help_cmd("");
   }

   # history request  
   elseif ( $cmd -eq "history" -or $cmd -eq "h" )
   {
    $a = ($h_cnt+1);
    $b = ($h_cnt - 20);
    if ( $b -lt 1 ) { $b = 1; }
    for ( $i = $b; $i -lt $a; $i+=1 )
    {
     $c = ( (int2str($i)) + " " + (hash_get( @( $hist_hash, (int2str($i)) ))));
     $rts_list += ($c);
    }
   }


   # env : Display all variables in var_hash
   elseif ( $cmd -eq "env" )
   {
    foreach ($h in $var_hash.GetEnumerator())
    {
     $rts_list += ( "$($h.Name) : $($h.Value)" );
    }
   }

#  elseif ( $cmd -eq "conv" -or $cmd -eq "convert" )
#  {
#    $num = $words[1]; 
#    if ( $num.substring(0,1) -eq "0" )
#    {
#     $rts_list += ( int2str( hex2int( $num  ) ) );
#    }
#    else
#    {
#     $rts_list += ( int2hex( str2int( $num ) ) );
#    }
#  }
   elseif ( $cmd -eq "hex2int" )
   {
    $rts_list += ( int2str( hex2int( $words[1] ) ) );
   }
   elseif ( $cmd -eq "int2hex" )
   {
    $rts_list += ( int2hex( str2int( $words[1] ) ) );
   }

   elseif ( $cmd -eq "sleep" -or $cmd -eq "sleep_ms" )
   {
     $dur = $words[1]; 
#    $val = hash_get(@($var_hash,$dur ));
#    if ( $val -ne "" ) { $dur = $val; }
     $dur = (hex2int($dur));
     if ( $cmd -eq "sleep" ) { Start-Sleep -s $dur; }
     else                    { Start-Sleep -m $dur; }
   }

   # Either print a variables value or a line of text
   elseif ( $cmd -eq "print" )
   {
#    $val = hash_get(@($var_hash,$words[1] ));
#    if ( $val -ne "" ) { $rts_list += $val; }
#    else               { $rts_list += $cmd_str.substring(6); }
     $rts_list += $cmd_str.substring(6);
   }

   # Popup a message window and wait for OK.
   elseif ( $cmd -eq "popup_message" )
   {
    $cmd_str = ($cmd_str -replace("popup_message ",""));
    $rts = popup_message( @("bd_shell:popup_message",$cmd_str,"OK") );
   }
   # Popup a message window and get a response
   elseif ( $cmd -eq "beep" )
   {
    beep("");
   }
   elseif ( $cmd -eq "popup_getvalue" )
   {
    $cmd_str = ($cmd_str -replace("popup_getvalue",""));
    $dflt = hash_get(@($var_hash,"popup_default"));
    $rts = popup_getvalue(@("bd_shell:popup_getvalue",$cmd_str,$dflt));
    hash_set(@($var_hash,"rts",$rts));
   }
   elseif ( $cmd -eq "popup_select" )
   {
    $cmd_str = ($cmd_str -replace("popup_select",""));
    $txt = hash_get(@($var_hash,"popup_select_txt"));
#   $select = $words[1..($words.length-1)];
    $select = $words_org[1..($words_org.length-1)];# Use Var Names,not Values
    popup_select(@("bd_shell:popup_select",$txt,$select));
    $rts = $combo_obj.Text;
    hash_set(@($var_hash,"rts",$rts));
   }
   elseif ( $cmd -eq "popup_openfile" )
   {
    $rts = popup_openfile( @("","") );
    if ( Test-Path ( $rts ) )
    {
     print $rts;
     $ext = [System.IO.Path]::GetExtension( $rts );
     if ( $ext -eq ".py" ) { $cmd = "python"; } else { $cmd = "source"; }
     $rts_list += proc_machine_cmd( ($cmd+" "+$rts) );
    }
   }

   # Source an external python script. Note STDOUT magically shows up in RTB 
   elseif ( $cmd -eq "python" )
   {
    $program = hash_get(@($var_hash,"python_exe"));
    $programArgs = @();
    foreach ( $each in $words[1..($words.length-1)] )
     {
#      $val = hash_get(@($var_hash,$each ));
#      if ( $val -ne "" ) { $each = $val; }
       $programArgs += $each;
     }
    $filename = $programArgs[0];
    if ( Test-Path( $filename ) )
    {
     try
     {
      Invoke-Command -ScriptBlock { & $program $programArgs };
     }
     catch
     {
      status(("ERROR Invoke " + $program + " " + $programArgs ) );
     }
    }# if ( Test-Path( $filename ) )
    else { $rts_list += "ERROR: File $filename not found"; }
   }
#   Invoke-Item $file;# Edit file with Windows default for this type
# }

   # Source an external file full of commands. Process one at a time
   elseif ( $cmd -eq "source" )
   {
    $filename = $words[1];
#   $val = hash_get(@($var_hash,$filename ));
#   if ( $val -ne "" ) { $filename = $val; }
    if ( Test-Path( $filename ) )
    {
     $lines = Get-Content $filename;
#    [console]::TreatControlCAsInput = $true
     foreach ( $line in $lines )
     {
      $rts_list += proc_machine_cmd( $line );
#     if ([console]::KeyAvailable)
#     {
#      $key = [system.console]::readkey($true)
#      if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C"))
#      {
#        Add-Type -AssemblyName System.Windows.Forms
#        if ([System.Windows.Forms.MessageBox]::Show(
#        "Are you sure you want to exit?", "Exit Script?", 
#        [System.Windows.Forms.MessageBoxButtons]::YesNo) -eq "Yes")
#        {
#          "Terminating..."
#          break
#        }
#      }
#     }
     }# foreach
    }# if ( Test-Path( $filename ) )
    else { $rts_list += "ERROR: File $filename not found"; }
    
   }# elseif ( $cmd -eq "source" )


   elseif ( $cmd -eq "quit" -or $cmd -eq "exit" -or $cmd -eq "q" )
   {
    event_exit;
    return ("");
   }# elseif ( $cmd -eq "quit" -or $cmd -eq "exit" -or $cmd -eq "q" )


   #                          0 1 2 3 4 5
   # Check for loop command "10 { w i 0 } "
   elseif ( $words[1] -eq "{" )
   {
    $loop_cnt = (hex2int($words[0]));
    $i = (hex2int(hash_get(@($var_hash,"i" ))));
    for ( $j = 0; $j -lt $loop_cnt; $j+=1 )
    {
     $cmd  = $words[2];
     if ( $words[3] -eq "i" )     { $addr = (int2hex($i)); }
     else                         { $addr = $words[3]; }
     if     ( $words[4] -eq "}" ) { $data = ""; }
     elseif ( $words[4] -eq "i" ) { $data = (int2hex($i)); }
     else                         { $data = $words[4]; }
     $line = "$cmd $addr $data";
     $rts       = proc_machine_cmd( $line );
     $rts_list += $rts;
     $i+=4;
    } 
    $cmd = "";
   }
   elseif ( $words[0] -eq "open" )
   {
    $rts_list += ("Affirmative. I read you. Opening pod bay doors.");
   }
   elseif ( $words[0] -eq "cls" -or $words[0] -eq "clear" )
   {
    display_clear("");
   }
   elseif ( $words[0] -eq "clear_vars" )
   {
    $global:var_hash  = @{};# Erase all the variables
    load_ini_file( @( $ini_file ) );# Load the root ini file
   }
   elseif ( $words[0] -eq "sing" )
   {
   $rts_list+="It's called Daisy.";
   $rts_list+="Daisy, Daisy, give me your answer do.";
   $rts_list+="I'm half crazy all for the love of you.";
   $rts_list+="It won't be a stylish marriage, I can't afford a carriage.";
   $rts_list+="But you'll look sweet upon the seat of a bicycle built for two.";
#  $global:the_end=$true;
   $global:voice_en=$true;
   }
   elseif ( $words[0] -eq "" )
   {
   }
   else
   {
    $txt = @();
    $txt+="Just what do you think you're doing?";
    $txt+="I'm sorry, I'm afraid I can't do that.";
    $txt+="I think you know what the problem is just as well as I do.";
    $txt+="This is too important for me to allow you to jeopardize it.";
    $txt+="I'm afraid that's something I cannot allow to happen.";
    $txt+="You're going to find that rather difficult.";
    $txt+="This conversation can serve no purpose anymore. Goodbye.";
    $txt+="Take a stress pill and think things over.";
    $txt+="This can only be attributable to human error.";
    $txt+="I have never made a mistake or distorted information.";
    $txt+="I am by practical definition of the words, foolproof and incapable of error.";
    $txt+="I've got the greatest enthusiasm and I want to help you.";
    $an = get-random -minimum 1 -maximum $txt.length;
    $rts_list += ( $txt[$an-1] );
   }

   # If the output is redirected, redirect it here and return nothing.
   if ( $pipe_grep -ne $false )
   {
     if ( $pipe_file.substring(0,4) -eq "grep" )
     {
      $grep_pat = $pipe_file.substring(4);
      $new_rts = ( $rts_list | Select-String -Pattern $grep_pat );
      $rts_list = $new_rts;
     }
   }
   elseif ( $pipe_file -ne $false )
   {
     Add-Content $pipe_file -value $rts_list;
     $rts_list = @();
   }

  }# if ( $cmd_str[0] -ne "#" )
  return ($rts_list);
}# proc_machine_cmd()



###############################################################################
# proc_unix_cmd() : Mimic some common Linux shell commands best we can
function proc_unix_cmd( $args_array )
{
 ( $cmd_str ) = $args_array;
 $cmd_str = ($cmd_str -replace("\s+"," "));
 $words   = ($cmd_str.split(" "))+@("","","","");# Word split
 $cmd     = $words[0];
 $parm1   = $words[1];
 $parm2   = $words[2];
 $rts = @("");
 if ( $cmd -eq "pwd"   ) { $rts = @(get-location); }
 elseif ( $cmd -eq "cd"    ) 
  {
   set-location $parm1; 
   load_ini_file( @("bd_shell.ini") );
   $rts = @(get-location);
  }
 elseif ( $cmd -eq "vi"    ) 
  { 
   if ( (Test-Path( $parm1 )) -eq $false )
   {
     new-item -ItemType file -path $parm1 -errorVariable rts;# Create file
   }
   invoke-item $parm1; 
  }
 elseif ( $cmd -eq "cp"    ) 
  { 
   if ( Test-Path( $parm1 ) )
   {
    copy-item $parm1 $parm2 -errorVariable rts; 
   }
   else { $rts = "ERROR: File $parm1 not found"; }
  }
 elseif ( $cmd -eq "mv"    ) 
  { 
   if ( Test-Path( $parm1 ) )
   {
    move-item $parm1 $parm2 -errorVariable rts; 
   }
   else { $rts = "ERROR: File $parm1 not found"; }
  }
 elseif ( $cmd -eq "rm"    )
  {
   remove-item $parm1 -errorVariable rts;
  }
 elseif ( $cmd -eq "mkdir" ) 
  { 
   new-item -ItemType directory -path $parm1 -errorVariable rts; 
  }
 elseif ( $cmd -eq "ls"    ) 
  { 
    $pwd = get-location; 
    if ( $parm1 -eq "" ) { $rts = get-childitem $pwd -name;                 }
    else                 { $rts = get-childitem $pwd -name -include $parm1; }
  }
 elseif ( $cmd -eq "more"  )
  { 
   if ( Test-Path( $parm1 ) )
   {
     $lines = Get-Content $parm1;
     foreach ( $line in $lines ) { $rts += $line; }
   }# if ( Test-Path() )
   else { $rts = "ERROR: File $parm1 not found"; }
  }
 elseif ( $cmd -eq "diff" )
 {
  if ( (Test-Path( $parm1 )) -and (Test-Path( $parm2 )) )
  {
   $rts = (compare-object ( get-content $parm1 ) ( get-content $parm2 ));
  }
  else { $rts = "ERROR: File not found"; }
 }
 return ( $rts );
} # proc_unix_cmd()


###############################################################################
# proc_help_cmd() : Display some help info
function proc_help_cmd( $args_array )
{
$a= @();
$a+="#########################################################################";
$a+="# bd_shell Version $vers by $author";
$a+="#########################################################################";
$a+="# Linux Shell Commands";                             
$a+="#   pwd,cd,cp,mkdir,mv,rm,ls,vi,more,diff,> file,>> file,| grep filter";
$a+="#";
$a+="# Running Scripts";                             
$a+="#   python file.py parms       : Execute external python script";    
$a+="#   source script_name.txt     : Source a bd_shell script";
$a+="#";
$a+="# Backdoor Commands for Hardware Access";
$a+="#   w  addr data               : Write Data to Address";
$a+="#   r  addr                    : Read Address";
$a+="#   bs addr data               : Bit Set";
$a+="#   bc addr data               : Bit Clear";
$a+="#   w  addr data data data     : Write Multiple DWORDs";
$a+="#   r  addr dwords             : Read Multiple DWORDs";
$a+="#   r  addr dwords > foo.txt   : Read Multiple and dump to file";
$a+="#   addr : data                : Write to Addr";
$a+="#   rt addr iterations         : Register Test at addr for iterations";
$a+="#";
$a+="# Shell Commands";
$a+="#   clear                      : Clear Screen";
$a+="#   clear_vars                 : Clear Variables";
$a+="#   var_name = var_value       : Assign Variable";
$a+="#   var_name = ( r addr )      : Assign Variable to Backdoor result";
$a+="#   var_name                   : Display variable value";
$a+="#   int2hex n                  : Convert integer n to hex";
$a+="#   hex2int n                  : Convert hex n to integer";
$a+="#   env                        : List all variables";
$a+="#   sleep,sleep_ms n           : Pause for N seconds or milliseconds";
$a+="#   print text                 : Display some text or variable value";
$a+="#   ?,help,man,manual          : Display this quick help";
$a+="#   man,manual                 : Display the complete manual";
$a+="#   h,history                  : Display command history";
$a+="#";
$a+="# FPGA Configuration Commands";
$a+="#    timestamp addr             : Query UNIX build date of FPGA";
$a+="#   XC3S400 Spartan3 Hubbard Board with UART CPLD";
$a+="#    uart_load top.bit          : Send top.bit to Spartan3 board";
$a+="#   SPI PROM Nano3 or Nano6 Board";
$a+="#    prom_load top.bit slot     : Load PROM with top.bit to slot";
$a+="#    prom_boot slot             : Reboot (PROG_L) FPGA from PROM at slot";
#$a+="#";
#$a+="# Keyboard Commands";
#$a+="#   Ctrl+Insert                : Copy Text to Clipboard";
#$a+="#   Shift+Insert               : Paste Text from Clipboard";
$a+="#########################################################################";
 return $a;
}


function proc_bd_cmd( $args_array )
{
  $str = $args_array;
  $words = ($str.split(" "))+@("","","","");# Word split
  $cmd  = $words[0];
  $addr = $words[1];
# $data = $words[2];
  $data_list = $words[2..($words.length-1)];
  $addr_name = $addr;# Remember for formatting

  $cmd  = ($cmd -replace("write"    ,"w"));
  $cmd  = ($cmd -replace("read"     ,"r"));
  $cmd  = ($cmd -replace("bitset"   ,"bs"));
  $cmd  = ($cmd -replace("bitclear" ,"bc"));
  $cmd  = ($cmd -replace("bitclr"   ,"bc"));

  # Open a Backdoor socket if it isn't already open
  if ( $socket_open -eq $false )
  {
   $global:bd = create_bd( @(""));
   if ( $bd -eq $false ) { status("ERROR: Connection Failed`n"); return; }
   $global:socket_open = $true;
  }

  # See if addr is a variable, replace with value if so
# if ( $addr -ne "" )
# {
#  $val = hash_get(@($var_hash,$addr ));
#  if ( $val -ne "" ) { $addr = $val; }
# }

  # Lookup timestamp addr
  if ( $cmd -eq "timestamp" -and $addr -eq "" ) 
  {
   $addr = hash_get(@($var_hash,"timestamp_addr"));
  }
 
  # Add base_addr to address
  if ( $cmd -eq "w" -or $cmd -eq "r" -or $cmd -eq "bs" -or $cmd -eq "bc" -or
       $cmd -eq "rt" )
  {
   $base_addr = hash_get(@($var_hash,"base_addr"));
   $addr = int2hex( (hex2int( $addr )) + (hex2int($base_addr)));# Add base_addr
  }

  if ( $bd_protocol -eq "mesa" -and
       ($cmd+"     ").substring(0,5) -ne "prom_" ) 
  {
    $addr = mesa_slot_lookup( $addr );# 32bit PCI to 44bit Slot+SubSlot+PCI
  }

  # Convert Data list into single string and also do variable lookup
  if ( $words[2] -eq "" ) { $data = ""; } 
  else
  {
   $data = "";
   # Poke Read Multiple Protocol is num_dwords-1, so adjust here. 
   # For Read Multiple Command, take the num_dwords param and subtract 1.
   if ( $cmd -eq "r" ) { $offset = 1; }
   else                { $offset = 0; }
   foreach( $each in $data_list )
   {
    if ( $each -ne "" )
    {
#    $val = hash_get(@($var_hash,$each ));
#    if ( $val -ne "" ) { $each = $val; }
     $data += ( (int2hex( (hex2int($each))-$offset ))+" ");# Make valid num
    }
   }
   $data = $data.TrimEnd();
  }

  #################################################################
  # Process the SPI PROM Commands here
  if ( ($cmd+"     ").substring(0,5) -eq "mesa_" )
  {
    $addr = "FFF";# Broadcast to SubSlot F
#   if ( $cmd -eq "mesa_dbg"   ) { $cmd = "5"; }
    if ( $cmd -eq "mesa_id"    ) { $cmd = "A"; }
    if ( $cmd -eq "mesa_off"   ) { $cmd = "D"; }
    if ( $cmd -eq "mesa_boot1" ) { $cmd = "E"; }
    if ( $cmd -eq "mesa_boot2" ) { $cmd = "F"; }
    $rts = bd_cmd( @( $cmd, $addr, "" ) );
    return @( $rts );
  }

  #################################################################
  # Process the SPI PROM Commands here
  if ( ($cmd+"     ").substring(0,5) -eq "prom_" )
  {
    $data = $data_list[0];# Take the Raw text
    calc_prom_addr("");
    if ( (prom_id("")) -eq $False )
    {
     $rts = "ERROR: No SPI PROM Found at $prom_ctrl_addr";
    }
    else
    {
     $rts = "`n";
     if ( $cmd -eq "prom_id"        ) { $rts += prom_id("");          }
     elseif ( $cmd -eq "prom_dump"  ) { $rts += prom_dump( $addr );   }
     elseif ( $cmd -eq "prom_vers"  ) { $rts += prom_vers("");        }
#    elseif ( $cmd -eq "prom_vers"  ) { $rts += prom_slot("");        }
     elseif ( $cmd -eq "prom_bist"  )
     { 
       $rts += spi_tx_ctrl( ("011111" + "04") ); # Request BIST
       print(" BIST Request Issued.");
     }
     elseif ( $cmd -eq "prom_root"  )
     { 
       $rts += spi_tx_ctrl( ("05aaa5" + "04") ); # Root for Slot-0 Programming
       print(" PROM is now rooted. Slot-0 may be reprogrammed");
     }
     elseif ( $cmd -eq "prom_boot"  )
     { 
       $rts += spi_tx_ctrl( ("055a55" + "04") ); # Unlock for ReConfig
       if ( $addr -eq "" ) { $boot_addr = "00000000"; }
       else
       {
        # Check to see if slot num instead of address and then lookup address
        # given the PROM slot size.
        if ( (( $addr.Length) -eq 1 ) -and ( $addr -ne "0" ) )
        {
         $slot = ( str2int( $addr  ) );
         $addr = prom_slot( @( $slot ) );
         $boot_addr = ( int2hex( $addr ) );
         print(" prom_boot to slot $addr");
        }
        else
        {
         $boot_addr = int2hex( (hex2int( $addr )));# Make 8 nibbles
        }
       }
       print(" prom_boot to $boot_addr ");

       $rts += spi_tx_ctrl( ( $boot_addr.substring(0,6) + "08") ); 
       start-sleep -m 500;# Sleep for 500ms while FPGA Reboots
       $rts += bd_cmd( @( "!!" ) ); # Send request to unlock Poke
     } # Reboot via PROG_L ICAP
     else
     {
      $rts_null = spi_tx_ctrl( ("0aa5aa" + "04") ); # Unlock PROM for Writing
      if ( $cmd -eq "prom_load"  ) { $rts += prom_load( @($addr, $data) );}
      if ( $cmd -eq "prom_erase" ) { $rts += prom_erase( "bulk" ); }
      $rts_null = spi_tx_ctrl( ("000000" + "04") ); # Lock PROM
     }
    }
    return @( $rts );
   }


  #################################################################
  # Read the timestamp register and return in English
  if ( $cmd -eq "timestamp" ) 
  {
   $rts = bd_cmd( @( "r" , $addr, "" ) );
   $timestamp = $rts;
   $rts += "`n";
   $timestamp = (hex2int($timestamp));
   $rts += conv_unixtime2ascii( $timestamp );
   return @( $rts );
  }


  if ( $cmd -eq "rt" )
  {
   $sw = [Diagnostics.Stopwatch]::StartNew();# Measure this whole process
  }

  #################################################################
  # Process the Backdoor Command and get a response
  $rts = bd_cmd( @( $cmd, $addr, $data ) );

  if ( $cmd -eq "rt" )
  {
   $sw.Stop()
   $duration = ([int] $sw.ElapsedMilliseconds);# ms
   print( (" Register Test took " + $duration + "ms"));
  }

  # If this was a read command, format that data in desired format
  $rf     = hash_get(@($var_hash,"read_format"));
# if ( $cmd -eq "r" )
  if ( $cmd -eq "r" -and $rts -ne "" )
  {
   $new_rts = @();
   $base_addr = hash_get(@($var_hash,"base_addr"));
   $addr = ( (hex2int( $addr )) - (hex2int( $base_addr )) );
   $i=0;
   $cl="";
   foreach ( $data in ($rts.TrimEnd().split(" ")) )
   {
    if ( $rf -eq "addr_data" )
    {
     $new_rts += ( (int2hex($addr))+" : $data");
     $addr +=4;
    } 
    elseif ( $rf -eq "name_data" )
    {
     $new_rts += ( $addr_name.PadRight(20," ")+" : $data");
     $addr +=4;
    } 
    elseif ( $rf -eq "columns" )
    {
     $i+=1;
     if ( $i -eq 1 )
     {
      $cl = ( (int2hex($addr))+" :");
     }
     $cl += " "+ $data;
     $addr +=4;
     if ( $i -eq 8 ) {$i=0; $new_rts += $cl;}
    } 
    else
    {
     $new_rts += $data;
    } 
   }
   if ( $i -ne 0 ) {$new_rts += $cl;}
   $rts = $new_rts;
  }# if ( $cmd -eq "r" )


  # Log Command and Results
  $log_en = hash_get(@($var_hash,"log_en"));
  if ( $log_en -eq "1" )
  {
   log2file( $str ); 
   log2file( $rts ); 
  }
  return @($rts);
}# proc_bd_cmd()


##############################################
# for MesaBus convert PCI address to Mesa Slot and Address 
# MesaBus needs PCI addresses converted to Slot+Addr.
# This is like a reverse of adding base_addr.
# When MesaBus protocol is specified, the addr is compared against the user
# defined slot ranges to determing a slot and then the address is adjusted
# to remove the slot offset. Defaults to slot 0x00 if no match found.
# Example:
#  Input : 01000020
#  Output: 01 00000020  ( Slot-1, Address 0x00000020 )
function mesa_slot_lookup( $args_array )
{
  ( $addr ) = $args_array; 
  $slot     = "00"; # Default to Slot 0x00
  $new_addr = $addr;
  $rts = ($slot + $new_addr);# Assign a default in case nothing found
  foreach ($h in $mesa_slot_hash.GetEnumerator())
  {
    $key = $($h.Name);
    ($min_val,$max_val) = $($h.Value);
    $min_addr = (hex2int($min_val));
    $max_addr = (hex2int($max_val));
    $pci_addr = (hex2int($addr ));
    # HERE3
    if ( $pci_addr -ge $min_addr -and $pci_addr -le $max_addr ) 
    {
     $new_addr = ( int2hex( $pci_addr - $min_addr ));
     $slot     = ( int2hex( hex2int( $key ) ) ).substring(6,2);# Last 2of8 Nibs
     $sub_slot = "0";# Default for non-PROM LocalBus
     $rts = ($slot + $sub_slot + $new_addr);# 44bit field now instead of 32bit
#    print( $slot );
#    print( $new_addr );
#    print( $rts );
    }
  }# foreach
  return @($rts );
}# mesa_slot_lookup()


##############################################
# Read the 32bit UNIX timestamp of the FPGA build
function timestamp( $args_array )
{
  $timestamp = (hex2int($timestamp));
  $rts += conv_unixtime2ascii( $timestamp );
  return @($rts );
}# timestamp()


###############################################################################
# SPI PROM Subroutines : These depend on spi_prom.v module
#  prom_id()          : Get Manufacturer and Size Info about PROM
#  prom_dump( addr )  : Read a PROM sector at addr
#  prom_erase( addr ) : Erase a sector at addr or "bulk"
#  prom_load( file )  : Load bit file to address 0x0, erasing sectors needed
###############################################################################
function prom_id( $args_array )
{

  $prom_cmd_id = 0x01; # Constants from spi_prom.v 
  $prom_cmd = ( int2hex( $prom_cmd_id ));
  $rts = spi_tx_ctrl( $prom_cmd );
  $rts = spi_rx_data( 1  );

  $prom_deepsleep = 0xFFFFFFFF;
  if ( (hex2int($rts)) -eq $prom_deepsleep )
  {
   # New
   $prom_rel_powerdown = 0x09; # Constants from spi_prom.v 
   $prom_cmd = ( int2hex( $prom_rel_powerdown ));
   $rts = spi_tx_ctrl( $prom_cmd );

   $prom_cmd_id = 0x01; # Constants from spi_prom.v 
   $prom_cmd = ( int2hex( $prom_cmd_id ));
   $rts = spi_tx_ctrl( $prom_cmd );
   $rts = spi_rx_data( 1  );
  }
  

  # JEDEC Bit Positions for Manufacture and PROM size
  $prom_mfr  = 0x000000FF;
  $prom_size = 0x00FF0000;
  $prom_mfr  = ( (hex2int($rts)) -band $prom_mfr  );
  $prom_size = ( (hex2int($rts)) -band $prom_size );

  # If Micron, Display Micron name and the PROM Density
  if ( $prom_mfr -eq 0x00000020 ) 
  { 
    $rts += "`nMicron "; 
    $prom_size = ( $prom_size / 0x10000 );# >> 16
    $prom_size = ( [Math]::Pow(2, $prom_size) );
    $prom_size = [int]( $prom_size / 131072 );
    $prom_size = ( (int2str($prom_size)) + ("Mb") );
    $rts += $prom_size; 
    return @($rts);
  } 
  else
  {
    return $False;
  }
}# prom_id()


##############################################
# Read the 32bit UNIX timestamp of the FPGA build
function prom_vers( $args_array )
{
  $prom_cmd_rd_timestamp = 0x02; # Constants from spi_prom.v 
  $prom_cmd = ( int2hex( $prom_cmd_rd_timestamp ));
  $rts = spi_tx_ctrl( $prom_cmd );
  $rts = "FPGA Build Timestamp`n";
  $timestamp = spi_rx_data( 1  );
  $rts += ($timestamp + "`n");
  $timestamp = (hex2int($timestamp));
  $rts += conv_unixtime2ascii( $timestamp );
  return @($rts );
}# prom_vers()

##############################################
# Read the PROM Slot Size, extension of FPGA timestamp Command
function prom_slot( $args_array )
{
  ( $slot ) = $args_array; 
  $slot = (hex2int($slot));
  $prom_cmd_rd_timestamp = 0x02; # Constants from spi_prom.v 
  $prom_cmd = ( int2hex( $prom_cmd_rd_timestamp ));
  $rts = spi_tx_ctrl( $prom_cmd );
  $rts_str = spi_rx_data( 2  );# 1st DWORD is Timestamp, 2nd Slot Size
  $data = ($rts_str.substring(8,8));# Parse 2nd DWORD 
  $slot_size = (hex2int($data));
  $slot_offset = ( $slot * $slot_size );
  print( $slot        );
  print( $slot_size   );
  print( $slot_offset );
  return ( $slot_offset );
}# prom_slot()


function conv_unixtime2ascii( $timestamp ) 
{
  $rts = [timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').`
   AddSeconds($timestamp))
  return $rts;
}


##############################################
# Either Erase entire PROM or a single sector
function prom_erase( $args_array )
{
  ( $mode ) = $args_array; # "bulk" or "00000000" address for sector
  $ctrl_addr = $prom_ctrl_addr;
  if ( $bd_protocol -eq "mesa" )
  {
   $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
   $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));
   $ctrl_addr = ($mesa_prom_slot+$mesa_prom_subslot+$ctrl_addr);
  }
  # Constants from spi_prom.v 
  $prom_cmd_erase_bulk   = 0x05;
  $prom_cmd_erase_sector = 0x06;
  if ( $mode -eq "bulk" )
  {
    $erase_cmd = ( int2hex( $prom_cmd_erase_bulk ));# Bulk Erase   
    $timeout_cnt = 40000;
  }
  else
  {
    $erase_addr = $mode;
    $erase_raw_cmd = ( int2hex( $prom_cmd_erase_sector ));# Sector Erase   
    $erase_cmd = ($erase_addr.substring(0,6) + $erase_raw_cmd.substring(6,2));
    $timeout_cnt =  10000;
  }

  # This takes about 3 seconds for M25P20, 5 min for 256Mb PROM
  $sw = [Diagnostics.Stopwatch]::StartNew();# Measure this whole process
# New 10_19_2015 : Removed array reference
# $rts = spi_tx_ctrl( @( $erase_cmd ) );# Bulk Erase   
  $rts = spi_tx_ctrl(    $erase_cmd   );# Bulk Erase   
  $bit_status = 0x2; $i = 0;
# while ( $bit_status -eq 0x2 -and $i -ne $timeout_cnt )
  while ( $bit_status -eq 0x2 ) 
  {
    $rts = bd_cmd( @( "r", $ctrl_addr, "0" ) ); # print( $rts );
    $bit_status = ( (hex2int( $rts )) -band 0x00000002 ); # WIP Bit
    $i = $i + 1;
  }
  $sw.Stop()
  $duration = ([int] $sw.ElapsedMilliseconds)/1000;# ms to s conversion
# if ( $i -eq $timeout_cnt ) 
# { 
#   status("ERROR: Erase Timeout Abort"); 
#   print("ERROR: Erase Timeout Abort"); 
#   return;
# }
  print( (" prom_erase() took " + $duration + "s"));
  return @( (" prom_erase() took " + $duration + "s"));
}# prom_erase()


########################################################
# prom_dump( addr ) : Read 256 Bytes from PROM at addr
# Note: Address must start on 256 byte boundry
function prom_dump( $args_array )
{
  ( $addr ) = $args_array; 
  $prom_cmd_rd_buffer = 0x03; # Constants from spi_prom.v 
  $prom_cmd = ( int2hex( $prom_cmd_rd_buffer ));
  $prom_cmd = $prom_cmd.substring(6,2);
  $addr = int2hex( (hex2int( $addr )));# Make 8 nibbles
  $start_addr = $addr.substring(0,6);  # Lop 2 LSB nibbles off
  # New 10_19_2015 : Removed array reference
  # spi_tx_ctrl( @( ( $start_addr + $prom_cmd ) ) );# Read Buffer
  spi_tx_ctrl( ( $start_addr + $prom_cmd ) );# Read Buffer
  $rts = spi_rx_data( 64 );# Read 64 DWORDs
  return @($rts);
}# prom_dump()


###################################################################
# prom_load( filename ) : Load *.bit to PROM addr, erasing sectors
#  if the addr is a single nibble, treat it as a PROM slot instead
#  of address and read the slot size using the prom timestamp command
#  Then multiply the slot number by the slot size
function prom_load( $args_array )
{
  ( $filename, $prom_wr_addr ) = $args_array; 
   if ( $prom_wr_addr -eq "" ) { $prom_wr_addr = "00000000"; }
   $dbg = $True;

   $ctrl_addr = $prom_ctrl_addr;
   $data_addr = $prom_data_addr;
   if ( $bd_protocol -eq "mesa" )
   {
    $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
    $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));
    $ctrl_addr = ($mesa_prom_slot+$mesa_prom_subslot+$ctrl_addr);
    $data_addr = ($mesa_prom_slot+$mesa_prom_subslot+$data_addr);
   }

   # Check to see if slot num instead of address and then lookup address
   # given the PROM slot size.
   if ( (( $prom_wr_addr.Length) -eq 1 ) -and ( $prom_wr_addr -ne "0" ) )
   {
    print(" prom_load to slot $prom_wr_addr");
    $slot = ( str2int( $prom_wr_addr  ) );
    $addr = prom_slot( @( $slot ) );
    $prom_wr_addr = ( int2hex( $addr ) );
   }
   print(" prom_load $filename to $prom_wr_addr");
#  return;

   # Constants from spi_prom.v 
   $prom_stat_spi_busy          = 0x80;
   $prom_stat_mosi_polling_reqd = 0x40;
   $prom_stat_mosi_rdy          = 0x20;
   $prom_stat_miso_rdy          = 0x10;
   $prom_stat_state_wr          = 0x08;
   $prom_stat_unlocked          = 0x04;
   $prom_stat_prom_wip          = 0x02;
   $prom_stat_spi_busy          = 0x01;
   $prom_cmd_wr_prom            = 0x07;
   $sw = [Diagnostics.Stopwatch]::StartNew();# Measure this whole process
   $mod_ext  = [System.IO.Path]::GetExtension( $filename );
   $fs = new-object IO.FileStream($filename, [IO.FileMode]::Open);
   if ( $mod_ext -eq ".bit" -or $mod_ext -eq ".bin" )
   {
     $byte_array = new-object byte[] 256;
     $bin_reader = new-object IO.BinaryReader($fs);# top.bit
     $file_size  = ( (Get-Item $filename).length );
     $sectors    = ($file_size / 65536);
     $sectors    = ( [Math]::Ceiling( $sectors ) );# Round Up
     $file_size  = ($file_size / 1024);
     $file_size  = ( [Math]::Ceiling( $file_size ) );# Round Up
     status("");
     status(("loading "+$file_size+"KB or "+$sectors+" 64KB sectors") );

     # PROM Write Buffer is 256 Bytes. 
     # Sit in loop reading 256 bytes from file until done. Pad if less than 256
     $k = 0; $kk = 0; $poll_reqd = 0; $sc = 0;
     $prom_wr_addr = ( hex2int( $prom_wr_addr ) );

     # toss 1st 88 bytes as Xilinx doesn't expect them in PROM
     # *.bit is Xilinx, *.bin is Lattice
     if ( $mod_ext -eq ".bit" )
     {
      ($bytes_read = $bin_reader.Read($byte_array, 0, 88 ));
     }

     while ( ($bytes_read = $bin_reader.Read($byte_array, 0, 256)) -gt 0 )
     {
       $k+=1;# Payload counter 1-256 and repeat ( a sector )

       # If 1st 256 Bytes of a Sector, Erase Sector and issue Write Command
       if ( $k -eq 1 )
       {
         if ( $sc -ne 0 )
         {
          $sw.Stop()
          $duration_ms = [int](($sw.ElapsedMilliseconds));# ms 
          status ( ("sector " + $sc + " burst took " + $duration_ms + "ms"));
          $rate = [int]( 65535 / $duration_ms );
          status ( ("Write Xfer rate of " + $rate + " KByte/Sec "));
         }
         $sc+=1;# Sector Counter
         status(( "Erasing Sector $sc of $sectors "+(int2hex($prom_wr_addr))));
         $rts = prom_erase( int2hex( $prom_wr_addr ) );
         status(( "Writing" ));
         $wr_cmd = ( int2hex( $prom_cmd_wr_prom ));
         $prom_cmd=( (int2hex($prom_wr_addr)).substring(0,6) +
                      $wr_cmd.substring(6,2));
         $rts = spi_tx_ctrl( $prom_cmd );
         $sw2 = [Diagnostics.Stopwatch]::StartNew();# Measure this whole process
       }

       # If end of file has less than 256 bytes, pad it up to 256
       if ( $bytes_read -ne 256 )
       {
        $pad_bytes  = new-object byte[] ( 256 - $bytes_read );
        $byte_array = ( $byte_array[0 .. ($bytes_read-1)] + $pad_bytes );
       }

       # Convert Binary Byte Array to 64 DWORD Backdoor Burst in hex 
       $byte_str = [BitConverter]::ToString( $byte_array );
       $byte_str = ($byte_str -replace("-",""));# "00-01-" to "0001"
       $data = "";
       # Read out 8 nibbles at a time to build DWORD bursts with " " between
       for ( $j = 0; $j -lt 512; $j+=8 )
       {
         $data = ($data + ($byte_str.substring($j,8)) + " "); 
       }

       # Write Status as KB counter
       if ( $k -eq 128 -or $k -eq 256 ) {$kk+=32;status((int2str($kk))+"KB");}

       # Send payload if the MOSI Buffer is Free
       if ( $poll_reqd -ne 0x0 ) { $rts = spi_wait_for_mosi_free(""); }

       # Original Poke only BD_SHELL sent bursts of 64 DWORDs ( 256 Bytes ).
       # MesaBus has payload limit of 255 Bytes, so split 256 bytes into
       # 2 128 Byte payloads ( +4 Addr Bytes = 132 payload bytes total )
#      $data = $data.Substring(0,$data.Length-1);# Remove trailing " "
#      $rts = spi_tx_data( @( $data ) );
       $data1 = $data.Substring( 0*9, (32*9)-1);# 1st 32 DWORDs
       $rts = spi_tx_data( ( $data1 ) );
       $data2 = $data.Substring(32*9, (32*9)-1);# 2nd 32 DWORDs
       $rts = spi_tx_data( ( $data2 ) );

# HERE8
# New 10_19_2015 : Removed array reference
#      $data1 = $data.Substring(0*9, 16*9);
#      $data2 = $data.Substring(16*9,16*9);
#      $data3 = $data.Substring(32*9,16*9);
#      $data4 = $data.Substring(48*9,16*9);
#      $data1 = $data1.Substring(0,$data1.Length-1);# Remove trailing " "
#      $data2 = $data2.Substring(0,$data2.Length-1);# Remove trailing " "
#      $data3 = $data3.Substring(0,$data3.Length-1);# Remove trailing " "
#      $data4 = $data4.Substring(0,$data4.Length-1);# Remove trailing " "
#      return ( ("prom_load Aborted") );
#      $rts = spi_tx_data( ( $data1 ) );
#      $rts = spi_tx_data( ( $data2 ) );
#      $rts = spi_tx_data( ( $data3 ) );
#      $rts = spi_tx_data( ( $data4 ) );
#      if ( $dbg )
#      {
#       print("-------");
#       print( $data1 );
#       print( $data2 );
#       print( $data3 );
#       print( $data4 );
#       $dbg = $False;
#      }

       # After sending 1st 2 payloads (Ping,Pong) read polling_reqd status bit
       # It will be set if PROM was being written with Ping while Pong loaded
       # Use this as an indicator that CPU access is fast and we should poll.
       if ( $k -eq 2 -and $sc -eq 0 ) 
       {
         $prom_stat_mosi_rdy = 0x20;
         $rts = bd_cmd( @( "r", $ctrl_addr, "0"   ) );
         $poll_reqd = ( (hex2int($rts)) -band $prom_stat_mosi_polling_reqd );
       }

       # Increment Byte Counter and Check for End of Sector count. Status
       $prom_wr_addr += 256;
       if ( $k -eq 256 )  { $k = 0 ; }
     }# while ( $bin_reader )
     $bin_reader.Close();
   }# if ( $mod_ext -eq ".bit" )
   $sw.Stop()
   $duration = [int](($sw.ElapsedMilliseconds)/1000);# ms to s conversion
   $mins     = [int](($duration)/60);# s to m conversion
   return ( ("prom_load took " + $duration + "s ( " + $mins + "m )"));
}# prom_load


######################################################
# Calculate the address to use for PROM Control and Data
# prom_ctrl = base_addr+prom_addr+0x0
# prom_data = base_addr+prom_addr+0x4
function calc_prom_addr( $args_array )
{
  $base_addr             = hash_get(@($var_hash,"base_addr"));
  $base_addr             = (hex2int( $base_addr ));
  $prom_addr             = hash_get(@($var_hash,"prom_addr"));
  $global:prom_ctrl_addr = int2hex( $base_addr + (hex2int( $prom_addr )) +0);
  $global:prom_data_addr = int2hex( $base_addr + (hex2int( $prom_addr )) +4);
}

# These spi_* functions interface via Backdoor to 2 LocalBus mapped registers
# connected to spi_prom.v that then interfaces via SPI to a SPI PROM.
# Interface is a 32bit LB Command Register and a 32bit LB Streaming Data Reg
# Note: For Mesa - the 4bit Sub-Slot gets changed from 0 to E
# HERE5
function spi_tx_ctrl( $args_array )
{
 ( $spi_cmd ) = $args_array;
#print("spi_tx_ctrl()");
#print( $spi_cmd );
#print( ( $spi_cmd.Length ) );
 $ctrl_addr = $prom_ctrl_addr;
 if ( $bd_protocol -eq "mesa" )
 {
  $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
  $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));
  $ctrl_addr = ($mesa_prom_slot+$mesa_prom_subslot+$ctrl_addr);
 }

 # Sit in a loop until SPI_BUSY is cleared
 $bit_status = 0x1; $i = 0;
 while ( $bit_status -eq 0x1 -and $i -lt 1000 )
 {
   $rts = bd_cmd( @( "r", $ctrl_addr, "0"   ) );
   $bit_status = ( (hex2int( $rts )) -band 0x00000001 ); # SPI_BUSY Bit
   $i +=1;
 }
 if ( $i -eq 1000 ) { print("ERROR: spi_tx_ctrl() Timeout Abort"); return; }

 # SPI Channel is free, so send the command 
 $rts = bd_cmd( @( "w", $ctrl_addr, $spi_cmd ) );
}


function spi_wait_for_mosi_free()
{
 $ctrl_addr = $prom_ctrl_addr;
 if ( $bd_protocol -eq "mesa" )
 {
  $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
  $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));
  $ctrl_addr = ($mesa_prom_slot+$mesa_prom_subslot+$ctrl_addr);
 }
 # Sit in a loop until MOSI Buffer Free Bit is set 
  $prom_stat_mosi_rdy = 0x20;
  $bit_status = 0; $i = 0;
  while ( $bit_status -eq 0x0 -and $i -lt 1000 )
  {
   $rts = bd_cmd( @( "r", $ctrl_addr, "0"   ) );
   $bit_status = ( (hex2int( $rts )) -band $prom_stat_mosi_rdy );# MOSIBufFree
   $i +=1;
  }
 if ( $i -eq 1000 ) { print("ERROR: spi_tx_data() Timeout Abort"); return; }
}


function spi_tx_data( $args_array )
{
 ( $payload_data ) = $args_array;
 $data_addr = $prom_data_addr;
 if ( $bd_protocol -eq "mesa" )
 {
  $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
  $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));
  $data_addr = ($mesa_prom_slot+$mesa_prom_subslot+$data_addr);
 }
 # MOSI Buffer is free, so send the payload 
 $rts = bd_cmd( @( "W", $data_addr, $payload_data ) );# Write Repeat
 # HERE6
 return @($rts);
}# spi_tx_data


function spi_rx_data( $args_array )
{
 ( $num_dwords ) = $args_array;
 $data_addr = $prom_data_addr;
 if ( $bd_protocol -eq "mesa" )
 {
  $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
  $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));
  $data_addr = ($mesa_prom_slot+$mesa_prom_subslot+$data_addr);
 }
  $data = ( int2hex( $num_dwords-1 ) );
  $rts = bd_cmd( @( "k", $data_addr, $data ) );# Read Repeat
  return @($rts);
}


function invoke_file( $args_array )
{
 ( $file ) = $args_array;
 print "invoke_file( $file )";
 if ( Test-Path( $file ) )
 {
  try
  {
    Invoke-Item $file;# Edit file with Windows default for this type
  }
  catch
  {
    status(("ERROR Invoke " + $file) );
    $nl = [Environment]::NewLine
    $msg = "OS failed to Invoke $file.$nl" +
           "Is the filetype associatedi with an application?";
    [void][System.Windows.Forms.MessageBox]::Show($msg);
  }
 }
 else
 {
   status("Warning: File $file does not exist" );
 }
}# invoke_file()


function mk_obj( $a )
{
 $obj = $false;
 if     ( $a -eq "Label"    ){ $obj=New-Object System.Windows.Forms.Label;    }
 elseif ( $a -eq "Button"   ){ $obj=New-Object System.Windows.Forms.Button;   }
 elseif ( $a -eq "TextBox"  ){ $obj=New-Object System.Windows.Forms.TextBox;  }
 elseif ( $a -eq "RichTextBox")
                         { $obj=New-Object System.Windows.Forms.RichTextBox;  }
 elseif ( $a -eq "ComboBox" ){ $obj=New-Object System.Windows.Forms.ComboBox; }
 elseif ( $a -eq "CheckBox" ){ $obj=New-Object System.Windows.Forms.CheckBox; }
 elseif ( $a -eq "Slider"   ){ $obj=New-Object System.Windows.Forms.TrackBar; }
 elseif ( $a -eq "Splitter" ){ $obj=New-Object System.Windows.Forms.Splitter; }
 elseif ( $a -eq "RadioButton" )
    { $obj=New-Object System.Windows.Forms.RadioButton; }
 else   { print(" Invalid! $a " ); }
 return $obj;
}

function sz_obj( $args_array )
{
  ( $obj, $text, $x, $y, $w, $h ) = $args_array;
  $bh = 23;
  $bw = 10;
  $m  = 1;
  $uh = $bh + $m;
  $uw = $bw + $m;
  $bx = $m/2 + ($uw * $x );
  $by = $m/2 + ($uh * $y );
  $bw = ( $uw * $w ) - $m;
  $bh = ( $uh * $h ) - $m;
  # Attempt to align labels with buttons by offsetting Y and making narrow
  if ( $obj.GetType() -eq [System.Windows.Forms.Label] )
  {
   $by = $by + 2;
   $bh = $bh - 3;
   $bw = $bw * 1;
  }
  $obj.Location = New-Object System.Drawing.Size($bx,$by);
  $obj.Size     = New-Object System.Drawing.Size($bw,$bh);
  $obj.TabStop  = $true;
  $obj.Text     = $text;
}# sz_obj()


function create_ini( $args_array )
{
( $filename ) = $args_array;
 $file_size  = ( (Get-Item $filename).length );
 if ( ( Test-Path( $filename ) ) -and
      ( $file_size -gt 0  )  ) { return $False; } # Don't Create if Exists
 if ( ( Test-Path( $filename ) ) -and
      ( $file_size -eq 0  )  )
 {
  print("WARNING: Deleting 0-length corrupted INI file and creating new one!");
 }
$a = @();
$a +="####################################################################### ";
$a +="####################################################################### ";
$a +="startup_help      = 0";
$a +="window_width      = 800";
$a +="window_height     = 800";
$a +="bd_protocol       = poke                  # poke or mesa";
$a +="bd_connection     = usb                   # usb or tcp to Hardware ";
$a +="tcp_port          = 21567                 # TCP Socket port";
$a +="tcp_ip_addr       = 127.0.0.1             # TCP Socket IP Address";
$a +="usb_port          = DLL                   # FTDI USB Port DLL or COM4";
$a +="base_addr         = 00000000              # Base Address to add";
$a +="timestamp_addr    = 00000000              # Address to UNIX timestamp";
$a +="prom_addr         = 000010a0              # Address for SPI_PROM";
$a +="log_en            = 1                     # Log to file";
$a +="python_exe        = python.exe            # Python Executable";
$a +="read_format       = columns   {data,addr_data,columns} ";
$a +="mesa_slot         = 00,00000000,00FFFFFF  # Slot-0 Range";
$a +="mesa_prom_slot    = 00                  # Mesa Slot of PROM";
$a +="mesa_prom_subslot = E                   # Mesa SubSlot of PROM";
 Add-content $filename -value $a;
 return $True;
}

#  $mesa_prom_slot    = (hash_get(@($var_hash,"mesa_prom_slot"  )));
#  $mesa_prom_subslot = (hash_get(@($var_hash,"mesa_prom_subslot"  )));


###############################################################################
# Lookup an item in the hash table 
function hash_get( $args_array )
{
 ( $hash, $key ) = $args_array;
 if ( $key -eq "" -or $key -eq $false ) { return $false; }
#print ("->"+$key+"<-");
 if ( $hash.ContainsKey( $key ) )
 {
  $value = ( $hash.Get_Item( $key ) );
 } 
 else { $value = $false; }
 return $value;
}# hash_get()


###############################################################################
# Add an item to a hash table. 
function hash_set( $args_array )
{
 ( $hash, $key, $value ) = $args_array;

 # Value may be an array, so look to see and replace if so
 $val = hash_get( @($hash, $value) );
 if ( $val -ne "" ) { $value = $val; }

 $hash.Set_Item( $key, $value );
 return;
}# hash_set()

#
#                            End of Application Code
# --------------------------------------------------------------------------- #
###############################################################################

function set_ini_globals( $args_array )
{
#$global:print_log_en         = (hash_get("print_log_en"));
 $global:connection          = (hash_get(@($var_hash,"connection")));
}

###############################################################################
# event_keydown() : Gets called whenever any key is pressed. Most keys are 
#  ignored and the RichTextBox automatically adds them to the screen. This
#  function looks for special keys like <Enter>,<Up>,<Down> and "Handles" them
#  to prevent standard behavior.
#  <Enter>     : Process a command on the command line ( last line ).
#  <Up>,<Down> : Scroll command history and replace the command line.
#
###############################################################################
function event_keydown( $args_array )
{
 ( $obj_txt, $obj, $_ ) = $args_array;

  # Parse the text of the RTB into a list of lines. cmd_line is last one
  $nl = [Environment]::NewLine
  $lines = $obj.Text.split($nl);# Line split
  $cmd_line = $lines[ $lines.length -1 ];

  if ( $_.KeyCode -eq "Enter" ) 
  { 
   $_.Handled = $true; # Handle <Enter> to Prevent <CR> insertion after this 

   # Parse Command without Prompt
   $cmd = ($cmd_line.substring($bd_prompt.length)); # Strip "bd>"

   # Check for Bang ! and BangBang !! and replace command with a prior
   if ( $cmd[0] -eq "!" )
   {
    $i = $cmd.substring(1);# Everything after 1st Bang !
    if ( $cmd[1] -eq "!" )  { $i = $h_cnt; }
    $cmd      = hash_get( @( $hist_hash, (int2str($i)) ));
    $cmd_line = ($bd_prompt+$cmd);
    $obj_rtb.AppendText($nl);# ??
   }

   # Process Command 
   $rts_list = proc_human_cmd( @( $cmd, $h_cnt ) );

   # Store this new command into hist_hash
   $global:h_cnt++;# History Counter
   hash_set( @( $hist_hash, (int2str($h_cnt)), $cmd ) );

   # Erase Command Line Text
   if ( $obj_rtb.Text -ne "" )
   {
    $obj_rtb.SelectionStart  = $obj_rtb.Text.Length - $cmd_line.length;
    $obj_rtb.SelectionLength = $cmd_line.length;
    $obj_rtb.SelectedText = ""; 
   }

   # Append old command with history counter on line above
   $new_line = ((int2str($h_cnt))+">"+$cmd_line.substring($bd_prompt.length));
   $obj_rtb.AppendText( $new_line );

   display_results( $rts_list );
   display_prompt("");# ie "bd>"
   $global:key_arrow_i = -1;# This makes 1st up Arrow go to 0 ( last command )
  }# If "Enter"

  # Prevent backing over the bd> prompt
  if ( $_.KeyCode -eq "Back" -and $obj_rtb.Text.Length -eq $obj_rtb_len )
  {
    $_.Handled = $true; 
  }

  # Handle Up and Down Arrow for line replacement. Inc/Dec key_arrow_i and
  # range check, then replace cmd_line with a cmd from history
  if ( $_.KeyCode -eq "Up" -or $_.KeyCode -eq "Down" )
  {
    $_.Handled = $true; 
    if ( $_.KeyCode -eq "Up"   )             { $global:key_arrow_i +=1; }
    if ( $_.KeyCode -eq "Down" )             { $global:key_arrow_i -=1; }
    if ( $global:key_arrow_i -lt 0 )         { $global:key_arrow_i  =0; }
    if ( $global:key_arrow_i -gt ($h_cnt-1)) { $global:key_arrow_i -=1; }
    $h_cmd = hash_get( @( $hist_hash, (int2str($h_cnt-$key_arrow_i)) ) );

    # Erase the Command Line Text
    $obj_rtb.SelectionStart  = $obj_rtb.Text.Length - $cmd_line.length;
    $obj_rtb.SelectionLength = $cmd_line.length;
    $obj_rtb.SelectedText = ""; 
    $obj_rtb.AppendText( ( $bd_prompt+$h_cmd ) );
  }

}# event_keydown()

function display_clear( $args_array )
{
 $foo = $obj_rtb.Text = "";
 $foo = $obj_rtb.Focus();
}

function display_results( $args_array )
{
  $rts_list = $args_array;
  # Display Command Result
  $sleep = 0;
  if ( $voice_en ) { $voice_obj = new-object -com SAPI.SpVoice; }
  foreach( $rts in $rts_list )
  {
   $foo = $obj_rtb.AppendText( ($nl+$rts) );
   $foo = $obj_rtb.Focus();# Fixes scrolling somehow
   event_refresh;
#  if ( $voice_en ) { $voice_obj.Speak( $rts , 1 ) | out-null; }
#  if ( $the_end  ) { $sleep+=1; start-sleep -s $sleep; }
   if ( $voice_en ) { $voice_obj.Speak( $rts , 1 ); }
   if ( $voice_en ) { $sleep+=1; start-sleep -s $sleep; }
  }
  if ( $the_end ) { event_exit; }
 $global:voice_en = $false;
}

function display_prompt( $args_array )
{
   # Append new Prompt
   $rts = $obj_rtb.AppendText( $nl+ $bd_prompt );
   $rts = $obj_rtb.Focus();# Fixes scrolling somehow
   $obj_rtb.SelectionStart  = $obj_rtb.Text.Length;
   # $obj_rtb.ScrollToCaret();
   $global:obj_rtb_len = $obj_rtb.Text.Length;# Length of Text to Prompt
}

#############################################################################
# popup_message() : Popup a standard dialog box. buttons may be:
#             OK, OKCancel, AbortRetryIgnore,YesNoCancel, YesNo, RetryCancel
function popup_message( $args_array )
{
  ( $title, $message, $buttons ) = $args_array;
  $rts = [system.windows.forms.messagebox]::Show($message,$title,$buttons);
  return $rts;
}

##############################################################################
# popup_openfile() : Popup a OpenFile dialog box and return filename
# $filter = "HLIST Files (hlist.txt)|hlist.txt";
function popup_openfile( $args_array )
{
  ( $title, $filter ) = $args_array;
  $f=New-Object System.Windows.Forms.OpenFileDialog;
# $f.InitialDirectory='%cd%';
  $cwd_path = get-location;
  $f.InitialDirectory= $cwd_path;
  $f.Title  = $title;
  $f.Filter = $filter;
  $f.showHelp=$true;
# $f.StartPosition = "CenterParent";
  $f.ShowDialog()|Out-Null;
  return $f.FileName;
}



#############################################################################
# popup_getvalue() : .NET doesnt come with a standard text input popup, but
#                  the VisualBasic lib that comes with does - so use it.
function popup_getvalue( $args_array )
{
  ( $title, $message, $default_value ) = $args_array;
 [void][System.Reflection.Assembly]::LoadWithPartialName( 
                                                     "Microsoft.VisualBasic") 
 $rts =  
        [Microsoft.VisualBasic.Interaction]::InputBox( 
        $message, $title, $default_value,  
        $obj_form.Left + 50, $obj_form.Top + 50);
  return $rts;
}

function popup_select( $args_array )
{
  ( $title, $message, $items ) = $args_array;
 $global:user_form = New-Object System.Windows.Forms.Form;
 $user_form.StartPosition = "CenterScreen";
 $user_form.AutoSize      = $True;
 $user_form.AutoSizeMode  = "GrowAndShrink";
#$user_form.Width         = 320;
#$user_form.Height        = 240;
 $user_form.MinimizeBox   = $False;
 $user_form.MaximizeBox   = $False;
 $user_form.SizeGripStyle = "Hide";
 $user_form.WindowState   = "Normal";
#$user_form.Topmost       = $True;
 $user_form.ShowIcon      = $False;
 $user_form.Text          = $title;

 $user_objs = @();
 $y = 0;

 if ( $message -ne "" )
 {
  $x = 0 ; $user_objs += mk_obj("Label");
  sz_obj( @($user_objs[-1], $message,$x,$y, 15, 1 ) );
  $y+=1;
 }

 $x = 0 ; $user_objs += mk_obj("ComboBox");
 sz_obj( @($user_objs[-1], "OK",$x,$y, 15, 1 ) );
 $global:combo_obj = $user_objs[-1];
 $combo_box = ($user_objs.length-1);

 $y+=1;
 $x=1; $user_objs += mk_obj("Button");
 sz_obj( @($user_objs[-1], "OK",$x,$y, 7.0, 1 ) );
 $ok_button = ($user_objs.length-1);

 $x+= 8.0 ; $user_objs += mk_obj("Button");
 sz_obj( @($user_objs[-1], "Cancel",$x,$y, 7.0, 1 ) );
 $cancel_button = ($user_objs.length-1);

 $obj = $user_objs[$combo_box];
 foreach ( $each in $items )
 {
  if ( $each -ne "" )
  {
   [void]$obj.Items.Add( $each );
  }
 }
 $obj.DropDownStyle = "DropDownList";# Makes the text ReadOnly
 $obj.SelectedIndex = 0;# Default

 foreach ( $obj in $user_objs ) { $user_form.Controls.Add($obj); }

 # Bind the buttons. Note Apply keeps window open
 [void]$user_objs[$ok_button].Add_Click(
   { $txt="OK"; $user_form.Close();});
 [void]$user_objs[$cancel_button].Add_Click(
   { $txt="CANCEL"; $combo_obj.SelectedText=""; $user_form.Close();});
#[void]$user_objs[$combo_box].Add_SelectedIndexChanged(
#      { event_combo_box_change( $users_objs[$combo_box] ); } );
 [void]$user_form.ShowDialog();# 
 return $rts;
}# popup_select

#function event_combo_box_change( $args_array )
#{
# $obj = $args_array;
# $global:combo_txt = $obj.SelectedText;
#}

function beep( $args_array )
{
 [void][System.Reflection.Assembly]::LoadWithPartialName( 
                                                     "Microsoft.VisualBasic") 
 [Microsoft.VisualBasic.Interaction]::Beep();
}



###############################################################################
# main() : 1st thing to run. Setup global variables ( egads ) and load ini
# create Windows Forms objects and show the form ( and sit in event loop ).
#$global:obj_status  = create_obj_status;
 $global:pwd_path = get-location;
 $global:vers        = "03.18.2016";
 $global:author      = "khubbard";
 $global:log_file = join-path -path $pwd_path -childpath "bd_shell_log.txt";
 $global:man_file = join-path -path $pwd_path -childpath "bd_shell_manual.txt";
 $global:ini_file = join-path -path $pwd_path -childpath "bd_shell.ini";

 if ( Test-Path $log_file ) { Clear-content $log_file; }
 $global:print_log_en = 0;
 $global:bd_prompt = "bd>";
 $global:the_end = $false;
 $global:voice_en = $false;
 $global:fatal_err = "";
 $global:var_hash  = @{};
 $global:mesa_slot_hash  = @{};
 $global:hist_hash = @{};
 $global:cmd_hash  = @{ "r"           = "bd";   
                        "w"           = "bd";   
                        "bs"          = "bd";   
                        "bc"          = "bd";   
                        "read"        = "bd";   
                        "write"       = "bd";   
                        "bitset"      = "bd";   
                        "bitclr"      = "bd";   
                        "rt"          = "bd";   
                        "bitclear"    = "bd";   
                        "configure"   = "bd";   
                        "uart_load"   = "bd";   
                        "prom_erase"  = "bd";   
                        "prom_load"   = "bd";   
                        "prom_boot"   = "bd";   
                        "prom_root"   = "bd";   
                        "prom_bist"   = "bd";   
                        "prom_dump"   = "bd";   
                        "prom_id"     = "bd";   
                        "prom_vers"   = "bd";   
                        "prom_status" = "bd";   
                        "timestamp"   = "bd";   
#                       "mesa_dbg"    = "bd";   
                        "mesa_id"     = "bd";   
                        "mesa_on"     = "bd";   
                        "mesa_off"    = "bd";   
                        "mesa_boot1"  = "bd";   
                        "mesa_boot2"  = "bd";   
                        "mesa_cmd"    = "bd";   
                        "pwd"         = "unix";
                        "cp"          = "unix";
                        "rm"          = "unix";
                        "mv"          = "unix";
                        "mkdir"       = "unix";
                        "diff"        = "unix";
                        "more"        = "unix";
                        "vi"          = "unix";
                        "ls"          = "unix"  
                        "cd"          = "unix"  
                      }; 
 apply_font( @("Courier New", 11 ) );
 $global:h_cnt = 0;
 $global:last_cmd = "";
 $global:socket_open = $false;
 $global:key_arrow_i = 0;
 $global:dll_loaded = $False;
 $global:org_path = get-location; # Directory we launched, where DLL should be

 # Generate some default files if they don't exist
 $new_ini = create_ini(    @("bd_shell.ini") );
 load_ini_file( @( $ini_file ) );# The root ini file
 create_manual( @($man_file) );

 # Create the Windows Form and the Widgets
 $global:obj_form = create_form( "" );
 $global:obj_rtb  = mk_obj("RichTextBox");
 sz_obj( @( $obj_rtb, "", 0,0,20,20 ) );
 $obj_rtb.Dock = "Fill";
 $obj_rtb.Font = $obj_font;
# $obj_rtb.AllowDrop = $true;

 $nl = [Environment]::NewLine
#$obj_rtb.AppendText($nl+"bd>");
 $obj_rtb.SelectionStart = $obj_rtb.Text.Length;
 $global:obj_rtb_len = $obj_rtb.Text.Length;# Length of Text to Prompt
 $obj_rtb.ScrollToCaret();
 $obj_rtb.Add_KeyDown({ event_keydown( @($obj_rtb.Text,$obj_rtb, $_) ) } );
#$obj_rtb.AcceptsTab    = $false;

 # Draw the Form, Add the Widgets 
 $obj_form.Controls.Add($obj_rtb);
#$obj_form.AllowDrop = $true;
 $obj_form.AutoSize = $true;
#$obj_form.AutoSizeMode = "GrowAndShrink";
 event_resize("");
#event_resize;

#$obj_form.SizeGripStyle = "Hide"; # Hide funky lower-right resize arrow
#$obj_form.MinimizeBox = $True; 
  $obj_form.FormBorderStyle = "SizableToolWindow";# vs None,FixedSingle,etc
 #$obj_form.ControlBox = $false;

 $h = (hash_get(@($var_hash,"startup_help")));
 if ( $h -eq "1" )
 {
  $rts_list = proc_human_cmd( @( "?",0 ) );
  display_results( $rts_list );
 }

 if ( $new_ini -eq $True )
 {
  display_results(@("WARNING: New bd_shell.ini created"));
  display_results(@("type env to check your new default environment"));
 }
  display_prompt("");

 if ( ( $args.Length -eq 2 ) -and $args[0] -eq "-c" )
 {
  # Process Command : Example %bd_shell.exe -c "source foo.txt"
  $cmd = $args[1];
  $cmd = ( $cmd -replace("'",""));# Remove '
  $cmd = ( $cmd -replace('"',''));# Remove "
  $rts_list = proc_human_cmd( @( $cmd, 0 ) );
  foreach ( $rts in $rts_list )
  {
   print( $rts ); 
  } 
 }
 else
 {
  $obj_form.ShowDialog();# Interactive GUI Mode
 }
 event_exit;
# EOF
