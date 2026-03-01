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
    stdio, video, util, strings, tracer;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    stdio.bufWriteStr(stdout_buf, 'Pixel Width: ');
    stdio.bufWriteIntLn(stdout_buf, video.frontBufferWidth);
    stdio.bufWriteStr(stdout_buf, 'Pixel Height: ');
    stdio.bufWriteIntLn(stdout_buf, video.frontBufferHeight);
    stdio.bufWriteStr(stdout_buf, 'Bits Per Pixel: ');
    stdio.bufWriteIntLn(stdout_buf, video.frontBufferBpp);
end;

procedure init();
begin
    tracer.push_trace('vbeinfo.init');
    stdio.registerCommand('VBEINFO', @Run, 'Print out vbeinfo (VESA VGA).');
end;

end.