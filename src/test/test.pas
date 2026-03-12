unit test;

interface

uses
    boot.mgr;

procedure init();
procedure runAllTests();

implementation

uses
    core.strings,
    driver.bus.usb.types,
    driver.bus.usb.core,
    driver.bus.usb.uhci,
    driver.bus.usb.ohci,
    driver.bus.usb.ehci,
    driver.bus.usb.xhci,
    driver.bus.usb.hub,
    driver.hid.usb.keyboard,
    driver.hid.usb.mouse,
    core.ds.fifo,
    core.ds.cfifo,
    core.ds.cfifols,
    core.ds.lifo,
    core.ds.circ,
    wasm.test,
    core.ds.minh,
    core.ds.maxh,
    core.ds.prio,
    driver.storage.vfs,
    driver.storage.test,
    core.enc.fnv1a,
    core.enc.djb2,
    core.ds.bloom,
    core.fmt.json;   

procedure init();
begin
    { Stub for now }
end;

procedure runAllTests();
begin
    { Run unit tests }
    core.strings.UnitTest;
    driver.bus.usb.types.UnitTest;
    driver.bus.usb.core.UnitTest;
    driver.bus.usb.uhci.UnitTest;
    driver.bus.usb.ohci.UnitTest;
    driver.bus.usb.ehci.UnitTest;
    driver.bus.usb.xhci.UnitTest;
    driver.bus.usb.hub.UnitTest;
    driver.hid.usb.keyboard.UnitTest;
    driver.hid.usb.mouse.UnitTest;
    core.ds.fifo.UnitTest;
    core.ds.cfifo.UnitTest;
    core.ds.cfifols.UnitTest;
    core.ds.lifo.UnitTest;
    core.ds.circ.UnitTest;
    wasm.test.run_all_tests;
    core.ds.minh.UnitTest;
    core.ds.maxh.UnitTest;
    core.ds.prio.UnitTest;
    driver.storage.vfs.UnitTest;
    driver.storage.test.UnitTest;
    core.enc.fnv1a.UnitTest;
    core.enc.djb2.UnitTest;
    core.ds.bloom.UnitTest;
    core.fmt.json.UnitTest;
end;

initialization
    boot.mgr.registerBoot('asuro.test.init', @init, 'Initialize Test Framework', BOOT_MGR_BARRIER_MID);
    boot.mgr.registerBoot('asuro.test.run', @runAllTests, 'Run Unit Tests', BOOT_MGR_BARRIER_LATE);

end.