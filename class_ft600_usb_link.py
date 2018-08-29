#!python3
###############################################################################
# Source file : class_ft600_usb_link.py
# Language    : Python 3.3 or Python 3.5
# Author      : Kevin Hubbard
# Description : Access to hardware using USB3 with FT600   
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
#   01.01.2018 : khubbard : Created
###############################################################################




###############################################################################
# class for sending and receiving ASCII strings to FTDI FT600 chip 
class ft600_usb_link:
  def __init__ ( self ):
    try:
      import ftd3xx
      import sys
      if sys.platform == 'win32':
        import ftd3xx._ftd3xx_win32 as _ft
      elif sys.platform == 'linux2':
        import ftd3xx._ftd3xx_linux as _ft
    except:
      raise RuntimeError("ERROR: FTD3XX from FTDIchip.com is required");
      raise RuntimeError(
         "ERROR: Unable to import serial\n"+
         "PySerial from sourceforge.net is required for Serial Port access.");
    try:
      # check connected devices
      numDevices = ftd3xx.createDeviceInfoList()
      if (numDevices == 0):
        print("ERROR: No FTD3XX device is detected.");
        return False;
      devList = ftd3xx.getDeviceInfoList()

      # Just open the first device (index 0)
      devIndex = 0;
      self.D3XX = ftd3xx.create(devIndex, _ft.FT_OPEN_BY_INDEX);
      if (self.D3XX is None):
        print("ERROR: Please check if another D3XX application is open!");
        return False;

      # check if USB3 or USB2
      devDesc = self.D3XX.getDeviceDescriptor();
      bUSB3 = devDesc.bcdUSB >= 0x300;

      # validate chip configuration
      cfg = self.D3XX.getChipConfiguration();

    # process loopback for all channels
    except:
      raise RuntimeError("ERROR: Unable to open USB Port " );
    return;

  def get_cfg( self ):
    cfg = self.D3XX.getChipConfiguration();
    return cfg;

  def set_cfg( self, cfg ):
    rts = self.D3XX.setChipConfiguration(cfg);
    return rts;

  def rd( self, bytes_to_read ):
    bytes_to_read = bytes_to_read * 4;# Only using 8 of 16bit of FT600, ASCII
    channel = 0;
    rx_pipe = 0x82 + channel;
    if sys.platform == 'linux2':
      rx_pipe -= 0x82;
    output = self.D3XX.readPipeEx( rx_pipe, bytes_to_read );
    xferd = output['bytesTransferred']
    if sys.version_info.major == 3:
      buff_read = output['bytes'].decode('latin1');
    else:
      buff_read = output['bytes'];

    while (xferd != bytes_to_read ):
      status = self.D3XX.getLastError()
      if (status != 0):
        print("ERROR READ %d (%s)" % (status,self.D3XX.getStrError(status)));
        if sys.platform == 'linux2':
          return self.D3XX.flushPipe(pipe);
        else:
          return self.D3XX.abortPipe(pipe);
      output = self.D3XX.readPipeEx( rx_pipe, bytes_to_read - xferd );
      status = self.D3XX.getLastError()
      xferd += output['bytesTransferred']
      if sys.version_info.major == 3:
        buff_read += output['bytes'].decode('latin1')
      else:
        buff_read += output['bytes']
    return buff_read[0::2];# Return every other ch as using 8 of 16 FT600 bits

  def wr( self, str ):
    str = "~".join( str );# only using 8bits of 16bit FT600, so pad with ~
    bytes_to_write = len( str );# str is now "~1~2~3 .. ~e~f" - Twice as long
    channel = 0;
    result = False;
    timeout = 5;
    tx_pipe = 0x02 + channel;
    if sys.platform == 'linux2':
      tx_pipe -= 0x02;
    if ( sys.version_info.major == 3 ):
      str = str.encode('latin1');
    xferd = 0
    while ( xferd != bytes_to_write ):
      # write data to specified pipe
      xferd += self.D3XX.writePipe(tx_pipe,str,bytes_to_write-xferd);
    return;

  def close(self):
    self.D3XX.close();
    self.D3XX = 0;
    return;
