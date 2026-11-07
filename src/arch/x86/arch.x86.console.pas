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

{ Commands extracted from io.stdio (Kieron Morris). }
unit arch.x86.console;
interface
procedure init;
implementation
uses io.stdio, core.version, driver.timer.rtc, arch.x86.util;
procedure cmd_version(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
begin
    bufWriteStr(stdout_buf, '  Asuro Version: ');
    bufWriteStrLn(stdout_buf, core.version.VERSION);
    bufWriteStr(stdout_buf, '  Compiled on: ');
    bufWriteStr(stdout_buf, core.version.COMPILE_DATE);
    bufWriteStr(stdout_buf, ' ');
    bufWriteStrLn(stdout_buf, core.version.COMPILE_TIME);
    bufWriteStrLn(stdout_buf, '  Compiled With: ');
    bufWriteStr(stdout_buf, '    NASM - Version: ');
    bufWriteStrLn(stdout_buf, core.version.NASM_VERSION);
    bufWriteStr(stdout_buf, '    FPC  - Version: ');
    bufWriteStrLn(stdout_buf, core.version.FPC_VERSION);
    bufWriteStr(stdout_buf, '    MAKE - Version: ');
    bufWriteStrLn(stdout_buf, core.version.MAKE_VERSION);
    bufWriteStr(stdout_buf, '  ');
    bufWriteInt(stdout_buf, core.version.LINE_COUNT);
    bufWriteStr(stdout_buf, ' lines, across ');
    bufWriteInt(stdout_buf, core.version.FILE_COUNT);
    bufWriteStrLn(stdout_buf, ' files.');
    bufWriteStr(stdout_buf, '  Baked Drivers: ');
    bufWriteIntLn(stdout_buf, core.version.DRIVER_COUNT);
    bufWriteStr(stdout_buf, '  Checksum: ');
    bufWriteStrLn(stdout_buf, core.version.CHECKSUM);
end;

procedure cmd_time(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    dt: TDateTime;
begin
    dt := getDateTime;
    if dt.Day < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Day);
    bufWriteChar(stdout_buf, '/');
    if dt.Month < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Month);
    bufWriteChar(stdout_buf, '/');
    bufWriteInt(stdout_buf, dt.Century);
    bufWriteInt(stdout_buf, dt.Year);
    bufWriteChar(stdout_buf, ' ');
    if dt.Hours < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Hours);
    bufWriteChar(stdout_buf, ':');
    if dt.Minutes < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Minutes);
    bufWriteChar(stdout_buf, ':');
    if dt.Seconds < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteIntLn(stdout_buf, dt.Seconds);
    bufWriteStr(stdout_buf, 'Weekday: ');
    bufWriteStrLn(stdout_buf, WeekdayToString(dt.Weekday));
end;

procedure cmd_reboot(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
begin
    resetSystem;
end;

procedure init;
begin
    registerCommand('VERSION', @cmd_version, 'Display the running version of Asuro.');
    registerCommand('TIME', @cmd_time, 'Print the current time.');
    registerCommand('REBOOT', @cmd_reboot, 'Reboot the system.');
end;
end.
