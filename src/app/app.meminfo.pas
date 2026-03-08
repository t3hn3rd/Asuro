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
    io.stdio, arch.x86.multiboot, arch.x86.memory.physical, memory.heap, debug.tracer;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    pmm_total, pmm_free, pmm_used : uint32;
    lmm_pages, lmm_free           : uint32;
begin
    { Multiboot memory info }
    io.stdio.bufWriteStrLn(stdout_buf, '--- Multiboot ---');
    io.stdio.bufWriteStr(stdout_buf, 'Lower Memory  : ');
    io.stdio.bufWriteInt(stdout_buf, multibootinfo^.mem_lower);
    io.stdio.bufWriteStrLn(stdout_buf, ' KB');
    io.stdio.bufWriteStr(stdout_buf, 'Upper Memory  : ');
    io.stdio.bufWriteInt(stdout_buf, multibootinfo^.mem_upper);
    io.stdio.bufWriteStrLn(stdout_buf, ' KB');
    io.stdio.bufWriteStr(stdout_buf, 'Total Memory  : ');
    io.stdio.bufWriteInt(stdout_buf, ((multibootinfo^.mem_upper + 1000) div 1024) + 1);
    io.stdio.bufWriteStrLn(stdout_buf, ' MB');

    { PMM stats }
    io.stdio.bufWriteStrLn(stdout_buf, '--- PMM (4 MB blocks) ---');
    pmm_total := arch.x86.memory.physical.pmm_total_blocks;
    pmm_free  := arch.x86.memory.physical.pmm_free_blocks;
    pmm_used  := pmm_total - pmm_free;
    io.stdio.bufWriteStr(stdout_buf, 'Total Blocks  : ');
    io.stdio.bufWriteIntLn(stdout_buf, pmm_total);
    io.stdio.bufWriteStr(stdout_buf, 'Free Blocks   : ');
    io.stdio.bufWriteIntLn(stdout_buf, pmm_free);
    io.stdio.bufWriteStr(stdout_buf, 'Used Blocks   : ');
    io.stdio.bufWriteIntLn(stdout_buf, pmm_used);
    io.stdio.bufWriteStr(stdout_buf, 'Free Physical : ');
    io.stdio.bufWriteInt(stdout_buf, pmm_free * 4);
    io.stdio.bufWriteStrLn(stdout_buf, ' MB');

    { LMM heap stats }
    io.stdio.bufWriteStrLn(stdout_buf, '--- LMM (Heap) ---');
    lmm_pages := memory.heap.lmm_page_count;
    lmm_free  := memory.heap.lmm_total_free;
    io.stdio.bufWriteStr(stdout_buf, 'Heap Pages    : ');
    io.stdio.bufWriteIntLn(stdout_buf, lmm_pages);
    io.stdio.bufWriteStr(stdout_buf, 'Heap Size     : ');
    io.stdio.bufWriteInt(stdout_buf, lmm_pages * 4);
    io.stdio.bufWriteStrLn(stdout_buf, ' MB');
    io.stdio.bufWriteStr(stdout_buf, 'Heap Free     : ');
    io.stdio.bufWriteInt(stdout_buf, lmm_free div 1024);
    io.stdio.bufWriteStrLn(stdout_buf, ' KB');
end;

procedure init();
begin
    debug.tracer.push_trace('meminfo.init');
    io.stdio.registerCommand('MEMINFO', @Run, 'Print memory statistics (PMM/LMM).');
end;

end.
