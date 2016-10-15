unit console;

interface

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

procedure console_init();
procedure console_clear();
procedure console_setdefaultattribute(attribute : char);

procedure console_writechar(character : char);
procedure console_writestring(str: PChar);
procedure console_writeint(i: Integer);
procedure console_writeword(i: DWORD);

procedure console_writecharln(character : char);
procedure console_writestringln(str: PChar);
procedure console_writeintln(i: Integer);
procedure console_writewordln(i: DWORD);

procedure console_writecharex(character : char; attributes : char);
procedure console_writestringex(str: PChar; attributes : char);
procedure console_writeintex(i: Integer; attributes : char);
procedure console_writewordex(i: DWORD; attributes : char);

procedure console_writecharlnex(character : char; attributes : char);
procedure console_writestringlnex(str: PChar; attributes : char);
procedure console_writeintlnex(i: Integer; attributes : char);
procedure console_writewordlnex(i: DWORD; attributes : char);

function console_combinecolors(Foreground, Background : TColor) : char;

procedure _console_increment_x();
procedure _console_increment_y();
procedure _console_safeincrement_y();
procedure _console_safeincrement_x();
procedure _console_newline();
 
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

procedure console_init(); [public, alias: 'console_init'];
Begin
     Console_Properties.Default_Attribute:= console_combinecolors(White, Black);
     console_clear();
end;

procedure console_clear(); [public, alias: 'console_clear'];
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

procedure console_setdefaultattribute(attribute: char); [public, alias: 'console_setdefaultattribute'];
begin
     Console_Properties.Default_Attribute:= attribute;
end;

procedure console_writechar(character: char); [public, alias: 'console_writechar'];
begin
     console_writecharex(character, Console_Properties.Default_Attribute);
end;

procedure console_writestring(str: PChar); [public, alias: 'console_writestring'];
begin
     console_writestringex(str, Console_Properties.Default_Attribute);
end;

procedure console_writeint(i: Integer); [public, alias: 'console_writeint'];
begin
     console_writeintex(i, Console_Properties.Default_Attribute);
end;

procedure console_writeword(i: DWORD); [public, alias: 'console_writeword'];
begin
     console_writewordex(i, Console_Properties.Default_Attribute);
end;

procedure console_writecharln(character: char); [public, alias: 'console_writecharln'];
begin
     console_writecharlnex(character, Console_Properties.Default_Attribute);
end;

procedure console_writestringln(str: PChar); [public, alias: 'console_writestringln'];
begin
     console_writestringlnex(str, Console_Properties.Default_Attribute);
end;

procedure console_writeintln(i: Integer); [public, alias: 'console_writeintln'];
begin
     console_writeintlnex(i, Console_Properties.Default_Attribute);
end;

procedure console_writewordln(i: DWORD); [public, alias: 'console_writewordln'];
begin
     console_writewordlnex(i, Console_Properties.Default_Attribute);
end;

procedure console_writecharex(character: char; attributes: char); [public, alias: 'console_writecharex'];
begin
     Console_Matrix^[Console_Cursor.Y][Console_Cursor.X].Character:= character;
     Console_Matrix^[Console_Cursor.Y][Console_Cursor.X].Attributes:= attributes;
     _console_safeincrement_x();
end;

procedure console_writestringex(str: PChar; attributes: char); [public, alias: 'console_writestringex'];
var
   i : integer;

begin
     i:= 0;
     while (str[i] <> #0) do begin
           console_writecharex(str[i], attributes);
           i:=i+1;
     end;
end;

procedure console_writeintex(i: Integer; attributes : char); [public, alias: 'console_writeintex'];
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
        console_writestringex(str, attributes);
end;
 
procedure console_writewordex(i: DWORD; attributes : char); [public, alias: 'console_writedwordex'];
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
        console_writestringex(@Buffer[0], attributes);
end;

procedure console_writecharlnex(character: char; attributes: char); [public, alias: 'console_writecharlnex'];
begin
     console_writecharex(character, attributes);
     _console_safeincrement_y();
end;

procedure console_writestringlnex(str: PChar; attributes: char); [public, alias: 'console_writestringlnex'];
begin
     console_writestringex(str, attributes);
     _console_safeincrement_y();
end;

procedure console_writeintlnex(i: Integer; attributes: char); [public, alias: 'console_writeintlnex'];
begin
     console_writeintex(i, attributes);
     _console_safeincrement_y();
end;

procedure console_writewordlnex(i: DWORD; attributes: char); [public, alias: 'console_writewordlnex'];
begin
     console_writewordex(i, attributes);
     _console_safeincrement_y();
end;

function console_combinecolors(Foreground, Background: TColor): char; [public, alias: 'console_combinecolors'];
begin
     console_combinecolors:= char(((ord(Background) shl 4) or ord(Foreground)));
end;

procedure _console_update_cursor(); [public, alias: '_console_update_cursor'];
begin
     {asm
        MOV AH, $02
        MOV BH, $00
        MOV DH, Console_Cursor.Y
        MOV DL, Console_Cursor.X
        INT $10
     end; }
	
end;

procedure _console_increment_x(); [public, alias: '_console_increment_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 79 then Console_Cursor.X:= 0;
     _console_update_cursor;
end;

procedure _console_increment_y(); [public, alias: '_console_increment_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 24 then begin
             _console_newline();
             Console_Cursor.Y:= 24;
     end;
     _console_update_cursor;
end;

procedure _console_safeincrement_x(); [public, alias: '_console_safeincrement_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 79 then begin
        _console_safeincrement_y();
     end;
     _console_update_cursor;
end;

procedure _console_safeincrement_y(); [public, alias: '_console_safeincrement_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 24 then begin
             _console_newline();
             Console_Cursor.Y:= 24;
     end;
     Console_Cursor.X:= 0;
     _console_update_cursor;
end;

procedure _console_newline(); [public, alias: '_console_newline'];
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
     _console_update_cursor
end;
 
end.
