// Copyright 2021 Kieron Morris & Aaron Hance
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

{ Shared dispatch for the table emitted by compile_initcalls.sh.
  Initializers only register boot work or set globals; they cannot depend on
  heap, hardware setup, or the alphabetical order of this generated table. }
var
    unitsInitialized: boolean;

procedure initializeUnits;
var
    i: longint;
    entry: CodePointer;
begin
    if unitsInitialized then exit;
    unitsInitialized := true;

    for i := 1 to InitFinalTable.TableCount do begin
        entry := InitFinalTable.Procs[i].InitProc;
        if entry <> nil then
            TProcedure(entry)();
    end;
end;
