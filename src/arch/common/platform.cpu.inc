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

{ Shared contract; implemented by each build-selected adapter. }
function lock: PtrUInt;
procedure unlock(flags: PtrUInt);
procedure outb(port: uint16; value: uint8);
function inb(port: uint16): uint8;
procedure copyBytes(source, dest: PtrUInt; bytes: SizeUInt);
procedure zero(dest: pointer; bytes: SizeUInt);
procedure idle;
