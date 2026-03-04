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
}
unit progmanager;

interface

uses
    tracer,
    //progs
    base64_prog, md5sum, dhclient, vbeinfo, testcmd, ping, meminfo;

{ Initialize all baked-in programs }
procedure init();

implementation

uses
    stdio,
    //command provider units
    kernel, cpu, drivermanagement, processmanager,
    arp, ipv4, tcp,
    storagemanagement, usbcore;

procedure init();
begin
    tracer.push_trace('progmanager.init');

    { Register commands from provider units }
    stdio.registerCommand('CPU', @cpu.Terminal_Command_CPU, 'CPU Info.');
    stdio.registerCommand('DEV', @drivermanagement.terminal_command_dev, 'Driver Management Interface.');
    stdio.registerCommand('PS', @processmanager.terminal_command_ps, 'List running processes.');
    stdio.registerCommand('KILL', @processmanager.terminal_command_kill, 'Force-kill a process by PID.');
    stdio.registerCommand('TERMINATE', @processmanager.terminal_command_terminate, 'Gracefully terminate a process by PID.');
    stdio.registerCommand('ARP', @arp.terminal_command_arp, 'Get ARP Table.');
    stdio.registerCommand('IFCONFIG', @ipv4.terminal_command_ifconfig, 'Configure Network Settings.');
    stdio.registerCommand('TCPCONNECT', @tcp.terminal_command_tcpconnect, 'Connect to a TCP host and send Hello World.');
    stdio.registerCommand('TCPLISTEN', @tcp.terminal_command_tcplisten, 'Listen on a TCP port and log received data.');
    stdio.registerCommand('TCPHTTP', @tcp.terminal_command_tcphttp, 'Send HTTP GET to a host IP (port 80 default).');
    stdio.registerCommand('DISK', @storagemanagement.disk_command, 'Disk utility');
    stdio.registerCommand('USB', @usbcore.terminal_command_usb, 'USB subsystem information.');

    { Initialize baked-in programs }
    md5sum.init();
    base64_prog.init();
    dhclient.init();
    vbeinfo.init();
    testcmd.init();
    ping.init();
    meminfo.init();
end;

end.