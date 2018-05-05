unit memview;

interface

uses
    console, terminal, keyboard;

procedure init();

implementation

uses
    strings, tracer;

type
    TMode = (tmHex, tmChar);

var
    Handle  : HWND = 0;
    MEM_LOC : uint32;
    NEW_LOC : Boolean;
    Colors  : uint32;
    Changed : uint32;
    Data    : Array[0..176] of byte;
    Mode    : TMode;

procedure printmemoryaschar(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);
var
    buf : puint8;
    i   : uint32;

begin
    tracer.push_trace('memview.printmemory');
    buf:= puint8(source);
    if NEW_LOC then begin
        NEW_LOC:= false;
        for i:=0 to length-1 do begin
            Data[i]:= buf[i];
        end;
    end;
    console.writestringlnExWND(' ', Colors, Handle);
    console.writestringlnExWND(' ', Colors, Handle);
    for i:=0 to length-1 do begin
        if offset_row and (i = 0) then begin
            console.writestringExWND('  ', Colors, Handle);
            console.writehexExWND(source + (i), Colors, Handle);
            console.writestringExWND(': ', Colors, Handle);
        end; 
        if buf[i] = Data[i] then console.writecharExWND(char(buf[i]), Colors, Handle) else console.writecharExWND(char(buf[i]), Changed, Handle);
        console.writecharExWND(' ', Colors, Handle);
        if i<>length-1 then begin
            if ((i+1) MOD col) = 0 then begin
                console.writestringlnExWND(' ', Colors, Handle);  
                if offset_row then begin
                    console.writestringExWND('  ', Colors, Handle);
                    console.writehexExWND(source + (i + 1), Colors, Handle);
                    console.writestringExWND(': ', Colors, Handle);
                end;  
            end else begin
                console.writestringExWND(delim, Colors, Handle);
            end;
        end;
    end;
    console.writestringlnExWND(' ', Colors, Handle);   
end;

procedure printmemoryashex(source : uint32; length : uint32; col : uint32; delim : PChar; offset_row : boolean);
var
    buf : puint8;
    i   : uint32;

begin
    tracer.push_trace('memview.printmemory');
    buf:= puint8(source);
    if NEW_LOC then begin
        NEW_LOC:= false;
        for i:=0 to length-1 do begin
            Data[i]:= buf[i];
        end;
    end;
    console.writestringlnExWND(' ', Colors, Handle);
    console.writestringlnExWND(' ', Colors, Handle);
    for i:=0 to length-1 do begin
        if offset_row and (i = 0) then begin
            console.writestringExWND('  ', Colors, Handle);
            console.writehexExWND(source + (i), Colors, Handle);
            console.writestringExWND(': ', Colors, Handle);
        end; 
        if buf[i] = Data[i] then console.writehexpairExWND(buf[i], Colors, Handle) else console.writehexpairExWND(buf[i], Changed, Handle);
        if i<>length-1 then begin
            if ((i+1) MOD col) = 0 then begin
                console.writestringlnExWND(' ', Colors, Handle);  
                if offset_row then begin
                    console.writestringExWND('  ', Colors, Handle);
                    console.writehexExWND(source + (i + 1), Colors, Handle);
                    console.writestringExWND(': ', Colors, Handle);
                end;  
            end else begin
                console.writestringExWND(delim, Colors, Handle);
            end;
        end;
    end;
    console.writestringlnExWND(' ', Colors, Handle);   
end;

procedure OnClose();
begin
    Handle:= 0;
end;

procedure Draw();
begin
    tracer.push_trace('memview.draw');
    if Handle <> 0 then begin
        clearWNDEx(Handle, Colors);
        case mode of
            tmHex:printmemoryashex(MEM_LOC, 176, 16, ' ', true);
            tmChar:printmemoryaschar(MEM_LOC, 176, 16, ' ', true);
        end;
    end;
end;

procedure OnKeyPressed(info : TKeyInfo);
begin
    if info.CTRL_DOWN then begin
        if info.key_code = 16 then begin
            dec(MEM_LOC, 176);
            NEW_LOC:= true;
        end;
        if info.key_code = 18 then begin
            inc(MEM_LOC, 176);
            NEW_LOC:= true;
        end;
    end else begin
        if info.key_code = 16 then begin
            dec(MEM_LOC, 16);
            NEW_LOC:= true;
        end;
        if info.key_code = 18 then begin
            inc(MEM_LOC, 16);
            NEW_LOC:= true;
        end;
    end;
    if info.key_code = uint8('c') then begin
        Mode:= tmChar;
    end;
    if info.key_code = uint8('h') then begin
        Mode:= tmHex;
    end;
end;

procedure run(Params : PParamList);
var
    loc : PChar;

begin
    tracer.push_trace('memview.run');
    if ParamCount(Params) < 1 then begin
        writestringlnWND('Memview Utility', getTerminalHWND);
        writestringlnWND(' ', getTerminalHWND);
        writestringlnWND('A tool to display the bytes stored at a memory location for debugging.', getTerminalHWND);
        writestringlnWND('UP/DOWN on the keyboard can be used to decrement/increment the view location by 16-bytes.', getTerminalHWND);
        writestringlnWND(' ', getTerminalHWND);
        writestringlnWND('Usage: ', getTerminalHWND);
        writestringlnWND('      memview <dLocation> - Display 176 bytes @ <dLocation>', getTerminalHWND);
        writestringlnWND(' ', getTerminalHWND);
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
            if (loc[0] = 'x') or (loc[0] = 'X') then MEM_LOC:= HexStringToInt(@loc[1]) else MEM_LOC:= stringToInt(loc);
            NEW_LOC:= true;
            if Handle = 0 then begin
                Handle:= newWindow(20, 40, 63, 14, 'MEMVIEW');
                registerEventHandler(Handle, EVENT_DRAW, void(@Draw));
                registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
                registerEventHandler(Handle, EVENT_KEY_PRESSED, void(@OnKeyPressed));
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
    Colors:= combineColors($0000, $FFFF);
    Changed:= combineColors($F800, $FFFF);
    Mode:= tmHex;
end;

end.