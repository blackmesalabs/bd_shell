#!python3
###############################################################################
# Source file : class_user.py      
# Language    : Python 3.3 or Python 3.5
# Author      : Kevin Hubbard
# Description : Example class for user defined add-on functions.
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
# Note: cmd_str is a text string from the command line "user1 foo" for example.
#       rts is a list of text strings that the CLI will display on completion.
# -----------------------------------------------------------------------------
# History :
#   01.01.2018 : khubbard : Created
###############################################################################
from common_functions import file2list;
from common_functions import list2file;



###############################################################################
# Example user class and methods.
#  user1 writes and reads a value from register 0x00
#  user2 reads value at register 0x04, increments it by +1 then reads again
class user:
  def __init__ ( self, lb_link ):
    self.bd = lb_link;
    # These are some constants from spi_prom.v
    self.user_reg_00 = 0x00000000;
    self.user_reg_04 = 0x00000004;

  def user1( self, cmd_str ):
    self.bd.wr( self.user_reg_00, [ 0x11223344 ] );
    rts = ["%08x" % ( self.bd.rd( self.user_reg_00,1 )[0] ) ];
    return rts;

  def user2( self, cmd_str ):
    rts = self.bd.rd( self.user_reg_04,1 );
    val = rts[0];
    val +=1;
    self.bd.wr( self.user_reg_04, [ val ] );
    rts = ["%08x" % ( self.bd.rd( self.user_reg_04,1 )[0] ) ];
    return rts;

  def user3( self, cmd_str ):
    rts = self.bd.rd( self.user_reg_00,2 );
    txt_rts = [ "%08x" % each for each in rts ];# list comprehension
    list2file( "bar.txt", txt_rts );
    rts = ["File bar.txt written"];
    return rts;

# EOF
