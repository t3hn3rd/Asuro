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
	Prog->app.vbeinfo - Print out app.vbeinfo (VESA VGA).
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.vbeinfo;

interface

uses
    io.stdio, driver.video, core.util, arch.x86.util, core.strings, debug.tracer;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    io.stdio.bufWriteStr(stdout_buf, 'Pixel Width: ');
    io.stdio.bufWriteIntLn(stdout_buf, driver.video.frontBufferWidth);
    io.stdio.bufWriteStr(stdout_buf, 'Pixel Height: ');
    io.stdio.bufWriteIntLn(stdout_buf, driver.video.frontBufferHeight);
    io.stdio.bufWriteStr(stdout_buf, 'Bits Per Pixel: ');
    io.stdio.bufWriteIntLn(stdout_buf, driver.video.frontBufferBpp);
end;

procedure init();
begin
    debug.tracer.push_trace('vbeinfo.init');
    io.stdio.registerCommand('VBEINFO', @Run, 'Print out app.vbeinfo (VESA VGA).');
end;

end.