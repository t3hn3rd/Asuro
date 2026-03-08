# app.meminfo

Terminal command for displaying physical and heap memory statistics.

## Overview

`app.meminfo` registers the `MEMINFO` shell command, which prints a summary of the system's memory state in three sections: Multiboot-reported memory ranges, Physical Memory Manager (PMM) block statistics, and Logical Memory Manager (LMM) heap statistics.

## Dependencies

- `io.stdio`
- `arch.x86.multiboot`
- `arch.x86.memory.physical`
- `memory.heap`
- `debug.tracer`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `MEMINFO` command with `io.stdio`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Outputs three labelled sections:

**Multiboot:** Reads `multibootinfo^.mem_lower` and `mem_upper` to report lower memory, upper memory, and total memory in KB/MB.

**PMM (4 MB blocks):** Reads `arch.x86.memory.physical.pmm_total_blocks`, `pmm_free_blocks`, and derives used blocks. Reports free physical memory in MB.

**LMM (Heap):** Reads `memory.heap.lmm_page_count` and `lmm_total_free`. Reports heap size in MB and free heap in KB.

All output is written to `stdout_buf`.
