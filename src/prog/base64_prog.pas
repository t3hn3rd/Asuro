//  Copyright 2021 Angus C
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
	Prog->Base64 - Base64 encode and decode.
	
	@author(Angus C <angus@actm.uk>)
}
unit base64_prog;

interface

uses
    console, terminal, keyboard, util, strings, tracer, base64, lmemorymanager;

procedure init();

implementation

procedure run(Params : PParamList);
var
    input     : pchar;
    pinput    : pchar;
    encdec    : pchar;
    result    : pchar;
    i         : uInt32;
    PSize     : uInt32;

begin
    tracer.push_trace('base64_prog.run');
    if paramCount(Params) > 1 then begin
        encdec := getParam(0, Params);
        if stringEquals(encdec, 'encode') then begin
            PSize := 0;
            for i := 1 to ParamCount(params) - 1 do begin
                PSize := PSize + stringSize(getParam(i, Params));
            end;
            Psize := PSize + 1 + (ParamCount(params) - 1);
            input := pchar(kalloc(PSize));
            pinput := input;
            for i := 1 to ParamCount(params) - 1 do begin
                memcpy(uInt32(getParam(i, Params)), uInt32(pinput), stringSize(getParam(i, Params)));
                inc(pinput, stringSize(getParam(i, Params)));
                pinput^ := ' ';
                inc(pinput);
            end;
            dec(pinput);
            pinput^ := #0;
            result := b64_encode_str(input);
            writestringlnWND(result, getTerminalHWND);
            kfree(void(result));
        end else if stringEquals(encdec, 'decode') then begin
            input := getParam(1, Params);
            result := b64_decode_str(input);
            writestringlnWND(result, getTerminalHWND);
            kfree(void(result));
        end else writestringlnWND('Usage: base64 <encode/decode> <text>', getTerminalHWND);
    end else begin
        writestringlnWND('Usage: base64 <encode/decode> <text>', getTerminalHWND);
    end;
end;

procedure init();
begin
    tracer.push_trace('base64_prog.init');
    terminal.registerCommand('BASE64', @Run, 'Perform Base64 Encode/Decode.');
end;

end.