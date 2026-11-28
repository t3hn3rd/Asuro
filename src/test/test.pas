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
    boot.mgr,
    io.syslog,
    test.harness;

procedure init();
procedure runAllTests();

implementation

uses
    {$IFDEF TEST_ONLY}
    arch.common.power,
    {$ENDIF}
    {$if defined(CPUX86_64) and defined(UNIT_TESTS)}arch.x86_64.regression,{$endif}
    {$if defined(CPUX86_64) and defined(UNIT_TESTS_COMPLEX)}arch.x86_64.test.storage,{$endif}
    core.strings,
    core.strings.helpers,
    core.ds.lists,
    core.ds.hashmap,
    driver.storage.iorequest, driver.storage.path, driver.storage.fs.mgr,
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
    {$ifndef CPUX86_64}wasm.test,{$endif}
    core.ds.minh,
    core.ds.maxh,
    core.ds.prio,
    driver.storage.vfs,
    {$ifndef CPUX86_64}driver.storage.test,{$endif}
    driver.storage.bench,
    core.clock,
    driver.storage.metatest,
    driver.storage.perftest,
    driver.storage.ctl.ahci,
    driver.storage.ctl.usb,
    core.comp.lzw,
    core.comp.lz4,
    core.comp.deflate,
    core.enc.fnv1a,
    core.enc.djb2, core.enc.sha1,
    core.ds.bloom,
    core.fmt.png,
    core.fmt.json,
    core.fmt.cbor.tests;

procedure init();
begin
    { Initialize the test harness }
    test.harness.init;
end;

procedure runAllTests();
begin
    io.syslog.logln('test', 'Running all standard unit tests...');

    { Run unit tests }
    {$if defined(CPUX86_64) and defined(UNIT_TESTS)}arch.x86_64.regression.UnitTest;{$endif}
    core.strings.UnitTest;
    core.strings.helpers.UnitTest;
    core.ds.lists.TestAllLists;
    core.ds.hashmap.UnitTest;
    driver.storage.iorequest.UnitTest;
    driver.storage.path.UnitTest;
    driver.storage.fs.mgr.UnitTest;
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
    {$ifndef CPUX86_64}wasm.test.run_all_tests;{$endif}
    core.ds.minh.UnitTest;
    core.ds.maxh.UnitTest;
    core.ds.prio.UnitTest;
    driver.storage.vfs.UnitTest;
    {$ifndef CPUX86_64}driver.storage.test.UnitTest;{$endif}
    driver.storage.ctl.ahci.UnitTest;
    driver.storage.ctl.usb.UnitTest;
    core.comp.lzw.UnitTest;
    core.comp.lz4.UnitTest;
    core.comp.deflate.UnitTest;
    core.fmt.png.UnitTest;
    core.enc.fnv1a.UnitTest;
    core.enc.djb2.UnitTest;
    core.enc.sha1.UnitTest;
    core.ds.bloom.UnitTest;
end;

procedure runComplexTests();
begin
    io.syslog.logln('test', 'Running complex unit tests...');

    { Run complex unit tests }
    core.fmt.json.UnitTest;
    core.fmt.cbor.tests.UnitTest;
    core.clock.UnitTest;
    driver.storage.bench.UnitTest;
    driver.storage.metatest.UnitTest;
    driver.storage.perftest.UnitTest;
    {$if defined(CPUX86_64) and defined(UNIT_TESTS_COMPLEX)}arch.x86_64.test.storage.run;{$endif}
end;

procedure finish();
begin
    { Finished }
    io.syslog.logln('test', 'Unit tests finished.');

    { Print the test harness results }
    test.harness.print;
    {$IFDEF TEST_ONLY}
        arch.common.power.powerOff;
    {$ENDIF}
end;

initialization
    {$IFDEF UNIT_TESTS}
        boot.mgr.registerBoot('asuro.test.init', @init, 'Initialize Test Framework', BOOT_MGR_BARRIER_MID);
        boot.mgr.registerBoot('asuro.test.run.standard', @runAllTests, 'Run Unit Tests', BOOT_MGR_BARRIER_LATE);
        {$IFDEF UNIT_TESTS_COMPLEX}
            boot.mgr.registerBoot('asuro.test.run.complex', @runComplexTests, 'Run Complex Unit Tests', 'asuro.test.run.standard');
        {$ENDIF}
        boot.mgr.registerBoot('asuro.test.finish', @finish, 'Finish Unit Tests', 'asuro.test.run.*');
    {$ENDIF}

end.
