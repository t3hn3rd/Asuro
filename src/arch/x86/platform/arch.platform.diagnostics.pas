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

{ Build-selected x86 adapter. }
unit arch.platform.diagnostics;
interface
{$i ../../common/platform.diagnostics.inc}
implementation
uses io.syslog, debug.tracer, core.panic;
procedure log(tag, message: pchar);
begin io.syslog.logln(tag, message); end;
procedure push_trace(name: pchar);
begin debug.tracer.push_trace(name); end;
procedure pop_trace;
begin debug.tracer.pop_trace; end;
procedure fatal(tag, message: pchar);
begin core.panic.panic(tag, message, nil); end;
procedure testSummary(tag, passedKey, failedKey: pchar; passed, failed: uint32);
begin
    io.syslog.log(tag, '');
    io.syslog.writeint(passed); io.syslog.writestring(' passed, ');
    io.syslog.writeint(failed); io.syslog.writestringln(' failed.');
end;
end.
