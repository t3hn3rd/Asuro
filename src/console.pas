{
/////////////////////////////////////////////////////////
//                                                     //
//               Freepascal barebone OS                //
//                       console.pas                   //
//                                                     //
/////////////////////////////////////////////////////////
//
//      By:             De Deyn Kim <kimdedeyn@skynet.be>
//      License:        Public domain
//
}
 
unit console;

interface

procedure console_init();
procedure console_clear();

procedure console_writechar(character : char; attributes : char);
procedure console_writestring(str: PChar; attributes : char);
procedure console_writeint(i: Integer; attributes : char);
procedure console_writedword(i: DWORD; attributes : char);

procedure console_writecharln(character : char; attributes : char);
procedure console_writestringln(str: PChar; attributes : char);
procedure console_writeintln(i: Integer; attributes : char);
procedure console_writedwordln(i: DWORD; attributes : char);

procedure _console_increment_x();
procedure _console_increment_y();
procedure _console_safeincrement_y();
procedure _console_safeincrement_x();
procedure _console_newline();
 
implementation

type
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
   Console_Memory : PVideoMemory = PVideoMemory($b8000);
   Console_Matrix : P2DVideoMemory = P2DVideoMemory($b8000);
   Console_Cursor : TCoord;

procedure console_init(); [public, alias: 'console_init'];
Begin
     console_clear();
end;

procedure console_clear(); [public, alias: 'console_clear'];
var
   x,y: Byte;

begin
     for x:=0 to 79 do begin
         for y:=0 to 24 do begin
	     Console_Matrix^[y][x].Character:=#0;
	     Console_Matrix^[y][x].Attributes:=#7;
	 end;
     end;
     Console_Cursor.X:= 0;
     Console_Cursor.Y:= 0;
end;

procedure console_writechar(character: char; attributes: char); [public, alias: 'console_writechar'];
begin
     Console_Matrix^[Console_Cursor.Y][Console_Cursor.X].Character:= character;
     Console_Matrix^[Console_Cursor.Y][Console_Cursor.X].Attributes:= attributes;
     _console_safeincrement_x();
end;

procedure console_writestring(str: PChar; attributes: char); [public, alias: 'console_writestring'];
var
   i : integer;

begin
     i:= 0;
     while (str[i] <> #0) do begin
           console_writechar(str[i], attributes);
           i:=i+1;
     end;
end;

procedure console_writeint(i: Integer; attributes : char); [public, alias: 'console_writeint'];
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
        console_writestring(str, attributes);
end;
 
procedure console_writedword(i: DWORD; attributes : char); [public, alias: 'console_writedword'];
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
        console_writestring(@Buffer[0], attributes);
end;

procedure console_writecharln(character: char; attributes: char); [public, alias: 'console_writecharln'];
begin
     console_writechar(character, attributes);
     _console_safeincrement_y();
end;

procedure console_writestringln(str: PChar; attributes: char); [public, alias: 'console_writestringln'];
begin
     console_writestring(str, attributes);
     _console_safeincrement_y();
end;

procedure console_writeintln(i: Integer; attributes: char); [public, alias: 'console_writeintln'];
begin
     console_writeint(i, attributes);
     _console_safeincrement_y();
end;

procedure console_writedwordln(i: DWORD; attributes: char); [public, alias: 'console_writedwordln'];
begin
     console_writedword(i, attributes);
     _console_safeincrement_y();
end;

procedure _console_increment_x(); [public, alias: '_console_increment_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 79 then Console_Cursor.X:= 0;
end;

procedure _console_increment_y(); [public, alias: '_console_increment_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 24 then begin
             _console_newline();
             Console_Cursor.Y:= 24;
     end;
end;

procedure _console_safeincrement_x(); [public, alias: '_console_safeincrement_x'];
begin
     Console_Cursor.X:= Console_Cursor.X+1;
     If Console_Cursor.X > 79 then begin
        _console_safeincrement_y();
     end;
end;

procedure _console_safeincrement_y(); [public, alias: '_console_safeincrement_y'];
begin
     Console_Cursor.Y:= Console_Cursor.Y+1;
     If Console_Cursor.Y > 24 then begin
             _console_newline();
             Console_Cursor.Y:= 24;
     end;
     Console_Cursor.X:= 0;
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
end;
 
end.
