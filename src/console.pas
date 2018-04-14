{ ************************************************
  * Asuro
  * Unit: console
  * Description: Basic Console Output
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit console;

interface

uses
     util, 
     bios_data_area,
     multiboot,
     fonts;

type
    TColor = ( Black   = $0,
               Blue    = $1,
               Green   = $2,
               Aqua    = $3,
               Red     = $4,
               Purple  = $5,
               Yellow  = $6,
               White   = $7,
               Gray    = $8,
               lBlue   = $9,
               lGreen  = $A,
               lAqua   = $B,
               lRed    = $C,
               lPurple = $D,
               lYellow = $E,
               lWhite  = $F );

procedure init();
procedure clear();
procedure setdefaultattribute(attribute : uint32);

procedure disable_cursor;

procedure writechar(character : char);
procedure writecharln(character : char);
procedure writecharex(character : char; attributes: uint32);
procedure writecharlnex(character : char; attributes: uint32);

procedure Output(identifier : PChar; str : PChar);
procedure Outputln(identifier : PChar; str : PChar);

procedure writestring(str: PChar);
procedure writestringln(str: PChar);
procedure writestringex(str: PChar; attributes: uint32);
procedure writestringlnex(str: PChar; attributes: uint32);

procedure writeint(i: Integer);
procedure writeintln(i: Integer);
procedure writeintex(i: Integer; attributes: uint32);
procedure writeintlnex(i: Integer; attributes: uint32);

procedure writeword(i: DWORD);
procedure writewordln(i: DWORD);
procedure writewordex(i: DWORD; attributes: uint32);
procedure writewordlnex(i: DWORD; attributes: uint32);

procedure writehexpair(b : uint8);
procedure writehex(i: DWORD);
procedure writehexln(i: DWORD);
procedure writehexex(i : DWORD; attributes: uint32);
procedure writehexlnex(i: DWORD; attributes: uint32);

procedure writebin8(b : uint8);
procedure writebin8ln(b : uint8);
procedure writebin8ex(b : uint8; attributes: uint32);
procedure writebin8lnex(b : uint8; attributes: uint32);

procedure writebin16(b : uint16);
procedure writebin16ln(b : uint16);
procedure writebin16ex(b : uint16; attributes: uint32);
procedure writebin16lnex(b : uint16; attributes: uint32);

procedure writebin32(b : uint32);
procedure writebin32ln(b : uint32);
procedure writebin32ex(b : uint32; attributes: uint32);
procedure writebin32lnex(b : uint32; attributes: uint32);

procedure backspace;

function combinecolors(Foreground, Background : uint16) : uint32;

procedure _increment_x();
procedure _increment_y();
procedure _safeincrement_y();
procedure _safeincrement_x();
procedure _newline();
 
implementation

uses
    lmemorymanager;

type
    TConsoleProperties = record
      Default_Attribute : uint32;
    end;

    TCharacter = bitpacked record
      Character  : Char;
      attributes: uint32;
    end;
    PCharacter = ^TCharacter;

    TVideoMemory = Array[0..1999] of TCharacter;
    PVideoMemory = ^TVideoMemory;

    T2DVideoMemory = Array[0..63] of Array[0..159] of TCharacter;
    P2DVideoMemory = ^T2DVideoMemory;

    TCoord = record
      X : Byte;
      Y : Byte;
    end;

var
   Console_Properties : TConsoleProperties;
   //Console_Memory     : PVideoMemory = PVideoMemory($C00b8000);
   Console_Matrix     : T2DVideoMemory;//P2DVideoMemory = P2DVideoMemory($C00b8000);
   Console_Cursor     : TCoord;
   Ready : Boolean = false;

procedure outputChar(c : char; x : uint8; y : uint8; fgcolor : uint16; bgcolor : uint16);
var
    dest : puint16;
    dest32 : puint32;
    fgcolor32, bgcolor32 : uint32;
    mask : puint32;
    i : uint32;

begin
    if not ready then exit;
    fgcolor32:= fgcolor OR (fgcolor SHL 16);
    bgcolor32:= bgcolor OR (bgcolor SHL 16);
    mask:= puint32(@Std_Mask[uint32(c) * (16 * 8)]);
    dest:= puint16(multibootinfo^.framebuffer_addr);
    dest:= dest + (y*(1280 * 16)) + (x * 8);
    dest32:= puint32(dest);
    for i:=0 to 15 do begin
        dest32[(i*640)+0]:= (bgcolor32 AND NOT(mask[(i*4)+0])) OR (fgcolor32 AND mask[(i*4)+0]);
        dest32[(i*640)+1]:= (bgcolor32 AND NOT(mask[(i*4)+1])) OR (fgcolor32 AND mask[(i*4)+1]);
        dest32[(i*640)+2]:= (bgcolor32 AND NOT(mask[(i*4)+2])) OR (fgcolor32 AND mask[(i*4)+2]);
        dest32[(i*640)+3]:= (bgcolor32 AND NOT(mask[(i*4)+3])) OR (fgcolor32 AND mask[(i*4)+3]);
    end;
end;

procedure disable_cursor;
begin
     outb($3D4, $0A);
     outb($3D5, $20);
end;

procedure init(); [public, alias: 'console_init'];
var
   fb: puint32;

Begin
     fb:= puint32(uint32(multibootinfo^.framebuffer_addr));
     kpalloc(uint32(fb));
     Console_Properties.Default_Attribute:= console.combinecolors($FFFF, $0000);
     console.clear();
     Ready:= True;
end;

procedure clear(); [public, alias: 'console_clear'];
var
   x,y: Byte;

begin
     for x:=0 to 159 do begin
         for y:=0 to 63 do begin
	     Console_Matrix[y][x].Character:= ' ';
	     Console_Matrix[y][x].Attributes:= Console_Properties.Default_Attribute;
             OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
	 end;
     end;
     Console_Cursor.X:= 0;
     Console_Cursor.Y:= 0;
end;

procedure writebin8ex(b : uint8; attributes: uint32);
var
   Mask : PMask;
   i    : uint8;

begin
     Mask:= PMask(@b);
     for i:=0 to 7 do begin
        If Mask^[7-i] then writecharex('1', attributes) else writecharex('0', attributes);
     end;
end;

procedure writebin16ex(b : uint16; attributes: uint32);
var
   Mask : PMask;
   i,j  : uint8;

begin
     for j:=1 downto 0 do begin
        Mask:= PMask(uint32(@b) + (1 * j));
        for i:=0 to 7 do begin
                If Mask^[7-i] then writecharex('1', attributes) else writecharex('0', attributes);
        end;
     end;
end;

procedure writebin32ex(b : uint32; attributes: uint32);
var
   Mask : PMask;
   i,j  : uint8;

begin
     for j:=3 downto 0 do begin
        Mask:= PMask(uint32(@b) + (1 * j));
        for i:=0 to 7 do begin
                If Mask^[7-i] then writecharex('1', attributes) else writecharex('0', attributes);
        end;
     end;
end;

procedure writebin8(b : uint8);
begin
     writebin8ex(b, Console_Properties.Default_Attribute);
end;

procedure writebin16(b : uint16);
begin
     writebin16ex(b, Console_Properties.Default_Attribute);
end;

procedure writebin32(b : uint32);
begin
     writebin32ex(b, Console_Properties.Default_Attribute);
end;

procedure writebin8lnex(b : uint8; attributes: uint32);
begin
     writebin8ex(b, attributes);
     console._safeincrement_y();
end;

procedure writebin16lnex(b : uint16; attributes: uint32);
begin
     writebin16ex(b, attributes);
     console._safeincrement_y();
end;

procedure writebin32lnex(b : uint32; attributes: uint32);
begin
     writebin32ex(b, attributes);
     console._safeincrement_y();
end;

procedure writebin8ln(b : uint8);
begin
     writebin8lnex(b, Console_Properties.Default_Attribute);
end;

procedure writebin16ln(b : uint16);
begin
     writebin16lnex(b, Console_Properties.Default_Attribute);
end;

procedure writebin32ln(b : uint32);
begin
     writebin32lnex(b, Console_Properties.Default_Attribute);
end;

procedure setdefaultattribute(attribute: uint32); [public, alias: 'console_setdefaultattribute'];
begin
     Console_Properties.Default_Attribute:= attribute;
end;

procedure writechar(character: char); [public, alias: 'console_writechar'];
begin
     console.writecharex(character, Console_Properties.Default_Attribute);
end;

procedure writestring(str: PChar); [public, alias: 'console_writestring'];
begin
     console.writestringex(str, Console_Properties.Default_Attribute);
end;

procedure writeint(i: Integer); [public, alias: 'console_writeint'];
begin
     console.writeintex(i, Console_Properties.Default_Attribute);
end;

procedure writeword(i: DWORD); [public, alias: 'console_writeword'];
begin
     console.writewordex(i, Console_Properties.Default_Attribute);
end;

procedure writecharln(character: char); [public, alias: 'console_writecharln'];
begin
     console.writecharlnex(character, Console_Properties.Default_Attribute);
end;

procedure writestringln(str: PChar); [public, alias: 'console_writestringln'];
begin
     console.writestringlnex(str, Console_Properties.Default_Attribute);
end;

procedure writeintln(i: Integer); [public, alias: 'console_writeintln'];
begin
     console.writeintlnex(i, Console_Properties.Default_Attribute);
end;

procedure writewordln(i: DWORD); [public, alias: 'console_writewordln'];
begin
     console.writewordlnex(i, Console_Properties.Default_Attribute);
end;

procedure writecharex(character: char; attributes: uint32); [public, alias: 'console_writecharex'];
begin
     outputChar(character, Console_Cursor.X, Console_Cursor.Y, attributes SHR 16, attributes AND $FFFF);
     Console_Matrix[Console_Cursor.Y][Console_Cursor.X].Character:= character;
     Console_Matrix[Console_Cursor.Y][Console_Cursor.X].Attributes:= attributes;
     console._safeincrement_x();
end;

procedure writehexpair(b : uint8);
var
    bn : Array[0..1] of uint8;
    i  : uint8;

begin
    bn[0]:= b SHR 4;
    bn[1]:= b AND $0F;
    for i:=0 to 1 do begin
        case bn[i] of
            0:writestring('0');
            1:writestring('1');
            2:writestring('2');
            3:writestring('3');
            4:writestring('4');
            5:writestring('5');
            6:writestring('6');
            7:writestring('7');
            8:writestring('8');
            9:writestring('9');
            10:writestring('A');
            11:writestring('B');
            12:writestring('C');
            13:writestring('D');
            14:writestring('E');
            15:writestring('F');
        end;
    end;
end;

procedure writehexex(i : dword; attributes: uint32); [public, alias: 'console_writehexex'];
var
   Hex : Array[0..7] of Byte;
   Res : DWORD;
   Rem : DWORD;
   c   : Integer;
   
begin
     for c:=0 to 7 do begin
          Hex[c]:= 0;
     end;
     c:=0;
     Res:= i;
     Rem:= Res mod 16;
     while Res > 0 do begin
          Hex[c]:= Rem;
          Res:= Res div 16;
          Rem:= Res mod 16;
          c:=c+1;
     end;
     writestringex('0x', attributes);
     for c:=7 downto 0 do begin
          if Hex[c] <> 255 then begin
               case Hex[c] of
                    0:writecharex('0', attributes);
                    1:writecharex('1', attributes);
                    2:writecharex('2', attributes);
                    3:writecharex('3', attributes);
                    4:writecharex('4', attributes);
                    5:writecharex('5', attributes);
                    6:writecharex('6', attributes);
                    7:writecharex('7', attributes);
                    8:writecharex('8', attributes);
                    9:writecharex('9', attributes);
                    10:writecharex('A', attributes);
                    11:writecharex('B', attributes);
                    12:writecharex('C', attributes);
                    13:writecharex('D', attributes);
                    14:writecharex('E', attributes);
                    15:writecharex('F', attributes);
                    else writecharex('?', attributes);
               end;
          end;
     end;
end;

procedure writehex(i : dword); [public, alias: 'console_writehex'];
begin
     console.writehexex(i, Console_Properties.Default_Attribute);
end;

procedure writehexlnex(i : dword; attributes: uint32);
begin
     console.writehexex(i, attributes);
     console._safeincrement_y();
end;

procedure writehexln(i : dword);
begin
     writehexlnex(i, Console_Properties.Default_Attribute);
end;

procedure Output(identifier : PChar; str : PChar);
begin
     writestring('[');
     writestring(identifier);
     writestring('] ');
     writestring(str);
end;

procedure Outputln(identifier : PChar; str : PChar);
begin
     Output(identifier, str);
     writestringln(' ');
end;

procedure writestringex(str: PChar; attributes: uint32); [public, alias: 'console_writestringex'];
var
   i : integer;

begin
     i:= 0;
     while (str[i] <> #0) do begin
           console.writecharex(str[i], attributes);
           i:=i+1;
     end;
end;

procedure writeintex(i: Integer; attributes: uint32); [public, alias: 'console_writeintex'];
var
        buffer: array [0..11] of Char;
        str: PChar;
        digit: DWORD;
        minus: Boolean;
begin
        str := @buffer[11];
        str^ := #0;
        if (i < 0) then begin
                digit := -i;
                minus := True;
        end else begin
                digit := i;
                minus := False;
        end;
        repeat
                Dec(str);
                str^ := Char((digit mod 10) + Byte('0'));
                digit := digit div 10;
        until (digit = 0);
        if (minus) then begin
                Dec(str);
                str^ := '-';
        end;
        console.writestringex(str, attributes);
end;
 
procedure writewordex(i: DWORD; attributes: uint32); [public, alias: 'console_writedwordex'];
var
        buffer: array [0..11] of Char;
        str: PChar;
        digit: DWORD;
begin
        for digit := 0 to 10 do buffer[digit] := '0';
        str := @buffer[11];
        str^ := #0;
        digit := i;
        repeat
                Dec(str);
                str^ := Char((digit mod 10) + Byte('0'));
                digit := digit div 10;
        until (digit = 0);
        console.writestringex(@Buffer[0], attributes);
end;

procedure writecharlnex(character: char; attributes: uint32); [public, alias: 'console_writecharlnex'];
begin
     console.writecharex(character, attributes);
     console._safeincrement_y();
end;

procedure writestringlnex(str: PChar; attributes: uint32); [public, alias: 'console_writestringlnex'];
begin
     console.writestringex(str, attributes);
     console._safeincrement_y();
end;

procedure writeintlnex(i: Integer; attributes: uint32); [public, alias: 'console_writeintlnex'];
begin
     console.writeintex(i, attributes);
     console._safeincrement_y();
end;

procedure writewordlnex(i: DWORD; attributes: uint32); [public, alias: 'console_writewordlnex'];
begin
     console.writewordex(i, attributes);
     console._safeincrement_y();
end;

function combinecolors(Foreground, Background: uint16): uint32; 
begin
     combinecolors:= (uint32(Foreground) SHL 16) OR Background;
end;

procedure _update_cursor(); [public, alias: '_console_update_cursor'];
var
   pos : word;
   b   : byte;
   
begin
     pos:= (Console_Cursor.Y * 80) + Console_Cursor.X;
     outb($3D4, $0F);
     b:= pos and $00FF;
     outb($3D5, b);
     outb($3D4, $0E);
     b:= pos shr 8;
     outb($3D5, b);
end;

procedure backspace;
begin
     Dec(Console_Cursor.X);
     writechar(' ');
     Dec(Console_Cursor.X);
     _update_cursor();
end;

procedure _increment_x(); [public, alias: '_console_increment_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 159 then Console_Cursor.X:= 0;
     console._update_cursor;
end;

procedure _increment_y(); [public, alias: '_console_increment_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 63 then begin
             console._newline();
             Console_Cursor.Y:= 63;
     end;
     console._update_cursor;
end;

procedure _safeincrement_x(); [public, alias: '_console_safeincrement_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 159 then begin
        console._safeincrement_y();
     end;
     console._update_cursor;
end;

procedure _safeincrement_y(); [public, alias: '_console_safeincrement_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 63 then begin
             console._newline();
             Console_Cursor.Y:= 63;
     end;
     Console_Cursor.X:= 0;
     console._update_cursor;
end;

procedure _newline(); [public, alias: '_console_newline'];
var
   x, y : byte;

begin
     for x:=0 to 159 do begin
         for y:=0 to 63 do begin
             Console_Matrix[y][x]:= Console_Matrix[y+1][x];
         end;
     end;
     for x:=0 to 159 do begin
         Console_Matrix[63][x].Character:= ' ';
         Console_Matrix[63][x].Attributes:= $FFFF0000;
     end;
     for y:=0 to 63 do begin
        for x:=0 to 159 do begin
            OutputChar(Console_Matrix[y][x].Character, x, y, Console_Matrix[y][x].Attributes SHR 16, Console_Matrix[y][x].Attributes AND $FFFF);
        end;
     end;
     console._update_cursor;
end;
 
end.
