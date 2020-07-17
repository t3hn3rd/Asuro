{ 
	Prog->edit - Simple text editor
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit edit;

interface

uses
    console, terminal, keyboard, shell, strings, tracer, storagemanagement, lmemorymanager, util;

procedure init();

implementation
const 
    width  = 60;
    height = 20;
var
    Handle  : HWND = 0;
    Colors  : uint32;
    ColorsSel  : uint32;
    position : uint32; //////////////////////////////
    fileName : pchar;
    extension : pchar = 'txt';
    //chars :  array[0..(height * width)] of char;
    chars : pchar;
    mousePos : uint32 =0;


procedure OnClose();
begin
    Handle:= 0;
end;

procedure Draw();
var
    y : uint32;
    pos : uint32;
begin
    push_trace('edit.draw');
    if Handle <> 0 then begin
        clearWNDEx(Handle, Colors);
        for y:=0 to (width * height)-1 do begin
            pos := y;
            if y = mousePos then begin 
                writecharexWND(chars[pos], ColorsSel, Handle); 
            end else begin
                writecharexWND(chars[pos], Colors, Handle);
            end;
            if (chars[pos] = char(0)) then break; // need to not do this at the end maybe...
        end;
    end
end;

procedure shiftBuffer(start : uint32);
var
    buffer : pchar;
begin
    buffer := stringnew(stringSize(chars) + 1);
    memset(uint32(buffer), 0, stringSize(chars) + 1); 

    memcpy(uint32(chars), uint32(@buffer[1]), stringSize(chars));
    memcpy(uint32(chars), uint32(buffer), start);

    kfree(puint32(chars));
    chars:= buffer;
end;

procedure OnKeyPressed(info : TKeyInfo);
var
    i   : uint32;
    pos : uint32;
begin
    //writeintlnWND(info.key_code, getTerminalHWND());
    if (info.CTRL_DOWN and (info.key_code = 115)) then begin 
        //SAVE FILE
        // storagemanagement.writeNewFile(fileName, extension, puint32(chars), stringSize(chars));
        writestringlnWND('saved', getTerminalHWND());
        //writeintlnWND(stringSize(chars), getTerminalHWND());
    end else begin
        //delete key
        if (info.key_code = 8) then begin
            //console.backspaceWND(Handle);
            if mousePos > 0 then mousePos -=1;
            chars[mousePos] := char(32);
        end else if info.key_code = 20 then begin
            mousePos +=1;
        end else if info.key_code = 19 then begin
            mousePos -=1;
        end else if info.key_code = 18 then begin
            if mousePos < width * height-1 then begin
                mousePos += width;
            end;
        end else if info.key_code = 16 then begin
            if mousePos > width+1 then begin
                mousePos -= width;
            end;
        end else begin
            if mousePos < stringSize(chars) then begin
                shiftBuffer(mousePos + 1);
            end;
            chars[mousePos] := char(info.key_code);
            //writecharexWND(char(info.key_code), Colors, Handle);
            mousePos +=1;
        end;

    end 



end;

procedure run(Params : PParamList);
var
    buffer : puint32;
    bytes  : puint32;
    error  : puint32;
    test : pchar;
begin
    tracer.push_trace('edit.run');

    fileName := stringCopy(getParam(0, Params));

    bytes := puint32(kalloc(4));
    bytes^ := 0;
    buffer := kalloc(4);
    // error := storagemanagement.readfile(fileName, extension, buffer, bytes);

    if error^ = 1 then begin
        //file doesn't exists, make new
        writestringlnWND('File does not exist, will save as a new file.', getTerminalHWND());
        console.redrawWindows();
        chars := pchar(kalloc(sizeof(char) * (width * height) * 10));
        memset(uint32(puint32(chars)), 0, sizeof(char) * (width * height));
    end else begin
        //load file from buffer
        writestringlnWND('File exsists, loading', getTerminalHWND());
        console.redrawWindows();
        //chars := pchar(buffer);
        chars := pchar(kalloc(bytes^));
        memset(uint32(chars), 0, bytes^);


        if uint32(puint32(chars)) = 0 then begin
            console.writestringlnWND('unable to allocate memory for file.', getTerminalHWND());
            console.writestringWND('attempted to allocate: ', getTerminalHWND());
            console.writeintWND(bytes^, getTerminalHWND());
                    redrawWindows();

            exit;
        end;

        //memset(uint32(chars), 0, bytes^ * 2);
        //memcpy(uint32(buffer), uint32(chars), uint32(bytes^));
        memcpy(uint32(buffer^), uint32(puint32(chars)), uint32(bytes^));
    end;

    // kfree(buffer);
    // kfree(bytes);
    // kfree(error);

    if Handle = 0 then begin
        Handle:= newWindow(20, 40, width, height, 'Edit');
        registerEventHandler(Handle, EVENT_DRAW, void(@Draw));
        registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
        registerEventHandler(Handle, EVENT_KEY_PRESSED, void(@OnKeyPressed));
        writestringlnWND('Edit Started.', getTerminalHWND);

    end;

    clearWNDEx(Handle, Colors);

end;

procedure init();
begin
    tracer.push_trace('edit.init');
    Colors:= combineColors($0000, $FFFF);
    ColorsSel:= combineColors($FFFF, $0000);
    terminal.registerCommand('EDIT', @Run, 'Edit those jucy text files');
end;

end.