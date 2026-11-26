unit core.fmt.cbor.values;

{$MODESWITCH RESULT}
{$POINTERMATH ON}

interface

uses
    core.fmt.cbor, core.ds.hashmap;

type
    PCBORValue = ^TCBORValue;
    PPCBORValue = ^PCBORValue;
    TCBORValue = record
        Head : TCBORHead;
        case TCBORKind of
            cborBytes, cborText: (Data : PUInt8);
            cborArray: (Items : PPCBORValue; ItemCount : SizeUInt);
            cborMap: (Map : PHashMap);
            cborTag: (Tagged : PCBORValue);
    end;

{ Parse one complete item and copy its data. On failure, root is nil.
  Maps accept text keys without embedded NULs. Duplicate keys are invalid.
  Indefinite strings and containers are normalised to their definite kinds. }
function Parse(buffer : PUInt8; size : SizeUInt; var root : PCBORValue) : TCBORStatus;

{ Return borrowed values or nil for missing keys, invalid indices or kinds. }
function GetMapItem(value : PCBORValue; key : PChar) : PCBORValue;
function GetArrayItem(value : PCBORValue; index : SizeUInt) : PCBORValue;
function GetArraySize(value : PCBORValue) : SizeUInt;

{ Return borrowed string data and its byte length. Text has a trailing NUL
  for convenience and may contain embedded NULs. The length excludes the terminator. }
function GetString(value : PCBORValue; var data : PUInt8; var length : SizeUInt) : Boolean;

{ Release a root and all descendants. Passing nil is safe. }
procedure FreeValue(value : PCBORValue);

implementation

uses
    memory.heap, core.util;

function GetMapItem(value : PCBORValue; key : PChar) : PCBORValue;
begin
    Result := nil;
    if value = nil then Exit;
    if value^.Head.Kind = cborMap then
        Result := PCBORValue(core.ds.hashmap.get(value^.Map, key));
end;

function GetArraySize(value : PCBORValue) : SizeUInt;
begin
    Result := 0;
    if value = nil then Exit;
    if value^.Head.Kind = cborArray then Result := value^.ItemCount;
end;

function GetArrayItem(value : PCBORValue; index : SizeUInt) : PCBORValue;
begin
    Result := nil;
    if index < GetArraySize(value) then Result := value^.Items[index];
end;

function GetString(value : PCBORValue; var data : PUInt8; var length : SizeUInt) : Boolean;
begin
    Result := False;
    if value = nil then Exit;
    if not (value^.Head.Kind in [cborText, cborBytes]) then Exit;
    data := value^.Data;
    length := SizeUInt(value^.Head.Argument);
    Result := True;
end;

procedure FreeValue(value : PCBORValue);
var
    i : SizeUInt;
    item, next : PHashItem;
begin
    if value = nil then Exit;
    case value^.Head.Kind of
        cborBytes, cborText:
            if value^.Data <> nil then kfree(void(value^.Data));
        cborArray: begin
            i := 0;
            while i < value^.ItemCount do begin
                FreeValue(value^.Items[i]);
                Inc(i);
            end;
            if value^.Items <> nil then kfree(void(value^.Items));
        end;
        cborMap:
            if value^.Map <> nil then begin
                for i := 0 to value^.Map^.Size - 1 do begin
                    item := value^.Map^.Table[i];
                    while item <> nil do begin
                        next := item^.Next;
                        FreeValue(PCBORValue(item^.Data));
                        kfree(void(item^.Key));
                        kfree(void(item));
                        item := next;
                    end;
                end;
                kfree(void(value^.Map^.Table));
                kfree(void(value^.Map));
            end;
        cborTag: FreeValue(value^.Tagged);
    end;
    kfree(void(value));
end;

{ Parse is preceded by a full wire validation pass. Offsets and lengths
  below therefore describe complete, structurally valid items. }
function ReadValue(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                   var value : PCBORValue) : TCBORStatus; forward;

function ReadPayload(buffer : PUInt8; size : SizeUInt; start : SizeUInt;
                     var offset : SizeUInt; value : PCBORValue) : TCBORStatus;
var
    head : TCBORHead;
    chunkKind : TCBORKind;
    payload : PUInt8;
    length, total, scan, copied : SizeUInt;
