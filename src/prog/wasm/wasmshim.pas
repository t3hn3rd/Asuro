{
    Prog->WASM->WASMShim - Bridges the Asuro process model to WASURO VM.

    Defines the shim record that ties a PProcessContext to a
    PWASMProcessContext, plus fault classification types.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit wasmshim;

interface

uses
    proctypes,
    wasm.types.context;

type
    { Fault classification — detected Asuro-side after wasm_tick returns false }
    TWASMFaultKind = (
        wfNone,                  { No fault — normal completion }
        wfInvalidBinary,         { Parse or validation failure }
        wfNoStartExport,         { _start not found in exports }
        wfUnexpectedHalt,        { Running=false with no ExitCode, IP < Limit }
        wfCodeOverrun,           { IP ran past code limit }
        wfUnknown                { Catch-all }
    );

    { The shim bridges Asuro process context to the WASURO VM context }
    PProcessWASMShim = ^TProcessWASMShim;
    TProcessWASMShim = record
        ProcessCtx  : PProcessContext;         { The owning Asuro process }
        WASMCtx     : PWASMProcessContext;     { The WASURO VM context }
        FileBuffer  : puint8;                  { kalloc'd buffer holding the .wasm file }
        FileSize    : uint32;                  { Size of the loaded file }
        FaultKind   : TWASMFaultKind;          { Fault classification after execution }
        FaultIP     : uint32;                  { IP at which fault occurred }
        ArgCount    : uint32;                  { Number of command-line arguments }
        ArgBuf      : pchar;                   { Flat buffer of null-terminated arg strings }
        ArgBufSize  : uint32;                  { Total byte size of ArgBuf }
    end;

implementation

end.
