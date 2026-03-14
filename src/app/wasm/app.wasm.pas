unit app.wasm;

interface

uses
    boot.mgr;

implementation

uses
    io.syslog,
    wasm.vm.io,
    wasm;

procedure init();
begin
    { Let's test Wasuro! }
    wasm.vm.io.io_set_writechar(@io.syslog.logchar);
    wasm.wasm_init;
end;

initialization
    boot.mgr.registerBoot('app.wasm', @init, 'Initialize WASM VM Backend', BOOT_MGR_BARRIER_FINAL)

end.