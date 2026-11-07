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

{ VFS directory helpers extracted from io.stdio (Kieron Morris). }
unit io.directory;
interface
function getWorkingDirectory: pchar;
procedure setWorkingDirectory(str: pchar);
implementation
uses driver.storage.vfs;
function getWorkingDirectory: pchar;
begin
    getWorkingDirectory := driver.storage.vfs.GetWorkingDirectory;
end;

procedure setWorkingDirectory(str: pchar);
begin
    if str <> nil then
        driver.storage.vfs.ChangeDirectory(str);
end;

end.
