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