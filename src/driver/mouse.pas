unit mouse;

interface

uses 
    console,
    util,
    isr44;

procedure init();

implementation

procedure callback(packet : void);
begin
    //console.writestring('Mouse Packet: ');
    //console.writehexln(DWORD(packet));
end;

procedure init();
begin
    isr44.hook(uint32(@callback));
end;

end.