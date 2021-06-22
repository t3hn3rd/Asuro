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
    MD5_128     : puint128;
    Result      : uint64;
    Result32    : uint32;
    Modulo      : uint64;


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