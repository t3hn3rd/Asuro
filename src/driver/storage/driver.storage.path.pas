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

{ Path syntax shared by VFS and boot consumers; no volume or driver access.
  Returned strings are caller-owned. Normalization is lexical, not symlink
  resolution, and never climbs above the root. }
unit driver.storage.path;

interface

function absolute(path, baseDir: pchar): pchar;
function normalize(path: pchar): pchar;
procedure UnitTest;

implementation

uses core.strings, core.util, memory.heap, arch.platform.diagnostics;

function absolute(path, baseDir: pchar): pchar;
var
    pathLen, baseLen, separator: uint32;
    result: pchar;
begin
    absolute := nil;
    if path = nil then begin
        absolute := stringCopy('/');
        exit;
    end;
    if path[0] = '/' then begin
        absolute := stringCopy(path);
        exit;
    end;
    if (baseDir = nil) or (baseDir[0] = #0) then baseDir := '/';
    pathLen := StringSize(path);
    baseLen := StringSize(baseDir);
    separator := 0;
    if baseDir[baseLen - 1] <> '/' then separator := 1;
    if pathLen >= High(uint32) - separator then exit;
    if baseLen >= High(uint32) - pathLen - separator then exit;

    result := stringNew(baseLen + separator + pathLen);
    if result = nil then exit;
    memcpy(PtrUInt(baseDir), PtrUInt(result), baseLen);
    if separator <> 0 then result[baseLen] := '/';
    memcpy(PtrUInt(path), PtrUInt(result) + baseLen + separator, pathLen);
    absolute := result;
end;

function normalize(path: pchar): pchar;
var
    length, readPos, start, count, used: uint32;
    result: pchar;
begin
    normalize := nil;
    if path = nil then path := '';
    length := StringSize(path);
    if length >= High(uint32) - 1 then exit;
    result := stringNew(length + 1);
    if result = nil then exit;
    result[0] := '/';
    used := 1;
    readPos := 0;

    while readPos < length do begin
        if path[readPos] = '/' then begin
            inc(readPos);
            continue;
        end;
        start := readPos;
        while (readPos < length) and (path[readPos] <> '/') do inc(readPos);
        count := readPos - start;
        if (count = 1) and (path[start] = '.') then continue;
        if (count = 2) and (path[start] = '.') and (path[start + 1] = '.') then begin
            while (used > 1) and (result[used - 1] <> '/') do dec(used);
            if used > 1 then dec(used);
        end else begin
            if used > 1 then begin
                result[used] := '/';
                inc(used);
            end;
            memcpy(PtrUInt(path) + start, PtrUInt(result) + used, count);
            inc(used, count);
        end;
    end;
    result[used] := #0;
    normalize := result;
end;

procedure UnitTest;
var
    passed, failed: uint32;
    beforeFree: SizeUInt;

    procedure Check(actual, expected: pchar);
    begin
        if StringEquals(actual, expected) then
            inc(passed)
        else begin
            inc(failed);
            log('PATH', 'FAIL: path result');
        end;
        kfree(void(actual));
    end;
begin
    passed := 0;
    failed := 0;
    beforeFree := lmm_total_free;
    Check(absolute('file', '/disk'), '/disk/file');
    Check(absolute('file', '/disk/'), '/disk/file');
    Check(absolute('/file', '/disk'), '/file');
    Check(absolute('file', ''), '/file');
    Check(absolute('file', nil), '/file');
    Check(absolute(nil, '/disk'), '/');
    Check(absolute('', '/disk'), '/disk/');
    Check(normalize('/a//b/./c/../..'), '/a');
    Check(normalize('../../a/..'), '/');
    Check(normalize('/a/../b/../c'), '/c');
    Check(normalize('a/b/'), '/a/b');
    Check(normalize('/.../.hidden'), '/.../.hidden');
    Check(normalize(''), '/');
    Check(normalize(nil), '/');
    if lmm_total_free = beforeFree then
        inc(passed)
    else begin
        inc(failed);
        log('PATH', 'FAIL: path allocation accounting');
    end;
    testSummary('PATH', 'PATH_TESTS_PASSED', 'PATH_TESTS_FAILED', passed, failed);
end;

end.
