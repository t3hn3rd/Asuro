unit memview;

interface

uses
    console, terminal;

procedure init();

implementation

uses
    strings, tracer;

var
    Handle  : HWND = 0;
    MEM_LOC : uint32;

procedure mvprintmemory(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);
var
    buf : puint8;
    i   : uint32;

begin   
    tracer.push_trace('memview.printmemory');
    buf:= puint8(source);
    console.writestringlnWND(' ', Handle);
    console.writestringlnWND(' ', Handle);
    for i:=0 to length-1 do begin
        if offset_row and (i = 0) then begin
            console.writestringWND('  ', Handle);
            console.writehexWND(source + (i), Handle);
            console.writestringWND(': ', Handle);
        end; 
        console.writehexpairWND(buf[i], Handle);
        if i<>length-1 then begin
            if ((i+1) MOD col) = 0 then begin
                console.writestringlnWND(' ', Handle);  
                if offset_row then begin
                    console.writestringWND('  ', Handle);
                    console.writehexWND(source + (i + 1), Handle);
                    console.writestringWND(': ', Handle);
                end;  
            end else begin
                console.writestringWND(delim, Handle);
            end;
        end;
    end;
    console.writestringlnWND(' ', Handle);   
end;

procedure OnClose();
begin
    Handle:= 0;
end;

procedure Draw();
begin
    tracer.push_trace('memview.draw');
    if Handle <> 0 then begin
        clearWND(Handle);
        mvprintmemory(MEM_LOC, 176, 16, ' ', true);
    end;
end;

procedure run(Params : PParamList);
var
    loc : PChar;

begin
    tracer.push_trace('memview.run');
    if ParamCount(Params) < 1 then begin
        writestringlnWND('No memory location specified!', getTerminalHWND);
    end else begin
        loc:= GetParam(0, Params);
        if StringEquals(loc, 'close') then begin
            tracer.push_trace('memview.close');
            if Handle <> 0 then begin
                closeWindow(Handle);
                writestringlnWND('Memview closed.', getTerminalHWND);
            end else begin
                writestringlnWND('Memview not open.', getTerminalHWND);   
            end;
        end else begin
            MEM_LOC:= stringToInt(loc);
            if Handle = 0 then begin
                Handle:= newWindow(20, 40, 63, 14, 'MEMVIEW');
                registerEventHandler(Handle, EVENT_DRAW, void(@Draw));
                registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
                writestringWND('Memview started at location: ', getTerminalHWND);
            end else begin
                writestringWND('Memview location changed to: ', getTerminalHWND);
            end;
            writehexlnWND(MEM_LOC, getTerminalHWND);
        end;
    end;
end;

procedure init();
begin
    tracer.push_trace('memview.init');
    terminal.registerCommand('MEMVIEW', @Run, 'View a location in memory [MEMVIEW <Location>]');
end;

end.