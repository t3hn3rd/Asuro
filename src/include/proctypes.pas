{
    ProcTypes - Type definitions for the preemptive process management system.

    Defines process states, system messages, context records, and resource
    bindings used by processmanager.pas and contextswitcher.pas.

    @author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit proctypes;

interface

uses
    stdio;

const
    { 8 KB per-process kernel stack }
    PROCESS_STACK_SIZE = 8192;

    { Base quantum multiplier: quantum = Priority * BASE_QUANTUM ticks }
    BASE_QUANTUM = 5;

type
    { Forward declaration }
    PProcessContext = ^TProcessContext;

    { Process states }
    TProcessState = (
        psCreated,      { Allocated, stack prepared, not yet scheduled }
        psRunning,      { Currently executing on the main thread }
        psReady,        { Runnable but not the current process }
        psSuspended,    { Paused - will not be scheduled }
        psAwaiting,     { Blocked on I/O or event - will not be scheduled }
        psFinished,     { Terminal state - safe to reap }
        psError         { Unrecoverable error - safe to reap }
    );

    { System messages delivered to processes }
    TProcessSysMsg = (
        smNone,         { No message }
        smTerminate,    { Graceful shutdown requested }
        smKill,         { Immediate forced shutdown }
        smSuspend,      { Pause execution }
        smResume,       { Resume from suspended }
        smInput,        { New data available on stdin }
        smChildExited,  { A child process has exited }
        smCustom        { User-defined message (payload in MsgData) }
    );

    { Process entry point - a procedure that IS the process.
      When this procedure returns, the process is finished. }
    TProcessEntryPoint = procedure(ctx : PProcessContext);

    { Resource binding types }
    TResourceKind = (
        rkSocket,       { TCP/UDP socket }
        rkTimer,        { A timer hook }
        rkFileHandle,   { VFS file descriptor }
        rkCustom        { Arbitrary pointer }
    );

    { Resource cleanup callback }
    TResourceCleanup = procedure(handle : void);

    PResourceBinding = ^TResourceBinding;
    TResourceBinding = record
        Kind    : TResourceKind;
        Handle  : void;
        Cleanup : TResourceCleanup;
    end;

    { Process context - the core data structure for each process }
    TProcessContext = record
        { Identity }
        ProcessID   : uint32;
        Name        : array[0..31] of char;
        ParentID    : uint32;

        { State }
        State       : TProcessState;
        ExitCode    : uint32;

        { StdIO - per-process I/O buffers }
        StdIn       : POutBuf;
        StdOut      : POutBuf;
        StdErr      : POutBuf;

        { Entry point }
        EntryPoint  : TProcessEntryPoint;

        { Context switch state }
        SavedESP    : uint32;
        StackBase   : void;
        StackTop    : uint32;

        { Scheduling }
        Priority    : uint8;
        Quantum     : uint16;
        TicksUsed   : uint16;

        { System messages }
        PendingMsg  : TProcessSysMsg;
        MsgData     : void;

        { Resource bindings (PDList of TResourceBinding) }
        Resources   : void;

        { Per-process file descriptor table (PFDTable from fdtable.pas) }
        FDTable     : void;

        { Per-process working directory — heap-allocated, defaults to '/' }
        Cwd         : pchar;

        { User-defined state }
        Local       : void;
    end;

implementation

end.
