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
unit app.md5sum;

interface

uses
    io.stdio, core.util, arch.x86.util, core.strings, debug.tracer, core.enc.md5;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
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
        io.stdio.bufWriteHexPair(stdout_buf, MD5_Hash^[i]);
    end;
    io.stdio.bufWriteStrLn(stdout_buf, ' ');
end;

procedure init();
begin
    debug.tracer.push_trace('md5sum.init');
    io.stdio.registerCommand('MD5SUM', @Run, 'Perform MD5SUM on a word.');
end;

end.