# Asuro OS Architecture

## System Overview

```mermaid
flowchart TB
    subgraph USERSPACE [" User Space "]
        direction LR
        VTERM["VTerminal\nLVGL Terminal"]
        STDIO["Stdio\nCommands · Params"]
        PROGMGR["Prog Manager\nBuilt-in cmds"]
        FILEDISPATCH["File Dispatch\nMagic routing"]

        VTERM --- STDIO --- PROGMGR --- FILEDISPATCH
    end

    subgraph WASM_LAYER [" WASM Integration "]
        direction LR
        WASMRUNNER["WASM Runner\n1024 ticks/yield"]
        WASMSHIM["WASM Shim\nProcess ↔ VM"]
        WASMIO["WASM IO\nWASI ↔ StdIO"]
        WASURO["WASURO VM\nParser · WASI P1"]

        WASMRUNNER --- WASMSHIM --- WASMIO --- WASURO
    end

    subgraph PROC_LAYER [" Process Management "]
        direction LR
        PROCMGR["Process Manager\ncreate · kill · yield · reap"]
        CTXSW["Context Switcher\nISR32 · PUSHAD"]
        SCHED["Scheduler\nRound-robin · Priority"]

        PROCMGR --- CTXSW --- SCHED
    end

    subgraph GFX_LAYER [" Graphics "]
        direction LR
        LVGL["LVGL 9.x\nWidgets · Styles"]
        WINMGR["Window Manager\n16 windows · Z-order"]
        DESKTOP_W["Desktop\nDock · Launcher"]
        GFXREFRESH["GFX Refresh\n~256 FPS"]
        VIDEODRV["Video\nVESA · DoubleBuffer"]

        LVGL --- WINMGR --- DESKTOP_W --- GFXREFRESH --- VIDEODRV
    end

    subgraph SERVICES [" Services "]
        direction LR
        VFS["VFS\nPath resolution\n32 handles"]
        STORMGMT["Storage Mgmt\nDevices · Volumes"]
        NETSTACK["Network Stack\nETH → IP → TCP/UDP"]

        VFS --- STORMGMT --- NETSTACK
    end

    subgraph FILESYS [" Filesystems & NICs "]
        direction LR
        FAT32["FAT32\nCluster chains"]
        RAMDRIVE["RAM Drive\n/disk/ram"]
        E1000["E1000 NIC\nIntel I217"]

        FAT32 --- RAMDRIVE --- E1000
    end

    subgraph DRIVER_LAYER [" Drivers "]
        direction LR
        DRVMGMT["Driver Mgmt\nAuto-match"]
        IDE["IDE / ATA\nPIO R/W"]
        INPUT["Input\nPS/2 + USB\nKeyboard · Mouse"]
        USBSTACK["USB Stack\nUHCI · OHCI\nEHCI · XHCI"]

        DRVMGMT --- IDE --- INPUT --- USBSTACK
    end

    subgraph BUS_LAYER [" Bus "]
        PCI["PCI Bus — Config Space Enumeration — BAR · IRQ · Class"]
    end

    subgraph MEM_LAYER [" Memory "]
        direction LR
        LMM["Heap Allocator\nkalloc / kfree"]
        VMM["Virtual MM\nPage Directory"]
        PMM["Physical MM\n4MiB block bitmap"]

        LMM --- VMM --- PMM
    end

    subgraph CPU_LAYER [" CPU Primitives "]
        direction LR
        GDT["GDT\n4GB flat"]
        IDT["IDT\n256 gates"]
        ISR["ISR Manager\n+ Faults"]
        IRQ["IRQ\nPIC remap"]
        PIT["PIT Timer\n1024 Hz"]
        TSS["TSS\nRing 0 stack"]

        GDT --- IDT --- ISR --- IRQ --- PIT --- TSS
    end

    subgraph BOOT_LAYER [" Boot & Utilities "]
        direction LR
        MULTIBOOT["Multiboot\nGRUB"]
        SERIAL["Serial\nSyslog"]
        RTC["RTC\nBIOS Data"]
        UTIL["Strings · Lists\nHashmap · MD5\nRNG · Tracer"]

        MULTIBOOT --- SERIAL --- RTC --- UTIL
    end

    USERSPACE --> WASM_LAYER
    WASM_LAYER --> PROC_LAYER
    USERSPACE --> GFX_LAYER
    PROC_LAYER --> SERVICES
    GFX_LAYER --> SERVICES
    SERVICES --> FILESYS
    FILESYS --> DRIVER_LAYER
    DRIVER_LAYER --> BUS_LAYER
    BUS_LAYER --> MEM_LAYER
    MEM_LAYER --> CPU_LAYER
    CPU_LAYER --> BOOT_LAYER
```

## Boot Sequence

```mermaid
flowchart LR
    A["GRUB\nMultiboot"]
    B["Serial\nSyslog"]
    C["GDT · IDT\nIRQ"]
    D["PMM → VMM\n→ Heap"]
    E["Stdio · TSS\nScheduler"]
    F["Video\nVESA"]
    G["VFS\nDrivers · PCI"]
    H["FAT32 · USB\nNetwork"]
    I["LVGL\nDesktop"]
    J["Context\nSwitcher"]
    K(("Idle\nHLT"))

    A --> B --> C --> D --> E --> F --> G --> H --> I --> J --> K
```

## Memory Management