begin
    if value^.Head.Kind in [cborBytes, cborText] then begin
        scan := start;
        Result := ReadString(buffer, size, scan, payload, length, chunkKind);
        if Result <> cborOK then Exit;
        value^.Data := PUInt8(kalloc(length + 1));
        if length <> 0 then memcpy(PtrUInt(payload), PtrUInt(value^.Data), length);
        value^.Data[length] := 0;
        offset := scan;
        Exit;
    end;

    if value^.Head.Kind = cborIndefiniteText then value^.Head.Kind := cborText
    else value^.Head.Kind := cborBytes;
    scan := offset;
    total := 0;
    while buffer[scan] <> $FF do begin
        Result := ReadString(buffer, size, scan, payload, length, chunkKind);
        if Result <> cborOK then Exit;
        Inc(total, length);
    end;
    value^.Data := PUInt8(kalloc(total + 1));
    value^.Head.Argument := total;
    copied := 0;
    while offset < scan do begin
        Result := ReadString(buffer, size, offset, payload, length, chunkKind);
        if Result <> cborOK then Exit;
        if length <> 0 then memcpy(PtrUInt(payload), PtrUInt(value^.Data + copied), length);
        Inc(copied, length);
    end;
    value^.Data[total] := 0;
    Result := ReadHead(buffer, size, offset, head);
end;

function ReadArray(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                   value : PCBORValue) : TCBORStatus;
var
    count, scan : SizeUInt;
    indefinite : Boolean;
begin
    indefinite := value^.Head.Kind = cborIndefiniteArray;
    count := SizeUInt(value^.Head.Argument);
    if indefinite then begin
        scan := offset;
        while buffer[scan] <> $FF do begin
            Result := SkipItem(buffer, size, scan);
            if Result <> cborOK then Exit;
            Inc(count);
        end;
    end;
    value^.Head := MakeHead(cborArray, count);
    if count > High(SizeUInt) div SizeOf(PCBORValue) then begin
        Result := cborUnsupported;
        Exit;
    end;
    if count <> 0 then value^.Items := PPCBORValue(kalloc(count * SizeOf(PCBORValue)));
    while value^.ItemCount < count do begin
        Result := ReadValue(buffer, size, offset, value^.Items[value^.ItemCount]);
        if Result <> cborOK then Exit;
        Inc(value^.ItemCount);
    end;
    if indefinite then Inc(offset);
    Result := cborOK;
end;

function ReadMap(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                 value : PCBORValue) : TCBORStatus;
var
    count, i : SizeUInt;
    indefinite : Boolean;
    key, child : PCBORValue;
begin
    indefinite := value^.Head.Kind = cborIndefiniteMap;
    count := SizeUInt(value^.Head.Argument);
    value^.Head := MakeHead(cborMap, 0);
    value^.Map := core.ds.hashmap.new;
    while True do begin
        if indefinite then begin
            if buffer[offset] = $FF then Break;
        end else if value^.Head.Argument = count then Break;
        if (buffer[offset] shr 5) <> 3 then begin
            Result := cborUnsupported;
            Exit;
        end;
        Result := ReadValue(buffer, size, offset, key);
        if Result <> cborOK then Exit;
        i := 0;
        while i < key^.Head.Argument do begin
            if key^.Data[i] = 0 then Break;
            Inc(i);
        end;

        if i <> key^.Head.Argument then Result := cborUnsupported
        else if GetMapItem(value, PChar(key^.Data)) <> nil then Result := cborInvalid
        else begin
            Result := ReadValue(buffer, size, offset, child);
            if Result = cborOK then begin
                core.ds.hashmap.add(value^.Map, PChar(key^.Data), void(child));
                Inc(value^.Head.Argument);
            end;
        end;
        FreeValue(key);
        if Result <> cborOK then Exit;
    end;
    if indefinite then Inc(offset);
    Result := cborOK;
end;

function ReadValue(buffer : PUInt8; size : SizeUInt; var offset : SizeUInt;
                   var value : PCBORValue) : TCBORStatus;
var
    head : TCBORHead;
    start : SizeUInt;
begin
    value := nil;
    start := offset;
    Result := ReadHead(buffer, size, offset, head);
    if Result <> cborOK then Exit;
    value := PCBORValue(kalloc(SizeOf(TCBORValue)));
    memset(PtrUInt(value), 0, SizeOf(TCBORValue));
    value^.Head := head;
    case head.Kind of
        cborBytes, cborText, cborIndefiniteBytes, cborIndefiniteText:
            Result := ReadPayload(buffer, size, start, offset, value);
        cborArray, cborIndefiniteArray: Result := ReadArray(buffer, size, offset, value);
        cborMap, cborIndefiniteMap: Result := ReadMap(buffer, size, offset, value);
        cborTag: Result := ReadValue(buffer, size, offset, value^.Tagged);
    end;
    if Result <> cborOK then begin
        FreeValue(value);
        value := nil;
    end;
end;

function Parse(buffer : PUInt8; size : SizeUInt; var root : PCBORValue) : TCBORStatus;
var
    offset : SizeUInt;
begin
    root := nil;
    Result := Validate(buffer, size);
    if Result <> cborOK then Exit;
    offset := 0;
    Result := ReadValue(buffer, size, offset, root);
end;

end.
