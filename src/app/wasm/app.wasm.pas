unit app.wasm;

interface

procedure init;

implementation

uses
    io.syslog,
    wasm.vm.io,
    wasm;

var
    initialized: boolean = false;

procedure init;
begin
    if initialized then exit;
    wasm.vm.io.io_set_writechar(@io.syslog.logchar);
    wasm.wasm_init;
    initialized := true;
end;

end.
