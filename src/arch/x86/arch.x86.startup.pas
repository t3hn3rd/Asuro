// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

{ Compose shared services with the i386 boot manager and platform commands. }
unit arch.x86.startup;
interface
implementation
uses boot.mgr, memory.heap, proc.mgr, io.stdio, arch.x86.console;
procedure consoleInit;
begin io.stdio.init; arch.x86.console.init; end;
initialization
    boot.mgr.registerBoot('memory.heap', @memory.heap.init, 'Heap Memory Manager', 'arch.*.memory.*');
    boot.mgr.registerBoot('io.stdio', @consoleInit, 'Standard I/O Abstraction', BOOT_MGR_BARRIER_EARLY);
    boot.mgr.registerBoot('proc.mgr', @proc.mgr.init, 'Process Manager', 'driver.storage.fs*');
end.
