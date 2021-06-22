//  Copyright 2021 Kieron Morris
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ 
	Prog->Themer - Live Desktop Color Picker.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit themer;

interface

uses
    console, terminal, keyboard, shell, strings, tracer;

procedure init();

implementation

type
    TThemeThing = record
        ThemeName : PChar;
        Colors    : PRGB565Pair;
    end;

var
    Handle  : HWND = 0;
    Colors  : uint32;
    Themes  : Array[0..3] of TThemeThing;
    Selected : uint32;
    ForeBack : uint32;
    Changing : Boolean = false;

procedure OnClose();
begin
    Handle:= 0;
end;

procedure Draw();
var
    i, j : uint32;
    longest, len : uint32;

begin
    tracer.push_trace('themer.draw');
    if Handle <> 0 then begin
        clearWNDEx(Handle, Colors);
        writestringlnexWND(' ', Colors, Handle);
        writestringlnexWND(' ', Colors, Handle);
        writestringlnexWND(' ', Colors, Handle);
        writestringlnexWND(' ', Colors, Handle);
        longest:= 0;
        for i:=0 to 3 do begin
            if stringSize(Themes[i].ThemeName) > longest then longest:= stringSize(Themes[i].ThemeName);
        end;
        for j:=0 to longest do begin
                writeStringexWND(' ', Colors, Handle);
        end;
        writestringexWND('       Foreground     ', Colors, Handle);
        writestringexWND(#6, Colors, Handle);
        writestringlnexWND('     Background', Colors, Handle);
        for i:=0 to 3 do begin
            len:= longest - StringSize(Themes[i].ThemeName);
            for j:=0 to len do begin
                writeStringexWND(' ', Colors, Handle);
            end;
            writestringexWND(' ', Colors, Handle);
            writeStringexWND(Themes[i].ThemeName, Colors, Handle);
            writeStringexWND(':', Colors, Handle);
            if (ForeBack = 0) and (Selected = i) and (Changing) then writeStringexWND(' *R:', Colors, Handle) else if (ForeBack = 0) and (Selected = i) then writeStringexWND(' >R:', Colors, Handle) else writeStringexWND('  R:', Colors, Handle);
            if Themes[i].Colors^.Foreground.R < 10 then writeintexWND(0, Colors, Handle);
            writeintexWND(Themes[i].Colors^.Foreground.R, Colors, Handle);
            if (ForeBack = 1) and (Selected = i) and (Changing) then writeStringexWND(' *G:', Colors, Handle) else if (ForeBack = 1) and (Selected = i) then writeStringexWND(' >G:', Colors, Handle) else writeStringexWND('  G:', Colors, Handle);
            if Themes[i].Colors^.Foreground.G < 10 then writeintexWND(0, Colors, Handle);
            writeintexWND(Themes[i].Colors^.Foreground.G, Colors, Handle);
            if (ForeBack = 2) and (Selected = i) and (Changing) then writeStringexWND(' *B:', Colors, Handle) else if (ForeBack = 2) and (Selected = i) then writeStringexWND(' >B:', Colors, Handle) else writeStringexWND('  B:', Colors, Handle);
            if Themes[i].Colors^.Foreground.B < 10 then writeintexWND(0, Colors, Handle);
            writeintexWND(Themes[i].Colors^.Foreground.B, Colors, Handle);
            writestringexWND('  ', Colors, Handle);
            writestringexWND(#6, Colors, Handle);
            if (ForeBack = 3) and (Selected = i) and (Changing) then writeStringexWND(' *R:', Colors, Handle) else if (ForeBack = 3) and (Selected = i) then writeStringexWND(' >R:', Colors, Handle) else writeStringexWND('  R:', Colors, Handle);
            if Themes[i].Colors^.Background.R < 10 then writeintexWND(0, Colors, Handle);
            writeintexWND(Themes[i].Colors^.Background.R, Colors, Handle);
            if (ForeBack = 4) and (Selected = i) and (Changing) then writeStringexWND(' *G:', Colors, Handle) else if (ForeBack = 4) and (Selected = i) then writeStringexWND(' >G:', Colors, Handle) else writeStringexWND('  G:', Colors, Handle);
            if Themes[i].Colors^.Background.G < 10 then writeintexWND(0, Colors, Handle);
            writeintexWND(Themes[i].Colors^.Background.G, Colors, Handle);
            if (ForeBack = 5) and (Selected = i) and (Changing) then writeStringexWND(' *B:', Colors, Handle) else if (ForeBack = 5) and (Selected = i) then writeStringexWND(' >B:', Colors, Handle) else writeStringexWND('  B:', Colors, Handle);
            if Themes[i].Colors^.Background.B < 10 then writeintexWND(0, Colors, Handle);
            writeintexWND(Themes[i].Colors^.Background.B, Colors, Handle);
            writestringlnexWND(' ', Colors, Handle);
        end;
        len:= longest - StringSize('Color16');
        for j:=0 to len do begin
            writeStringexWND(' ', Colors, Handle);
        end;
        writestringexWND(' ', Colors, Handle);
        writestringexWND('Color16:', Colors, Handle);
        writestringexWND('     ', Colors, Handle);
        writehexexWND(puint16(@Themes[Selected].Colors^.Foreground)^, Colors, Handle);
        writestringexWND('     '+#6, Colors, Handle);
        writestringexWND('     ', Colors, Handle);
        writehexlnexWND(puint16(@Themes[Selected].Colors^.Background)^, Colors, Handle);
        writestringlnexWND(' ', Colors, Handle);
        writestringlnexWND('  Press ''d'' to dump color values.', Colors, Handle);
    end;
end;

procedure incrementSelected;
begin
    case ForeBack of
        0:Themes[Selected].Colors^.Foreground.R:= Themes[Selected].Colors^.Foreground.R + 1;
        1:Themes[Selected].Colors^.Foreground.G:= Themes[Selected].Colors^.Foreground.G + 1;
        2:Themes[Selected].Colors^.Foreground.B:= Themes[Selected].Colors^.Foreground.B + 1;
        3:Themes[Selected].Colors^.Background.R:= Themes[Selected].Colors^.Background.R + 1;
        4:Themes[Selected].Colors^.Background.G:= Themes[Selected].Colors^.Background.G + 1;
        5:Themes[Selected].Colors^.Background.B:= Themes[Selected].Colors^.Background.B + 1;
    end;
end;

procedure decrementSelected;
begin
    case ForeBack of
        0:Themes[Selected].Colors^.Foreground.R:= Themes[Selected].Colors^.Foreground.R - 1;
        1:Themes[Selected].Colors^.Foreground.G:= Themes[Selected].Colors^.Foreground.G - 1;
        2:Themes[Selected].Colors^.Foreground.B:= Themes[Selected].Colors^.Foreground.B - 1;
        3:Themes[Selected].Colors^.Background.R:= Themes[Selected].Colors^.Background.R - 1;
        4:Themes[Selected].Colors^.Background.G:= Themes[Selected].Colors^.Background.G - 1;
        5:Themes[Selected].Colors^.Background.B:= Themes[Selected].Colors^.Background.B - 1;
    end;
end;

procedure OnKeyPressed(info : TKeyInfo);
var
    i : uint32;

begin
    case info.key_code of
        13:begin
            Changing:= not Changing;
        end;
        16:begin //Up
            if changing then begin
                incrementSelected;
            end else begin
                if Selected > 0 then dec(Selected);
            end;
        end;
        18:begin //Down
            if changing then begin
                decrementSelected;
            end else begin
                if Selected < 3 then inc(Selected);
            end;
        end;
        20:begin //Right
            if not changing then begin
                if ForeBack < 5 then inc(ForeBack);
            end;
        end;
        19:begin //Left
            if not changing then begin
                if ForeBack > 0 then dec(ForeBack);
            end;
        end;
        uint8('d'):begin
            writestringlnWND(' ', getTerminalHWND);
            for i:=0 to 3 do begin
                writestringWND(Themes[i].ThemeName, getTerminalHWND);
                writestringWND(': Foreground: ', getTerminalHWND);
                writehexWND(puint16(@Themes[i].Colors^.Foreground)^, getTerminalHWND);
                writestringWND(' Background: ', getTerminalHWND);
                writehexlnWND(puint16(@Themes[i].Colors^.Background)^, getTerminalHWND);
            end;
        end;
    end;
end;

procedure run(Params : PParamList);
begin
    tracer.push_trace('themer.run');
    if Handle = 0 then begin
        Handle:= newWindow(20, 40, 65, 14, 'THEMER');
        registerEventHandler(Handle, EVENT_DRAW, void(@Draw));
        registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
        registerEventHandler(Handle, EVENT_KEY_PRESSED, void(@OnKeyPressed));
        writestringlnWND('Themer Started.', getTerminalHWND);
        Themes[0].ThemeName:= 'Windows';
        Themes[0].Colors:= PRGB565Pair(getWindowColorPtr);
        Themes[1].ThemeName:= 'Background';
        Themes[1].Colors:= PRGB565Pair(getDesktopColorsPtr);
        Themes[2].ThemeName:= 'Explore Button';
        Themes[2].Colors:= PRGB565Pair(getExploreColorsPtr);
        Themes[3].ThemeName:= 'Taskbar';
        Themes[3].Colors:= PRGB565Pair(getTaskbarColorsPtr);
        Selected:= 0;
        ForeBack:= 0;
    end;
end;

procedure init();
begin
    Colors:= combineColors($0000, $FFFF);
    tracer.push_trace('themer.init');
    terminal.registerCommand('THEMER', @Run, 'Themer, for your themez.');
end;

end.