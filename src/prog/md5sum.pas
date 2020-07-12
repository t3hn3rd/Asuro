{ 
	Prog->MD5Sum - MD5 Checksum of a given string.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit md5sum;

interface

uses
    console, terminal, keyboard, util, strings, tracer, md5;

procedure init();

implementation

procedure run(Params : PParamList);
var
    md5word     : pchar;
    wordlen     : uint32;
    MD5_Hash    : PMD5Digest; 
    i           : uint32;

begin
    md5word:= getParam(0, Params);
    wordlen:= stringSize(md5word);
    MD5_Hash := MD5Buffer(puint8(md5word), wordlen);
    for i:=0 to 15 do begin
        writehexpairWND(MD5_Hash^[i], getTerminalHWND);
    end;
    writestringlnWND(' ', getTerminalHWND);
end;

procedure init();
begin
    tracer.push_trace('md5sum.init');
    terminal.registerCommand('MD5SUM', @Run, 'Perform MD5SUM on a word.');
end;

end.