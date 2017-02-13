unit keyboard;

{$ASMMODE intel}

interface

uses
     util;

function get_scancode() : byte;

implementation

function get_scancode() : byte; [public, alias: 'get_scancode'];
var
   c : byte;
   
begin
     c:= 0;
     while true do begin
          if inb($60) <> c then begin
               c:= inb($60);
               if c > 0 then begin
                    get_scancode:= c;
                    exit;
               end;
          end;    
     end;
end;

end.
