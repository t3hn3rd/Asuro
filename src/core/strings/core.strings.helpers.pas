{
    Core->StringHelpers - Reusable file-oriented search, sort, and format utilities.

    Provides:
      - getFileExtension: zero-copy extension extraction
      - fmtFileSize:      human-readable file size formatting (kalloc'd result)
      - sortStringArray:   in-place insertion sort on pchar arrays
      - sortStringArrayWithData: parallel insertion sort (pchar + uint32 arrays)

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit core.strings.helpers;

interface

type
    PPChar  = ^pchar;

{ Return a pointer into name at the last '.' (including the dot).
  Returns nil if there is no extension.  Zero-copy: does NOT allocate. }
function getFileExtension(name : pchar) : pchar;

{ Return a kalloc'd human-readable size string (e.g. '1.2 MB').
  Caller must kfree the result. }
function fmtFileSize(sz : uint32) : pchar;

{ In-place case-insensitive insertion sort on an array of n pchar pointers. }
procedure sortStringArray(arr : PPChar; n : uint32);

{ In-place case-insensitive insertion sort on an array of n pchar pointers,
  swapping a parallel uint32 data array in lockstep. }
procedure sortStringArrayWithData(arr : PPChar; data : puint32; n : uint32);

procedure UnitTest;

implementation

uses
    core.strings,
    memory.heap,
    io.syslog;

{ ============================================================
  getFileExtension
  Walk backwards from end of name to find the last '.'.
  Returns pointer into original string at the dot, or nil.
  ============================================================ }
function getFileExtension(name : pchar) : pchar;
var
    len : uint32;
    i   : uint32;
begin
    getFileExtension := nil;
    if name = nil then exit;
    len := stringSize(name);
    if len = 0 then exit;
    i := len;
    while i > 0 do begin
        i := i - 1;
        if name[i] = '.' then begin
            getFileExtension := @name[i];
            exit;
        end;
    end;
end;

{ ============================================================
  fmtFileSize
  Returns a kalloc'd human-readable size string.
  Caller must kfree the result.
  ============================================================ }
function fmtFileSize(sz : uint32) : pchar;
var
    whole, frac     : uint32;
    s1, s2, s3, res : pchar;
begin
    if sz < 1024 then begin
        s1  := intToString(sz);
        res := stringConcat(s1, ' B');
        kfree(void(s1));
    end else if sz < uint32(1024 * 1024) then begin
        whole := sz div 1024;
        frac  := (sz mod 1024) * 10 div 1024;
        s1  := intToString(whole);
        s2  := stringConcat(s1, '.');         kfree(void(s1));
        s3  := intToString(frac);
        s1  := stringConcat(s2, s3);          kfree(void(s2)); kfree(void(s3));
        res := stringConcat(s1, ' KB');       kfree(void(s1));
    end else begin
        whole := sz div (1024 * 1024);
        frac  := (sz mod (1024 * 1024)) * 10 div (1024 * 1024);
        s1  := intToString(whole);
        s2  := stringConcat(s1, '.');         kfree(void(s1));
        s3  := intToString(frac);
        s1  := stringConcat(s2, s3);          kfree(void(s2)); kfree(void(s3));
        res := stringConcat(s1, ' MB');       kfree(void(s1));
    end;
    fmtFileSize := res;
end;

{ ============================================================
  sortStringArray
  In-place insertion sort using stringCompareCI.
  Guarded for n=0 (Lesson #13).
  ============================================================ }
procedure sortStringArray(arr : PPChar; n : uint32);
var
    i, j : uint32;
    tmp  : pchar;
    p    : PPChar;
begin
    if (arr = nil) or (n < 2) then exit;
    if n > 1 then
        for i := 1 to n - 1 do begin
            p   := PPChar(pointer(uint32(arr) + i * sizeof(pchar)));
            tmp := p^;
            j   := i;
            while j > 0 do begin
                p := PPChar(pointer(uint32(arr) + (j - 1) * sizeof(pchar)));
                if stringCompareCI(tmp, p^) >= 0 then break;
                PPChar(pointer(uint32(arr) + j * sizeof(pchar)))^ := p^;
                j := j - 1;
            end;
            PPChar(pointer(uint32(arr) + j * sizeof(pchar)))^ := tmp;
        end;
end;

{ ============================================================
  sortStringArrayWithData
  In-place insertion sort on pchar array, swapping a parallel
  uint32 data array in lockstep.  Uses stringCompareCI.
  Guarded for n=0 (Lesson #13).
  ============================================================ }
procedure sortStringArrayWithData(arr : PPChar; data : puint32; n : uint32);
var
    i, j  : uint32;
    tmpN  : pchar;
    tmpD  : uint32;
    p     : PPChar;
    dp    : puint32;
begin
    if (arr = nil) or (n < 2) then exit;
    if n > 1 then
        for i := 1 to n - 1 do begin
            p    := PPChar(pointer(uint32(arr) + i * sizeof(pchar)));
            dp   := puint32(pointer(uint32(data) + i * sizeof(uint32)));
            tmpN := p^;
            tmpD := dp^;
            j    := i;
            while j > 0 do begin
                p := PPChar(pointer(uint32(arr) + (j - 1) * sizeof(pchar)));
                if stringCompareCI(tmpN, p^) >= 0 then break;
                PPChar(pointer(uint32(arr) + j * sizeof(pchar)))^ := p^;
                puint32(pointer(uint32(data) + j * sizeof(uint32)))^ :=
                    puint32(pointer(uint32(data) + (j - 1) * sizeof(uint32)))^;
                j := j - 1;
            end;
            PPChar(pointer(uint32(arr) + j * sizeof(pchar)))^ := tmpN;
            puint32(pointer(uint32(data) + j * sizeof(uint32)))^ := tmpD;
        end;
end;

{ ============================================================
  UnitTest
  ============================================================ }
procedure UnitTest;
var
    passed, failed : uint32;
    s : pchar;
    ext : pchar;
    names : array[0..4] of pchar;
    sizes : array[0..4] of uint32;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            io.syslog.logln('SEARCH', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr := intToString(passed);
        fStr := intToString(failed);
        msg  := stringConcat(pStr, ' passed, ');
        tmp  := stringConcat(msg, fStr);
        kfree(void(msg));
        msg := stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        io.syslog.logln('SEARCH', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    io.syslog.logln('SEARCH', 'Unit tests starting...');

    { === getFileExtension === }
    ext := getFileExtension('readme.txt');
    Assert(ext <> nil, 'getFileExt txt not nil');
    Assert(stringEquals(ext, '.txt'), 'getFileExt txt');
    ext := getFileExtension('archive.tar.gz');
    Assert(stringEquals(ext, '.gz'), 'getFileExt tar.gz');
    ext := getFileExtension('noext');
    Assert(ext = nil, 'getFileExt none');
    ext := getFileExtension('');
    Assert(ext = nil, 'getFileExt empty');
    ext := getFileExtension(nil);
    Assert(ext = nil, 'getFileExt nil');
    ext := getFileExtension('.hidden');
    Assert(stringEquals(ext, '.hidden'), 'getFileExt dotfile');

    { === fmtFileSize === }
    s := fmtFileSize(0);
    Assert(stringEquals(s, '0 B'), 'fmtFileSize 0');
    kfree(void(s));
    s := fmtFileSize(512);
    Assert(stringEquals(s, '512 B'), 'fmtFileSize 512');
    kfree(void(s));
    s := fmtFileSize(1024);
    Assert(stringEquals(s, '1.0 KB'), 'fmtFileSize 1KB');
    kfree(void(s));
    s := fmtFileSize(1024 * 1024);
    Assert(stringEquals(s, '1.0 MB'), 'fmtFileSize 1MB');
    kfree(void(s));

    { === sortStringArray === }
    names[0] := 'delta';
    names[1] := 'alpha';
    names[2] := 'Charlie';
    names[3] := 'bravo';
    names[4] := 'Echo';
    sortStringArray(@names[0], 5);
    Assert(stringEqualsCI(names[0], 'alpha'), 'sort[0]=alpha');
    Assert(stringEqualsCI(names[1], 'bravo'), 'sort[1]=bravo');
    Assert(stringEqualsCI(names[2], 'Charlie'), 'sort[2]=charlie');
    Assert(stringEqualsCI(names[3], 'delta'), 'sort[3]=delta');
    Assert(stringEqualsCI(names[4], 'Echo'), 'sort[4]=echo');

    { === sortStringArray edge cases === }
    sortStringArray(@names[0], 0);  { should not crash }
    sortStringArray(@names[0], 1);  { should not crash }
    sortStringArray(nil, 5);        { should not crash }

    { === sortStringArrayWithData === }
    names[0] := 'delta';  sizes[0] := 4;
    names[1] := 'alpha';  sizes[1] := 1;
    names[2] := 'Charlie'; sizes[2] := 3;
    names[3] := 'bravo';  sizes[3] := 2;
    names[4] := 'Echo';   sizes[4] := 5;
    sortStringArrayWithData(@names[0], @sizes[0], 5);
    Assert(stringEqualsCI(names[0], 'alpha'), 'sortData[0]=alpha');
    Assert(sizes[0] = 1, 'sortData[0] data=1');
    Assert(stringEqualsCI(names[4], 'Echo'), 'sortData[4]=echo');
    Assert(sizes[4] = 5, 'sortData[4] data=5');

    PrintSummary;
end;

end.