```mermaid
flowchart TB
    subgraph LMM [" Logical Memory Manager "]
        L1["kalloc(size) / kfree(ptr)"]
        L2["8-byte allocation units"]
        L3["16-byte size prefix · SSE aligned"]
        L4["klalloc for large multi-page"]
    end

    subgraph VMM [" Virtual Memory Manager "]
        V1["x86 Page Directory"]
        V2["Maps 4MiB physical → virtual"]
        V3["Kernel page directory"]
    end

    subgraph PMM [" Physical Memory Manager "]
        P1["1024 × 4MiB blocks"]
        P2["Dual bitmap: Present + Allocated"]
        P3["Reads multiboot memory map"]
    end

    LMM -->|"requests pages"| VMM
    VMM -->|"allocates blocks"| PMM
```

## Process Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created : create()
    Created --> Ready : scheduled

    Ready --> Running : picked by scheduler
    Running --> Ready : quantum expired

    Running --> Suspended : proc_suspend
    Suspended --> Ready : proc_resume

    Running --> Awaiting : proc_await
    Awaiting --> Ready : event fired

    Running --> Finished : proc_exit / return
    Running --> Error : fault

    Finished --> [*] : reaped
    Error --> [*] : reaped
```

## Network Stack

```mermaid
flowchart TB
    E1000["E1000 NIC Driver"]
    NIC["net.pas — NIC Interface"]
    ETH["Ethernet L2 — EtherType dispatch"]
    ARP["ARP — MAC ↔ IP cache"]
    IPV4["IPv4 — Routing · Fragmentation"]
    ICMP["ICMP — Ping"]
    TCP["TCP — Handshake · Retransmit"]
    UDP["UDP — Datagrams"]
    DHCP["DHCP Client — Auto-config"]

    E1000 --> NIC
    NIC --> ETH
    ETH --> ARP
    ETH --> IPV4
    IPV4 --> ICMP
    IPV4 --> TCP
    IPV4 --> UDP
    UDP --> DHCP
```

## USB Stack

```mermaid
flowchart TB
    PCI_D["PCI Discovery"]
    USB["USB Init"]
    UHCI["UHCI"]
    OHCI["OHCI"]
    EHCI["EHCI"]
    XHCI["XHCI"]
    CORE["USB Core\nEnumeration · Transfers"]
    HUB["Hub Driver"]
    HID_KB["USB Keyboard"]
    HID_MS["USB Mouse"]
    MSC["USB Mass Storage"]
    STOR["Storage Management"]

    PCI_D --> USB
    USB --> UHCI
    USB --> OHCI
    USB --> EHCI
    USB --> XHCI
    UHCI --> CORE
    OHCI --> CORE
    EHCI --> CORE
    XHCI --> CORE
    CORE --> HUB
    CORE --> HID_KB
    CORE --> HID_MS
    CORE --> MSC
    HUB -->|"downstream"| CORE
    MSC --> STOR
```

## Graphics Pipeline

```mermaid
flowchart LR
    subgraph RENDER [" Rendering "]
        VESA["VESA Driver\n8/16/24/32 BPP"]
        DBUF["Double Buffer\nSSE 128-bit copy"]
        VDRV["Video Abstraction"]

        VESA --> VDRV
        DBUF --> VDRV
    end

    subgraph UI [" UI Toolkit "]
        LVGL_G["LVGL 9.x"]
        WIN["Window Manager\n16 windows · Z-order"]
        DESK["Desktop\nDock · Launcher · Clock"]

        LVGL_G --> WIN --> DESK
    end

    subgraph LOOP [" Refresh Loop "]
        TMR["Timer Hook\n~256 FPS"]
    end

    TMR -->|"tick"| DESK
    TMR -->|"lv_handler"| LVGL_G
    TMR -->|"Flush"| VDRV
```

## Terminal Command Flow

```mermaid
flowchart LR
    A["User types\ncommand"]
    B["VTerminal\nparse input"]
    C{"Command\nregistered?"}
    D["stdio.findCommand\nexecute as process"]
    E{"File\nexists?"}
    F["filedispatch\ncheck magic bytes"]
    G["Error:\nunknown command"]
    H["wasmrunner\ncreate VM process"]
    I["Process Manager\npreemptive execution"]
    J["Output drains\nback to VTerminal"]

    A --> B --> C
    C -->|"Yes"| D --> I
    C -->|"No"| E
    E -->|"Yes"| F -->|"WASM magic"| H --> I
    E -->|"No"| G
    I --> J
```

## WASM Execution

```mermaid
flowchart TB
    subgraph LOAD [" Loading "]
        A["File Dispatch\nmatches 0x00 0x61 0x73 0x6D"]
        B["Read .wasm via VFS"]
        C["wasm_load — parse binary"]
        D["Create shim +\nserialize params"]

        A --> B --> C --> D
    end

    subgraph WIRE [" Wiring "]
        E["Wire WASI hooks\nfd_write · fd_read\nclock · random · args"]
        F["Register host functions"]
        G["Create preemptive process"]

        E --> F --> G
    end

    subgraph RUN [" Execution Loop "]
        H["wasm_prepare_start"]
        I{"Running?"}
        J["Execute 1024 opcodes"]
        K["proc_yield to scheduler"]
        L["Propagate exit code"]

        H --> I
        I -->|"Yes"| J --> K --> I
        I -->|"No"| L
    end

    LOAD --> WIRE --> RUN
```
