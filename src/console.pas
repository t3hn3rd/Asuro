unit console;

interface

uses
     util, 
     bios_data_area;

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
procedure setdefaultattribute(attribute : char);

procedure writechar(character : char);
procedure writestring(str: PChar);
procedure writeint(i: Integer);
procedure writeword(i: DWORD);
procedure writehex(i: DWORD);

procedure writecharln(character : char);
procedure writestringln(str: PChar);
procedure writeintln(i: Integer);
procedure writewordln(i: DWORD);
procedure writehexln(i: DWORD);

procedure writecharex(character : char; attributes : char);
procedure writestringex(str: PChar; attributes : char);
procedure writeintex(i: Integer; attributes : char);
procedure writewordex(i: DWORD; attributes : char);
procedure writehexex(i : DWORD; attributes : char);

procedure writecharlnex(character : char; attributes : char);
procedure writestringlnex(str: PChar; attributes : char);
procedure writeintlnex(i: Integer; attributes : char);
procedure writewordlnex(i: DWORD; attributes : char);
procedure writehexlnex(i: DWORD; attributes : char);

function combinecolors(Foreground, Background : TColor) : char;

procedure _increment_x();
procedure _increment_y();
procedure _safeincrement_y();
procedure _safeincrement_x();
procedure _newline();
 
implementation

type
    TConsoleProperties = record
      Default_Attribute : Char;
    end;

    TCharacter = bitpacked record
      Character  : Char;
      Attributes : Char;
    end;
    PCharacter = ^TCharacter;

    TVideoMemory = Array[0..1999] of TCharacter;
    PVideoMemory = ^TVideoMemory;

    T2DVideoMemory = Array[0..24] of Array[0..79] of TCharacter;
    P2DVideoMemory = ^T2DVideoMemory;

    TCoord = record
      X : Byte;
      Y : Byte;
    end;

var
   Console_Properties : TConsoleProperties;
   Console_Memory     : PVideoMemory = PVideoMemory($b8000);
   Console_Matrix     : P2DVideoMemory = P2DVideoMemory($b8000);
   Console_Cursor     : TCoord;

procedure init(); [public, alias: 'console_init'];
Begin
     Console_Properties.Default_Attribute:= console.combinecolors(White, Black);
     console.clear();
end;

procedure clear(); [public, alias: 'console_clear'];
var
   x,y: Byte;

begin
     for x:=0 to 79 do begin
         for y:=0 to 24 do begin
	     Console_Matrix^[y][x].Character:= #0;
	     Console_Matrix^[y][x].Attributes:= Console_Properties.Default_Attribute;
	 end;
     end;
     Console_Cursor.X:= 0;
     Console_Cursor.Y:= 0;
end;

procedure setdefaultattribute(attribute: char); [public, alias: 'console_setdefaultattribute'];
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

procedure writecharex(character: char; attributes: char); [public, alias: 'console_writecharex'];
begin
     Console_Matrix^[Console_Cursor.Y][Console_Cursor.X].Character:= character;
     Console_Matrix^[Console_Cursor.Y][Console_Cursor.X].Attributes:= attributes;
     console._safeincrement_x();
end;

procedure writehexex(i : dword; attributes: char); [public, alias: 'console_writehexex'];
var
   Hex : Array[0..7] of Byte;
   Res : DWORD;
   Rem : DWORD;
   c   : Integer;
   
begin
     for c:=0 to 7 do begin
          Hex[c]:= 255;
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

procedure writehexlnex(i : dword; attributes : char);
begin
     console.writehexex(i, attributes);
     console._safeincrement_y();
end;

procedure writehexln(i : dword);
begin
     writehexlnex(i, Console_Properties.Default_Attribute);
end;

procedure writestringex(str: PChar; attributes: char); [public, alias: 'console_writestringex'];
var
   i : integer;

begin
     i:= 0;
     while (str[i] <> #0) do begin
           console.writecharex(str[i], attributes);
           i:=i+1;
     end;
end;

procedure writeintex(i: Integer; attributes : char); [public, alias: 'console_writeintex'];
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
 
procedure writewordex(i: DWORD; attributes : char); [public, alias: 'console_writedwordex'];
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

procedure writecharlnex(character: char; attributes: char); [public, alias: 'console_writecharlnex'];
begin
     console.writecharex(character, attributes);
     console._safeincrement_y();
end;

procedure writestringlnex(str: PChar; attributes: char); [public, alias: 'console_writestringlnex'];
begin
     console.writestringex(str, attributes);
     console._safeincrement_y();
end;

procedure writeintlnex(i: Integer; attributes: char); [public, alias: 'console_writeintlnex'];
begin
     console.writeintex(i, attributes);
     console._safeincrement_y();
end;

procedure writewordlnex(i: DWORD; attributes: char); [public, alias: 'console_writewordlnex'];
begin
     console.writewordex(i, attributes);
     console._safeincrement_y();
end;

function combinecolors(Foreground, Background: TColor): char; [public, alias: 'console_combinecolors'];
begin
     combinecolors:= char(((ord(Background) shl 4) or ord(Foreground)));
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

procedure _increment_x(); [public, alias: '_console_increment_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 79 then Console_Cursor.X:= 0;
     console._update_cursor;
end;

procedure _increment_y(); [public, alias: '_console_increment_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 24 then begin
             console._newline();
             Console_Cursor.Y:= 24;
     end;
     console._update_cursor;
end;

procedure _safeincrement_x(); [public, alias: '_console_safeincrement_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 79 then begin
        console._safeincrement_y();
     end;
     console._update_cursor;
end;

procedure _safeincrement_y(); [public, alias: '_console_safeincrement_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 24 then begin
             console._newline();
             Console_Cursor.Y:= 24;
     end;
     Console_Cursor.X:= 0;
     console._update_cursor;
end;

procedure _newline(); [public, alias: '_console_newline'];
var
   x, y : byte;

begin
     for x:=0 to 79 do begin
         for y:=0 to 23 do begin
             Console_Matrix^[y][x]:= Console_Matrix^[y+1][x];
         end;
     end;
     for x:=0 to 79 do begin
         Console_Matrix^[24][x].Character:= #0;
         Console_Matrix^[24][x].Attributes:= #7;
     end;
     console._update_cursor
end;
 
end.
