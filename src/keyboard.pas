unit keyboard;

{$ASMMODE intel}

interface

uses
     types,
     util;

function get_scancode() : uint8;

implementation

function get_scancode() : uint8; [public, alias: 'get_scancode'];
var
   c : uint8;
   
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
