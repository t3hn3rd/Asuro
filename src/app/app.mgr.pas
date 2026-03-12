//  Copyright 2021 Kieron Morris
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
	ProgManager - Central initialization for terminal registered, baked-in programs.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.mgr;

interface

uses
    boot.mgr,
    debug.tracer, io.stdio, proc.mgr,
    //progs
    app.base64, app.md5sum, app.dhclient, app.vbeinfo, app.testcmd, app.ping, app.meminfo, app.setres,
    //drivers
    driver.storage.ctl.ram, driver.mgr,
    //network
    driver.net.proto.ipv4, driver.net.proto.arp, driver.net.proto.tcp,
    //dispatch
    driver.storage.filedispatch,
    //wasm
    app.wasm.runner,
    app.divzero,
    app.bsod,
    app.vterminal,
    app.filebrowser;

{ Initialize all baked-in programs }
procedure init();

implementation

uses
    core.version,
    //command provider units
    arch.x86.cpu,
    app.diskcmd, driver.bus.usb.core, app.diskutil, app.notepad, app.partcmd, app.volcmd,
    app.filebrowser;

procedure init();
begin
    debug.tracer.push_trace('app.mgr.init');

    { Register commands from provider units }
    io.stdio.registerCommand('CPU', @arch.x86.cpu.Terminal_Command_CPU, 'CPU Info.');
    io.stdio.registerCommand('DEV', @driver.mgr.terminal_command_dev, 'Driver Management Interface.');
    io.stdio.registerCommand('PS', @proc.mgr.terminal_command_ps, 'List running processes.');
    io.stdio.registerCommand('KILL', @proc.mgr.terminal_command_kill, 'Force-kill a process by PID.');
    io.stdio.registerCommand('TERMINATE', @proc.mgr.terminal_command_terminate, 'Gracefully terminate a process by PID.');
    io.stdio.registerCommand('ARP', @driver.net.proto.arp.terminal_command_arp, 'Get ARP Table.');
    io.stdio.registerCommand('IFCONFIG', @driver.net.proto.ipv4.terminal_command_ifconfig, 'Configure Network Settings.');
    io.stdio.registerCommand('TCPCONNECT', @driver.net.proto.tcp.terminal_command_tcpconnect, 'Connect to a TCP host and send Hello World.');
    io.stdio.registerCommand('TCPLISTEN', @driver.net.proto.tcp.terminal_command_tcplisten, 'Listen on a TCP port and log received data.');
    io.stdio.registerCommand('TCPHTTP', @driver.net.proto.tcp.terminal_command_tcphttp, 'Send HTTP GET to a host IP (port 80 default).');
    io.stdio.registerCommand('USB', @driver.bus.usb.core.terminal_command_usb, 'driver.bus.usb subsystem information.');

    { File dispatch — must init before apps that register handlers }
    driver.storage.ctl.ram.init();
    driver.storage.filedispatch.init();

    { Initialize baked-in programs }
    app.diskcmd.init();
    app.partcmd.init();
    app.volcmd.init();
    app.diskutil.init();
    app.notepad.init();
    app.md5sum.init();
    app.base64.init();
    app.dhclient.init();
    app.vbeinfo.init();
    app.testcmd.init();
    app.ping.init();
    app.meminfo.init();
    { WASM & remaining apps }
    app.wasm.runner.init();
    app.setres.init();
    app.divzero.init();
    app.bsod.init();
    app.vterminal.init;
    app.filebrowser.init();
end;

Initialization
    boot.mgr.registerBoot('app.mgr', @init, 'Program Manager', BOOT_MGR_BARRIER_LATE);

end.