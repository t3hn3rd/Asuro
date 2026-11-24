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

unit boot.services;

interface
procedure registerDevices;

implementation
uses boot.mgr, driver.net, driver.hid.ps2.keyboard, driver.hid.ps2.mouse,
     driver.hid.usb.keyboard, driver.hid.usb.mouse, driver.storage.ctl.usb,
     driver.storage.bench, driver.storage.perftest;

procedure registerDevices;
begin
    boot.mgr.registerBoot('driver.net', @driver.net.init, 'Net Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.ps2.keyboard', @driver.hid.ps2.keyboard.init, 'PS/2 Keyboard Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.ps2.mouse', @driver.hid.ps2.mouse.init, 'PS/2 Mouse Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.usb.keyboard', @driver.hid.usb.keyboard.init, 'USB Keyboard Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.usb.mouse', @driver.hid.usb.mouse.init, 'USB Mouse Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.storage.ctl.usb', @driver.storage.ctl.usb.init, 'USB Mass Storage Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.storage.perftest', @driver.storage.perftest.init, 'Storage Performance Tests', BOOT_MGR_BARRIER_MID);
    boot.mgr.registerBoot('driver.storage.bench', @driver.storage.bench.init, 'Storage Benchmark', BOOT_MGR_BARRIER_LATE);
end;

end.
