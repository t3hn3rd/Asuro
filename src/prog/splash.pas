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
	Prog->Splash - Asuro Splash Screen.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit splash;

interface

uses
    console, keyboard, RTC;

procedure init();

implementation

var
    Splash_Handle : HWND;
    Seconds : uint32 = 0;
    Colors : uint32;
    Delta  : uint32 = 0;
    Loops  : uint32 = 0;

procedure quit();
begin
    closeWindow(Splash_Handle);
    mouseEnabled(true);
end;

procedure keypress(info : TKeyInfo);
begin
    quit();
end;

procedure animate();
var
    DateTime : TDateTime;

begin
    DateTime:= getDateTime;
    if DateTime.Seconds <> Seconds then begin
        inc(Delta);
        Seconds:= DateTime.Seconds;
    end;
    ClearWNDEx(Splash_Handle, Colors);
    if Delta > 1 then begin
        setCursorPosWND(45, 27, Splash_Handle);
        writestringExWND('       db           ', Colors, Splash_Handle);  
    end;
    if Delta > 2 then begin
        setCursorPosWND(45, 28, Splash_Handle);                                             
        writestringExWND('      d88b          ', Colors, Splash_Handle);
    end;
    if Delta > 3 then begin
        setCursorPosWND(45, 29, Splash_Handle);
        writestringExWND('     d8''`8b         ', Colors, Splash_Handle);
    end;
    if Delta > 4 then begin
        setCursorPosWND(45, 30, Splash_Handle);
        writestringExWND('    d8''  `8b      ,adPPYba,  88       88  8b,dPPYba,   ,adPPYba,', Colors, Splash_Handle);
    end;
    if Delta > 5 then begin
        setCursorPosWND(45, 31, Splash_Handle);
        writestringExWND('   d8YaaaaY8b     I8[    ""  88       88  88P''   "Y8  a8"     "8a', Colors, Splash_Handle);
    end;
    if Delta > 6 then begin
        setCursorPosWND(45, 32, Splash_Handle);
        writestringExWND('  d8""""""""8b     `"Y8ba,   88       88  88          8b       d8', Colors, Splash_Handle);  
    end;
    if Delta > 7 then begin
        setCursorPosWND(45, 33, Splash_Handle);
        writestringExWND(' d8''        `8b   aa    ]8I  "8a,   ,a88  88          "8a,   ,a8"', Colors, Splash_Handle);  
    end;
    if Delta > 8 then begin
        setCursorPosWND(45, 34, Splash_Handle);
        writestringExWND('d8''          `8b  `"YbbdP"''   `"YbbdP''Y8  88           `"YbbdP"''', Colors, Splash_Handle);
    end;
    if Delta > 9 then begin
        Inc(Loops);
        Delta:= 1;
    end;
    if Loops > 2 then begin 
        quit();
    end;
end;

procedure init();
begin
    Colors:= combineColors($FFFF, $5CDE);
    Splash_Handle:= newWindow(0, 0, 159, 63, 'SPLASH');
    SetShellWindow(Splash_Handle, false);
    BordersEnabled(Splash_Handle, false);
    registerEventHandler(Splash_Handle, EVENT_DRAW, void(@animate));
    registerEventHandler(Splash_Handle, EVENT_KEY_PRESSED, void(@keypress));
    mouseEnabled(false);
end;

end.