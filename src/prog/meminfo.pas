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
	Prog->meminfo - Print memory statistics (PMM / LMM).
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit meminfo;

interface

uses
    stdio, multiboot, pmemorymanager, lmemorymanager, tracer;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    pmm_total, pmm_free, pmm_used : uint32;
    lmm_pages, lmm_free           : uint32;
begin
    { Multiboot memory info }
    stdio.bufWriteStrLn(stdout_buf, '--- Multiboot ---');
    stdio.bufWriteStr(stdout_buf, 'Lower Memory  : ');
    stdio.bufWriteInt(stdout_buf, multibootinfo^.mem_lower);
    stdio.bufWriteStrLn(stdout_buf, ' KB');
    stdio.bufWriteStr(stdout_buf, 'Upper Memory  : ');
    stdio.bufWriteInt(stdout_buf, multibootinfo^.mem_upper);
    stdio.bufWriteStrLn(stdout_buf, ' KB');
    stdio.bufWriteStr(stdout_buf, 'Total Memory  : ');
    stdio.bufWriteInt(stdout_buf, ((multibootinfo^.mem_upper + 1000) div 1024) + 1);
    stdio.bufWriteStrLn(stdout_buf, ' MB');

    { PMM stats }
    stdio.bufWriteStrLn(stdout_buf, '--- PMM (4 MB blocks) ---');
    pmm_total := pmemorymanager.pmm_total_blocks;
    pmm_free  := pmemorymanager.pmm_free_blocks;
    pmm_used  := pmm_total - pmm_free;
    stdio.bufWriteStr(stdout_buf, 'Total Blocks  : ');
    stdio.bufWriteIntLn(stdout_buf, pmm_total);
    stdio.bufWriteStr(stdout_buf, 'Free Blocks   : ');
    stdio.bufWriteIntLn(stdout_buf, pmm_free);
    stdio.bufWriteStr(stdout_buf, 'Used Blocks   : ');
    stdio.bufWriteIntLn(stdout_buf, pmm_used);
    stdio.bufWriteStr(stdout_buf, 'Free Physical : ');
    stdio.bufWriteInt(stdout_buf, pmm_free * 4);
    stdio.bufWriteStrLn(stdout_buf, ' MB');

    { LMM heap stats }
    stdio.bufWriteStrLn(stdout_buf, '--- LMM (Heap) ---');
    lmm_pages := lmemorymanager.lmm_page_count;
    lmm_free  := lmemorymanager.lmm_total_free;
    stdio.bufWriteStr(stdout_buf, 'Heap Pages    : ');
    stdio.bufWriteIntLn(stdout_buf, lmm_pages);
    stdio.bufWriteStr(stdout_buf, 'Heap Size     : ');
    stdio.bufWriteInt(stdout_buf, lmm_pages * 4);
    stdio.bufWriteStrLn(stdout_buf, ' MB');
    stdio.bufWriteStr(stdout_buf, 'Heap Free     : ');
    stdio.bufWriteInt(stdout_buf, lmm_free div 1024);
    stdio.bufWriteStrLn(stdout_buf, ' KB');
end;

procedure init();
begin
    tracer.push_trace('meminfo.init');
    stdio.registerCommand('MEMINFO', @Run, 'Print memory statistics (PMM/LMM).');
end;

end.
