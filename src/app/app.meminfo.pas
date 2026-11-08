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
	Prog->app.meminfo - Print memory statistics (PMM / LMM).
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.meminfo;

interface

uses
    io.stdio, arch.platform.memory, memory.heap, debug.tracer;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    total, available: uint64;
    heapPages: uint32;
begin
    total := arch.platform.memory.totalPhysicalBytes;
    available := arch.platform.memory.freePhysicalBytes;
    io.stdio.bufWriteStr(stdout_buf, 'Usable Physical: ');
    io.stdio.bufWriteInt(stdout_buf, total div 1024);
    io.stdio.bufWriteStrLn(stdout_buf, ' KiB');
    io.stdio.bufWriteStr(stdout_buf, 'Free Physical  : ');
    io.stdio.bufWriteInt(stdout_buf, available div 1024);
    io.stdio.bufWriteStrLn(stdout_buf, ' KiB');
    io.stdio.bufWriteStr(stdout_buf, 'Used Physical  : ');
    io.stdio.bufWriteInt(stdout_buf, (total - available) div 1024);
    io.stdio.bufWriteStrLn(stdout_buf, ' KiB');
    heapPages := memory.heap.lmm_page_count;
    io.stdio.bufWriteStr(stdout_buf, 'Heap Regions   : ');
    io.stdio.bufWriteIntLn(stdout_buf, heapPages);
    io.stdio.bufWriteStr(stdout_buf, 'Heap Size      : ');
    io.stdio.bufWriteInt(stdout_buf, uint64(heapPages) * PAGE_SIZE_LMM div 1024);
    io.stdio.bufWriteStrLn(stdout_buf, ' KiB');
    io.stdio.bufWriteStr(stdout_buf, 'Heap Free      : ');
    io.stdio.bufWriteInt(stdout_buf, memory.heap.lmm_total_free div 1024);
    io.stdio.bufWriteStrLn(stdout_buf, ' KiB');
end;
procedure init();
begin
    debug.tracer.push_trace('meminfo.init');
    io.stdio.registerCommand('MEMINFO', @Run, 'Print memory statistics (PMM/LMM).');
end;

end.
