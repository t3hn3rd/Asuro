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

{ Build-selected x86_64 adapter. }
unit arch.platform.diagnostics;

interface
{$i ../../common/platform.diagnostics.inc}

implementation
uses debug.early;

procedure log(tag, message: pchar);
begin
    debug.early.puts(message);
    debug.early.puts(#13#10);
end;

procedure push_trace(name: pchar);
begin
end;

procedure pop_trace;
begin
end;

procedure fatal(tag, message: pchar);
begin
    log(tag, message);
    bootstrap_halt;
end;

procedure testSummary(tag, passedKey, failedKey: pchar; passed, failed: uint32);
begin
    debug.early.field(passedKey, passed);
    debug.early.field(failedKey, failed);
end;
end.
