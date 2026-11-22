//  Copyright 2026 Aaron Hance
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
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit test;

interface

uses
    boot.mgr;

procedure init();
procedure runAllTests();

implementation

uses
    core.strings,
    app.diskutil,
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
    driver.storage.bench,
    driver.storage.metatest,
    driver.storage.perftest,
    driver.storage.ctl.ahci,
    driver.storage.ctl.usb,
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
    app.diskutil.UnitTest;
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
    driver.storage.bench.UnitTest;
    driver.storage.metatest.UnitTest;
    driver.storage.perftest.UnitTest;
    driver.storage.ctl.ahci.UnitTest;
    driver.storage.ctl.usb.UnitTest;
    core.enc.fnv1a.UnitTest;
    core.enc.djb2.UnitTest;
    core.ds.bloom.UnitTest;
    core.fmt.json.UnitTest;
end;

initialization
    boot.mgr.registerBoot('asuro.test.init', @init, 'Initialize Test Framework', BOOT_MGR_BARRIER_MID);
    boot.mgr.registerBoot('asuro.test.run', @runAllTests, 'Run Unit Tests', BOOT_MGR_BARRIER_LATE);

end.