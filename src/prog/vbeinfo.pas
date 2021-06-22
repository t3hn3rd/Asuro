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
	Prog->vbeinfo - Print out vbeinfo (VESA VGA).
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit vbeinfo;

interface

uses
    console, terminal, keyboard, util, strings, tracer, md5;

procedure init();

implementation

procedure run(Params : PParamList);
var
    ConProp : PConsoleProperties;

begin
    ConProp:= getConsoleProperties();
    writestringWND('Pixel Width: ', getTerminalHWND);
    writeintlnWND(ConProp^.Width, getTerminalHWND);
    writestringWND('Pixel Height: ', getTerminalHWND);
    writeintlnWND(ConProp^.Height, getTerminalHWND);
    writestringWND('Bits Per Pixel: ', getTerminalHWND);
    writeintlnWND(ConProp^.BitsPerPixel, getTerminalHWND);
    writestringWND('Cell Width: ', getTerminalHWND);
    writeintlnWND(ConProp^.MAX_CELL_X, getTerminalHWND);
    writestringWND('Cell Height: ', getTerminalHWND);
    writeintlnWND(ConProp^.MAX_CELL_Y, getTerminalHWND);
end;

procedure init();
begin
    tracer.push_trace('vbeinfo.init');
    terminal.registerCommand('VBEINFO', @Run, 'Print out vbeinfo (VESA VGA).');
end;

end.