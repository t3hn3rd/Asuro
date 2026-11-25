unit svc.registry;

{$MODESWITCH RESULT}
{$POINTERMATH ON}

interface

uses
    driver.storage.types;

const
    REGISTRY_DEFAULT_CACHE_BYTES = 50 * 1024 * 1024;

    REGISTRY_UINT32 = 1;
    REGISTRY_UINT8 = 2;
    REGISTRY_UINT16 = 3;
    REGISTRY_UINT64 = 4;
    REGISTRY_INT8 = 5;
    REGISTRY_INT16 = 6;
    REGISTRY_INT32 = 7;
    REGISTRY_INT64 = 8;
    REGISTRY_FLOAT32 = 9;
    REGISTRY_FLOAT64 = 10;
    REGISTRY_TEXT = 11;
    REGISTRY_BOOLEAN = 12;
    REGISTRY_BYTES = 13;

{ Set the value cache budget before the registry mounts. }
procedure SetCacheBudget(bytes : uint32);
{ Readiness means the initial scan is complete, even without a database.
  WaitReady is for scheduled processes. }
function IsReady : Boolean;
procedure WaitReady;
type
    PRegistryChange = ^TRegistryChange;
    TRegistryChange = record
        Next : PRegistryChange;
        Path : PChar;
        Kind : uint8;
        Bytes : PUInt8;
        Length : uint32;
    end;

{ Apply existing logical keys as one in-memory update. }
function ApplyChanges(changes : PRegistryChange) : Boolean;
{ Paths are relative to the registry root and use logical key names.
  List callbacks receive borrowed names valid for the duration of the call. }
type
    TRegistryEntryVisitor = procedure(name : PChar; isDirectory : Boolean;
                                      kind : uint8; length : uint32; context : Pointer);

function TypeSuffix(valueType : uint8) : PChar;
function ListKeys(path : PChar; visit : TRegistryEntryVisitor;
                  context : Pointer) : TError;
function LookupKey(path : PChar; kind : uint8; var length : uint32) : Boolean;
function ReadKey(path : PChar; kind : uint8; offset : uint32;
                 buffer : PUInt8; length : uint32) : uint32;
function ReplaceKey(path : PChar; kind : uint8; buffer : PUInt8;
                    length : uint32) : uint32;
function CanCreateKey(path : PChar) : Boolean;
function CreateKey(path : PChar; kind : uint8; buffer : PUInt8;
                   length : uint32) : Boolean;
function CreateRegistryDirectory(path : PChar) : TError;
procedure UnitTest;

implementation

uses
    boot.mgr,
    proc.mgr,
    proc.types,
    driver.storage.vfs,
    driver.storage.fs.registry,
    core.ds.hashmap,
    core.strings,
    core.fmt.cbor,
    memory.heap,
    core.util,
    io.syslog,
    test.harness;

const
    REGISTRY_TAG_BASE = 65000;

type
    PSource = ^TSource;
    TSource = record
        Next : PSource;
        Name, Path : PChar;
        Writable, CanRead : Boolean;
    end;

    POverride = ^TOverride;
    TOverride = record
        References : uint32;
        Length : uint32;
        Bytes : PUInt8;
    end;

    PNode = ^TNode;
    PPNode = ^PNode;
    TNode = record
        Next, Children : PNode;
        Name : PChar;
        IsDirectory : Boolean;
        PersistVersion : uint32;
        Source : PSource;
        Offset, Length : uint32;
        Data : PUInt8;
        ValueType : uint8;
        Scalar : QWord;
        OverrideValue : POverride;
    end;

    TReader = record
        Handle : TFileHandle;
        Size, Position, BufferStart, BufferLength : uint32;
        Buffer : array[0..511] of Byte;
    end;

var
    cacheBudget, cachedBytes, overrideBytes : uint32;
    sources, writeSource : PSource;
    root : PNode;
    scanStarted, scanComplete : Boolean;
    mounted : Boolean;
    changeVersion : uint32 = 1;
    savedGeneration : QWord;
    primarySavePath, recoverySavePath, saveDirectory : PChar;
    recoveryPending, saveBlocked : Boolean;

procedure ReleaseOverride(value : POverride); forward;

procedure MarkChanged(node : PNode);
begin
    if not mounted then Exit;
    Inc(changeVersion);
    if node^.PersistVersion = 0 then node^.PersistVersion := changeVersion;
end;

function IsReady : Boolean;
begin
    Result := scanComplete;
end;

procedure WaitReady;
begin
    while not IsReady do proc.mgr.proc_sleep_ms(10);
end;

procedure SetCacheBudget(bytes : uint32);
begin
    if not scanStarted then cacheBudget := bytes;
end;

procedure CollectVolume(key : PChar; data : void; unused : void);
var
    obj : PVFSObject;
    volume : PStorage_Volume;
    source, current, previous : PSource;
    directory : PChar;
begin
    obj := PVFSObject(data);
    if obj = nil then Exit;
    if obj^.ObjectType <> otDRIVE then Exit;
    volume := PStorage_Volume(obj^.Reference);
    if volume = nil then Exit;
    if (volume^.device = nil) or (volume^.filesystem = nil) then Exit;

    source := PSource(kalloc(SizeOf(TSource)));
    source^.Name := stringCopy(key);
    directory := stringConcat('/disk/', key);
    source^.Path := stringConcat(directory, '/sys/asuro.db');
    if (volume^.isBootDrive or volume^.device^.isBootDevice) and
       (PathValid(source^.Path) <> pvFile) then begin
        kfree(void(source^.Path));
        source^.Path := stringConcat(directory, '/sys/asuro.db.cbor');
    end;
    kfree(void(directory));
    source^.Writable := volume^.device^.writable and
                        (volume^.filesystem^.writeOffsetCallback <> nil) and
                        (volume^.filesystem^.readOffsetCallback <> nil);
    source^.CanRead := volume^.filesystem^.readOffsetCallback <> nil;

    previous := nil;
    current := sources;
    while current <> nil do begin
        if stringCompare(source^.Name, current^.Name) < 0 then Break;
        previous := current;
        current := current^.Next;
    end;
    source^.Next := current;
    if previous = nil then sources := source
    else previous^.Next := source;
end;

function ReadHeader(var reader : TReader; var head : TCBORHead) : Boolean;
var
    offset : SizeUInt;
begin
    Result := False;
    if reader.Position >= reader.Size then Exit;
    if (reader.Position < reader.BufferStart) or
       (reader.Position - reader.BufferStart >= reader.BufferLength) or
       (reader.BufferLength - (reader.Position - reader.BufferStart) < 9) then begin
        reader.BufferStart := reader.Position;
        reader.BufferLength := ReadFile(reader.Handle, reader.Position,
                                       @reader.Buffer[0], SizeOf(reader.Buffer));
    end;
    offset := reader.Position - reader.BufferStart;
    if ReadHead(@reader.Buffer[0], reader.BufferLength, offset, head) <> cborOK then Exit;
    reader.Position := reader.BufferStart + offset;
    Result := True;
end;

function ReadName(var reader : TReader; var name : PChar) : Boolean;
var
    bytes : array[0..263] of Byte;
    head : TCBORHead;
    start, size, i : uint32;
    offset, length : SizeUInt;
    data : PUInt8;
    kind : TCBORKind;
begin
    Result := False;
    name := nil;
    start := reader.Position;
    if not ReadHeader(reader, head) then Exit;
    if head.Kind <> cborText then Exit;
    if (head.Argument = 0) or (head.Argument > 255) then Exit;
    if head.Argument > reader.Size - reader.Position then Exit;
    size := reader.Position - start + uint32(head.Argument);
    if ReadFile(reader.Handle, start, @bytes[0], size) <> size then Exit;
    offset := 0;
    if ReadString(@bytes[0], size, offset, data, length, kind) <> cborOK then Exit;
    for i := 0 to length - 1 do
        if (data[i] = 0) or (data[i] = Ord('/')) then Exit;
    name := stringNew(length);
    memcpy(uint32(data), uint32(name), length);
    if stringEquals(name, '.') or stringEquals(name, '..') then begin
        kfree(void(name));
        name := nil;
        Exit;
    end;
    Inc(reader.Position, length);
    Result := True;
end;

procedure FreeNodes(node : PNode);
var
    next : PNode;
begin
    while node <> nil do begin
        next := node^.Next;
        FreeNodes(node^.Children);
        if node^.Data <> nil then kfree(void(node^.Data));
        ReleaseOverride(node^.OverrideValue);
        kfree(void(node^.Name));
        kfree(void(node));
        node := next;
    end;
end;

function FindNode(list : PNode; name : PChar) : PNode;
begin
    while list <> nil do begin
        if stringEquals(list^.Name, name) then Break;
        list := list^.Next;
    end;
    Result := list;
end;

function TypeSuffix(valueType : uint8) : PChar;
begin
    case valueType of
        REGISTRY_UINT8: Result := '.u8';
        REGISTRY_UINT16: Result := '.u16';
        REGISTRY_UINT32: Result := '.u32';
        REGISTRY_UINT64: Result := '.u64';
        REGISTRY_INT8: Result := '.i8';
        REGISTRY_INT16: Result := '.i16';
        REGISTRY_INT32: Result := '.i32';
        REGISTRY_INT64: Result := '.i64';
        REGISTRY_FLOAT32: Result := '.f32';
        REGISTRY_FLOAT64: Result := '.f64';
        REGISTRY_TEXT: Result := '.txt';
        REGISTRY_BOOLEAN: Result := '.bool';
    else
        Result := '';
    end;
end;

function HasTypeSuffix(name : PChar) : Boolean;
var
    valueType : uint8;
begin
    Result := True;
    for valueType := REGISTRY_UINT32 to REGISTRY_BOOLEAN do
        if stringEndsWith(name, TypeSuffix(valueType)) then Exit;
    Result := False;
end;

function ScalarSize(valueType : uint8) : uint32;
begin
    case valueType of
        REGISTRY_UINT8, REGISTRY_INT8, REGISTRY_BOOLEAN:
            Result := 1;
        REGISTRY_UINT16, REGISTRY_INT16:
            Result := 2;
        REGISTRY_UINT32, REGISTRY_INT32, REGISTRY_FLOAT32:
            Result := 4;
        REGISTRY_UINT64, REGISTRY_INT64, REGISTRY_FLOAT64:
            Result := 8;
    else
        Result := 0;
    end;
end;

function ReadScalar(node : PNode; const head : TCBORHead) : Boolean;
var
    limit : QWord;
begin
    Result := False;
    node^.Length := ScalarSize(node^.ValueType);
    if node^.Length = 0 then Exit;
    case node^.ValueType of
        REGISTRY_UINT8, REGISTRY_UINT16, REGISTRY_UINT32, REGISTRY_UINT64:
            begin
                if head.Kind <> cborUnsigned then Exit;
                limit := High(QWord) shr (64 - 8 * node^.Length);
                if head.Argument > limit then Exit;
                node^.Scalar := head.Argument;
            end;
        REGISTRY_INT8, REGISTRY_INT16, REGISTRY_INT32, REGISTRY_INT64:
            begin
                if not (head.Kind in [cborUnsigned, cborNegative]) then Exit;
                limit := High(QWord) shr (65 - 8 * node^.Length);
                if head.Argument > limit then Exit;
                if head.Kind = cborNegative then node^.Scalar := not head.Argument
                else node^.Scalar := head.Argument;
            end;
        REGISTRY_FLOAT32:
            begin
                if head.Kind <> cborFloat32 then Exit;
                node^.Scalar := head.Argument;
            end;
        REGISTRY_FLOAT64:
            begin
                if head.Kind <> cborFloat64 then Exit;
                node^.Scalar := head.Argument;
            end;
        REGISTRY_BOOLEAN:
            begin
                if not (head.Kind in [cborFalse, cborTrue]) then Exit;
                node^.Scalar := Ord(head.Kind = cborTrue);
            end;
    end;
    Result := True;
end;

function CheckText(var reader : TReader; length : uint32) : Boolean;
var
    bytes : array[0..511] of uint8;
    position, remaining, size : uint32;
begin
    Result := False;
    position := reader.Position;
    remaining := length;
    while remaining <> 0 do begin
        size := remaining;
        if size > SizeOf(bytes) then size := SizeOf(bytes);
        if ReadFile(reader.Handle, position, @bytes[0], size) <> size then Exit;
        if size < remaining then begin
            { Re-read the last code point with the next block. }
            Dec(size);
            while (size > 0) and ((bytes[size] and $C0) = $80) do Dec(size);
            if size = 0 then Exit;
        end;
        if not ValidUTF8(@bytes[0], size) then Exit;
        Inc(position, size);
        Dec(remaining, size);
    end;
    Result := True;
end;

function ReadLeaf(
    var reader : TReader;
    source : PSource;
    node : PNode;
    head : TCBORHead
) : Boolean;
begin
    Result := False;
    if head.Kind = cborTag then begin
        if (head.Argument <= REGISTRY_TAG_BASE) or
           (head.Argument > REGISTRY_TAG_BASE + REGISTRY_BOOLEAN) then Exit;
        node^.ValueType := uint8(head.Argument - REGISTRY_TAG_BASE);
        if not ReadHeader(reader, head) then Exit;
        if node^.ValueType <> REGISTRY_TEXT then begin
            Result := ReadScalar(node, head);
            Exit;
        end;
        if head.Kind <> cborText then Exit;
    end else begin
        if head.Kind <> cborBytes then Exit;
        node^.ValueType := REGISTRY_BYTES;
    end;

    if head.Argument > reader.Size - reader.Position then Exit;
    node^.Length := uint32(head.Argument);
    if node^.ValueType = REGISTRY_TEXT then
        if not CheckText(reader, node^.Length) then Exit;
    node^.Source := source;
    node^.Offset := reader.Position;
    Inc(reader.Position, node^.Length);
    Result := True;
end;

function ReadMap(var reader : TReader; source : PSource; count : QWord;
                 depth : uint32; var nodes : PNode) : Boolean;
var
    head : TCBORHead;
    node : PNode;
    name : PChar;
begin
    Result := False;
    if depth > CBOR_MAX_DEPTH then Exit;
    if count > (reader.Size - reader.Position) div 3 then Exit;
    while count <> 0 do begin
        if not ReadName(reader, name) then Exit;
        if FindNode(nodes, name) <> nil then begin
            kfree(void(name));
            Exit;
        end;
        node := PNode(kalloc(SizeOf(TNode)));
        memset(uint32(node), 0, SizeOf(TNode));
        node^.Name := name;
        node^.Next := nodes;
        nodes := node;

        if not ReadHeader(reader, head) then Exit;
        case head.Kind of
            cborMap: begin
                if HasTypeSuffix(node^.Name) then Exit;
                node^.IsDirectory := True;
                if not ReadMap(reader, source, head.Argument, depth + 1, node^.Children) then Exit;
            end;
        else
            if not ReadLeaf(reader, source, node, head) then Exit;
            if (node^.ValueType = REGISTRY_BYTES) and HasTypeSuffix(node^.Name) then Exit;
        end;
        Dec(count);
    end;
    Result := True;
end;

{ Higher priority values replace lower priority values. Two maps merge. }
procedure Merge(var list : PNode; incoming : PNode);
var
    link : ^PNode;
    old, next : PNode;
begin
    while incoming <> nil do begin
        next := incoming^.Next;
        link := @list;
        while link^ <> nil do begin
            if stringEquals(link^^.Name, incoming^.Name) then Break;
            link := @link^^.Next;
        end;
        old := link^;
        if old = nil then begin
            incoming^.Next := nil;
            link^ := incoming;
        end else if old^.IsDirectory and incoming^.IsDirectory then begin
            Merge(old^.Children, incoming^.Children);
            if incoming^.PersistVersion <> 0 then old^.PersistVersion := incoming^.PersistVersion;
            incoming^.Children := nil;
            incoming^.Next := nil;
            FreeNodes(incoming);
        end else begin
            incoming^.Next := old^.Next;
            link^ := incoming;
            old^.Next := nil;
            FreeNodes(old);
        end;
        incoming := next;
    end;
end;

function LoadSource(source : PSource) : Boolean;
var
    reader : TReader;
    head : TCBORHead;
    error : TError;
    nodes : PNode;
    generation : QWord;
begin
    Result := False;
    if PathValid(source^.Path) <> pvFile then Exit;
    if not source^.CanRead then begin
        io.syslog.logln('registry', 'Database filesystem lacks offset reads.');
        Exit;
    end;
    reader.Handle := OpenFile(source^.Path, omRead, @error);
    if reader.Handle = 0 then Exit;
    reader.Size := FileSizeFromHandle(reader.Handle);
    reader.Position := 0;
    reader.BufferStart := 0;
    reader.BufferLength := 0;
    nodes := nil;
    if ReadHeader(reader, head) then begin
        if head.Kind = cborMap then
            Result := ReadMap(reader, source, head.Argument, 1, nodes)
        else if (head.Kind = cborArray) and (head.Argument = 3) and
                ReadHeader(reader, head) and (head.Kind = cborUnsigned) then begin
            generation := head.Argument;
            if ReadHeader(reader, head) and (head.Kind = cborMap) then
                Result := ReadMap(reader, source, head.Argument, 1, nodes) and
                          ReadHeader(reader, head) and (head.Kind = cborUnsigned) and
                          (head.Argument = generation);
        end;
        Result := Result and (reader.Position = reader.Size);
    end;
    CloseFile(reader.Handle);
    if Result then Merge(root, nodes)
    else begin
        FreeNodes(nodes);
        io.syslog.logln('registry', 'Invalid registry database ignored.');
    end;
end;

function ReadBacking(node : PNode; offset : uint32; buffer : PUInt8;
                     length : uint32) : uint32;
var
    handle : TFileHandle;
    error : TError;
begin
    Result := 0;
    handle := OpenFile(node^.Source^.Path, omRead, @error);
    if handle = 0 then Exit;
    Result := ReadFile(handle, node^.Offset + offset, buffer, length);
    CloseFile(handle);
end;

function RetainOverride(node : PNode) : POverride;
var
    flags : uint32;
begin
    asm
        pushfd
        cli
        pop flags
    end;
    Result := node^.OverrideValue;
    if Result <> nil then Inc(Result^.References);
    asm
        push flags
        popfd
    end;
end;

procedure ReleaseOverride(value : POverride);
var
    flags : uint32;
    release : Boolean;
begin
    if value = nil then Exit;
    asm
        pushfd
        cli
        pop flags
    end;
    Dec(value^.References);
    release := value^.References = 0;
    if release then Dec(overrideBytes, value^.Length + SizeOf(TOverride));
    asm
        push flags
        popfd
    end;
    if release then kfree(void(value));
end;

function ReadNode(data : Pointer; offset : uint32; buffer : PUInt8;
                  length : uint32) : uint32;
var
    node : PNode;
    value : POverride;
    size, i : uint32;
begin
    Result := 0;
    node := PNode(data);
    value := RetainOverride(node);
    if value <> nil then size := value^.Length
    else size := node^.Length;
    if (offset >= size) or (length = 0) then begin
        ReleaseOverride(value);
        Exit;
    end;
    if length > size - offset then length := size - offset;
    if value <> nil then begin
        memcpy(uint32(value^.Bytes + offset), uint32(buffer), length);
        ReleaseOverride(value);
    end else if node^.Source = nil then begin
        for i := 0 to length - 1 do
            buffer[i] := uint8((node^.Scalar shr (8 * (offset + i))) and $FF);
    end else if node^.Data <> nil then
        memcpy(uint32(node^.Data + offset), uint32(buffer), length)
    else begin
        Result := ReadBacking(node, offset, buffer, length);
        Exit;
    end;
    Result := length;
end;

function PrepareOverride(node : PNode; buffer : PUInt8;
                         length : uint32) : POverride;
var
    value : POverride;
    valueType : uint8;
    allocation, flags : uint32;
    reserved : Boolean;
begin
    Result := nil;
    if (node = nil) or (buffer = nil) then Exit;
    valueType := node^.ValueType;
    case valueType of
        REGISTRY_TEXT:
            if not ValidUTF8(buffer, length) then Exit;
        REGISTRY_UINT32..REGISTRY_FLOAT64:
            if length <> ScalarSize(valueType) then Exit;
        REGISTRY_BOOLEAN:
            begin
                if length <> 1 then Exit;
                if buffer[0] > 1 then Exit;
            end;
    else
        if valueType <> REGISTRY_BYTES then Exit;
    end;
    if length > High(uint32) - SizeOf(TOverride) then Exit;
    allocation := length + SizeOf(TOverride);
    asm
        pushfd
        cli
        pop flags
    end;
    reserved := allocation <= cacheBudget - overrideBytes;
    if reserved then Inc(overrideBytes, allocation);
    asm
        push flags
        popfd
    end;
    if not reserved then Exit;

    value := POverride(kalloc(allocation));
    value^.References := 1;
    value^.Length := length;
    value^.Bytes := PUInt8(uint32(value) + SizeOf(TOverride));
    if length <> 0 then memcpy(uint32(buffer), uint32(value^.Bytes), length);

    Result := value;
end;

function WriteNode(data : Pointer; offset : uint32; buffer : PUInt8;
                   length : uint32) : uint32;
var
    node : PNode;
    value, previous : POverride;
    flags : uint32;
begin
    Result := 0;
    if offset <> 0 then Exit;
    node := PNode(data);
    value := PrepareOverride(node, buffer, length);
    if value = nil then Exit;

    asm
        pushfd
        cli
        pop flags
    end;
    previous := node^.OverrideValue;
    node^.OverrideValue := value;
    MarkChanged(node);
    asm
        push flags
        popfd
    end;
    ReleaseOverride(previous);
    Result := length;
end;

function FindKeyPath(first : PNode; path : PChar) : PNode;
var
    copy, name, cursor : PChar;
    node, nodes : PNode;
begin
    Result := nil;
    if (path = nil) or (path^ = #0) then Exit;
    copy := stringCopy(path);
    name := copy;
    cursor := copy;
    nodes := first;
    while True do begin
        while (cursor^ <> #0) and (cursor^ <> '/') do Inc(cursor);
        if cursor^ = #0 then begin
            Result := FindNode(nodes, name);
            Break;
        end;
        cursor^ := #0;
        node := FindNode(nodes, name);
        if (node = nil) or not node^.IsDirectory then Break;
        nodes := node^.Children;
        Inc(cursor);
        name := cursor;
    end;
    kfree(void(copy));
end;

function ApplyChangesTo(nodes : PNode; changes : PRegistryChange) : Boolean;
type
    PPreparedChange = ^TPreparedChange;
    TPreparedChange = record
        Next : PPreparedChange;
        Node : PNode;
        Value : POverride;
    end;
var
    prepared, entry : PPreparedChange;
    node : PNode;
    value, previous : POverride;
    flags : uint32;
begin
    Result := false;
    prepared := nil;
    while changes <> nil do begin
        node := FindKeyPath(nodes, changes^.Path);
        if (node = nil) or node^.IsDirectory or (node^.ValueType <> changes^.Kind) then Break;
        entry := prepared;
        while (entry <> nil) and (entry^.Node <> node) do entry := entry^.Next;
        if entry <> nil then Break;
        value := PrepareOverride(node, changes^.Bytes, changes^.Length);
        if value = nil then Break;
        entry := PPreparedChange(kalloc(SizeOf(TPreparedChange)));
        entry^.Next := prepared;
        entry^.Node := node;
        entry^.Value := value;
        prepared := entry;
        changes := changes^.Next;
    end;

    if changes = nil then begin
        asm
            pushfd
            cli
            pop flags
        end;
        entry := prepared;
        while entry <> nil do begin
            previous := entry^.Node^.OverrideValue;
            entry^.Node^.OverrideValue := entry^.Value;
            MarkChanged(entry^.Node);
            entry^.Value := previous;
            entry := entry^.Next;
        end;
        asm
            push flags
            popfd
        end;
        Result := true;
    end;
    while prepared <> nil do begin
        entry := prepared;
        prepared := entry^.Next;
        ReleaseOverride(entry^.Value);
        kfree(void(entry));
    end;
end;

function ApplyChanges(changes : PRegistryChange) : Boolean;
begin
    Result := IsReady and ApplyChangesTo(root, changes);
end;

function NodeSize(data : Pointer) : uint32;
var
    node : PNode;
    value : POverride;
begin
    node := PNode(data);
    value := RetainOverride(node);
    if value <> nil then Result := value^.Length
    else Result := node^.Length;
    ReleaseOverride(value);
end;

procedure CacheValues(nodes : PNode);
begin
    while nodes <> nil do begin
        if nodes^.IsDirectory then CacheValues(nodes^.Children)
        else if (nodes^.Source <> nil) and (nodes^.Length <> 0) and
                (nodes^.Length <= cacheBudget - cachedBytes) then begin
            nodes^.Data := PUInt8(kalloc(nodes^.Length));
            if ReadBacking(nodes, 0, nodes^.Data, nodes^.Length) = nodes^.Length then
                Inc(cachedBytes, nodes^.Length)
            else begin
                kfree(void(nodes^.Data));
                nodes^.Data := nil;
            end;
        end;
        nodes := nodes^.Next;
    end;
end;

function ResolveNewPath(path : PChar; directory : Boolean; var list : PPNode;
                        var name : PChar) : TError;
var
    segment, separator : PChar;
    length, depth : uint32;
    node : PNode;
begin
    Result := eInvalidPath;
    if path = nil then Exit;
    list := @root;
    segment := path;
    depth := 0;
    repeat
        Inc(depth);
        if (depth > CBOR_MAX_DEPTH) or (directory and (depth = CBOR_MAX_DEPTH)) then Exit;
        separator := segment;
        while (separator^ <> #0) and (separator^ <> '/') do Inc(separator);
        length := uint32(separator) - uint32(segment);
        if (length = 0) or (length > 255) then Exit;
        name := stringNew(length);
        memcpy(uint32(segment), uint32(name), length);
        if (length = 0) or (length > 255) or HasTypeSuffix(name)
            or stringEquals(name, '.') or stringEquals(name, '..')
            or not ValidUTF8(PUInt8(name), length) then begin
            kfree(void(name));
            Exit;
        end;
        node := FindNode(list^, name);
        if separator^ = #0 then begin
            if node = nil then Exit(eNone);
            kfree(void(name));
            Exit(eAlreadyExists);
        end;
        kfree(void(name));
        if (node = nil) or not node^.IsDirectory then Exit(eDirectoryDoesNotExist);
        list := @node^.Children;
        Inc(separator);
        segment := separator;
    until False;
end;

function CreateRegistryDirectory(path : PChar) : TError;
var
    list : PPNode;
    node : PNode;
    name : PChar;
    flags : uint32;
begin
    if not mounted then Exit(eDeviceNotReady);
    asm
        pushfd
        cli
        pop flags
    end;
    Result := ResolveNewPath(path, True, list, name);
    if Result = eNone then begin
        node := PNode(kalloc(SizeOf(TNode)));
        node^.Name := name;
        node^.IsDirectory := True;
        node^.Next := list^;
        list^ := node;
        MarkChanged(node);
    end;
    asm
        push flags
        popfd
    end;
end;

function ListKeys(path : PChar; visit : TRegistryEntryVisitor;
                  context : Pointer) : TError;
var
    node : PNode;
begin
    if not mounted then Exit(eDeviceNotReady);
    if (path = nil) or (path^ = #0) then node := root
    else begin
        node := FindKeyPath(root, path);
        if (node = nil) or not node^.IsDirectory then Exit(eDirectoryDoesNotExist);
        node := node^.Children;
    end;
    while node <> nil do begin
        visit(node^.Name, node^.IsDirectory, node^.ValueType, NodeSize(node), context);
        node := node^.Next;
    end;
    Result := eNone;
end;

function FindTypedKey(path : PChar; kind : uint8) : PNode;
begin
    Result := nil;
    if not mounted then Exit;
    Result := FindKeyPath(root, path);
    if Result <> nil then
        if Result^.IsDirectory or (Result^.ValueType <> kind) then Result := nil;
end;

function LookupKey(path : PChar; kind : uint8; var length : uint32) : Boolean;
var
    node : PNode;
begin
    length := 0;
    node := FindTypedKey(path, kind);
    Result := node <> nil;
    if Result then length := NodeSize(node);
end;

function ReadKey(path : PChar; kind : uint8; offset : uint32;
                 buffer : PUInt8; length : uint32) : uint32;
var
    node : PNode;
begin
    node := FindTypedKey(path, kind);
    if node = nil then Exit(0);
    Result := ReadNode(node, offset, buffer, length);
end;

function ReplaceKey(path : PChar; kind : uint8; buffer : PUInt8;
                    length : uint32) : uint32;
var
    node : PNode;
begin
    node := FindTypedKey(path, kind);
    if node = nil then Exit(0);
    Result := WriteNode(node, 0, buffer, length);
end;

function CanCreateKey(path : PChar) : Boolean;
var
    list : PPNode;
    name : PChar;
begin
    Result := mounted and (ResolveNewPath(path, False, list, name) = eNone);
    if Result then kfree(void(name));
end;

function CreateKey(path : PChar; kind : uint8; buffer : PUInt8;
                   length : uint32) : Boolean;
var
    list : PPNode;
    name : PChar;
    node : PNode;
    value : POverride;
    flags : uint32;
begin
    Result := False;
    if not mounted then Exit;
    node := PNode(kalloc(SizeOf(TNode)));
    node^.ValueType := kind;
    value := PrepareOverride(node, buffer, length);
    if value = nil then begin
        kfree(void(node));
        Exit;
    end;

    asm
        pushfd
        cli
        pop flags
    end;
    if ResolveNewPath(path, False, list, name) = eNone then begin
        node^.Name := name;
        node^.OverrideValue := value;
        node^.Next := list^;
        list^ := node;
        MarkChanged(node);
        Result := True;
    end;
    asm
        push flags
        popfd
    end;
    if not Result then begin
        ReleaseOverride(value);
        kfree(void(node));
    end;
end;

type
    TSnapshotWriter = record
        Handle : TFileHandle;
        Position, Used : uint32;
        Buffer : array[0..1023] of uint8;
    end;

function FlushSnapshotBuffer(var writer : TSnapshotWriter) : Boolean;
begin
    Result := True;
    if writer.Used = 0 then Exit;
    if writer.Used > High(uint32) - writer.Position then Exit(False);
    Result := WriteFile(writer.Handle, writer.Position, @writer.Buffer[0],
                        writer.Used) = writer.Used;
    if Result then begin
        Inc(writer.Position, writer.Used);
        writer.Used := 0;
    end;
end;

function SnapshotBytes(var writer : TSnapshotWriter; bytes : PUInt8;
                       length : uint32) : Boolean;
var
    count : uint32;
begin
    while length <> 0 do begin
        count := SizeOf(writer.Buffer) - writer.Used;
        if count > length then count := length;
        memcpy(uint32(bytes), uint32(@writer.Buffer[writer.Used]), count);
        Inc(writer.Used, count);
        Inc(bytes, count);
        Dec(length, count);
        if writer.Used = SizeOf(writer.Buffer) then
            if not FlushSnapshotBuffer(writer) then Exit(False);
    end;
    Result := True;
end;

function SnapshotHead(var writer : TSnapshotWriter; kind : TCBORKind;
                      argument : QWord) : Boolean;
var
    bytes : array[0..8] of uint8;
    length : SizeUInt;
begin
    length := 0;
    Result := (WriteHead(@bytes[0], SizeOf(bytes), length,
                        MakeHead(kind, argument)) = cborOK) and
              SnapshotBytes(writer, @bytes[0], length);
end;

function SnapshotLeaf(var writer : TSnapshotWriter; node : PNode) : Boolean;
var
    value : POverride;
    kind : TCBORKind;
    argument : QWord;
    length, i : uint32;
begin
    Result := False;
    value := RetainOverride(node);
    if value = nil then Exit;
    length := value^.Length;
    if node^.ValueType <> REGISTRY_BYTES then
        if not SnapshotHead(writer, cborTag, REGISTRY_TAG_BASE + node^.ValueType) then begin
            ReleaseOverride(value);
            Exit;
        end;
    case node^.ValueType of
        REGISTRY_TEXT, REGISTRY_BYTES:
            begin
                kind := cborBytes;
                if node^.ValueType = REGISTRY_TEXT then kind := cborText;
                Result := SnapshotHead(writer, kind, length) and
                          SnapshotBytes(writer, value^.Bytes, length);
            end;
    else
        argument := 0;
        for i := 0 to length - 1 do
            argument := argument or (QWord(value^.Bytes[i]) shl (8 * i));
        kind := cborUnsigned;
        case node^.ValueType of
            REGISTRY_INT8..REGISTRY_INT64:
                if (value^.Bytes[length - 1] and $80) <> 0 then begin
                    kind := cborNegative;
                    argument := (not argument) and (High(QWord) shr (64 - 8 * length));
                end;
            REGISTRY_FLOAT32: kind := cborFloat32;
            REGISTRY_FLOAT64: kind := cborFloat64;
            REGISTRY_BOOLEAN:
                if argument = 0 then kind := cborFalse
                else kind := cborTrue;
        end;
        Result := SnapshotHead(writer, kind, argument);
    end;
    ReleaseOverride(value);
end;

function InSnapshot(node : PNode; version : uint32) : Boolean;
var
    child : PNode;
begin
    if (node^.PersistVersion <> 0) and (node^.PersistVersion <= version) then Exit(True);
    child := node^.Children;
    while child <> nil do begin
        if InSnapshot(child, version) then Exit(True);
        child := child^.Next;
    end;
    Result := False;
end;

function SnapshotMap(var writer : TSnapshotWriter; nodes : PNode;
                     version : uint32) : Boolean;
var
    node : PNode;
    count, length : uint32;
begin
    count := 0;
    node := nodes;
    while node <> nil do begin
        if InSnapshot(node, version) then Inc(count);
        node := node^.Next;
    end;
    if not SnapshotHead(writer, cborMap, count) then Exit(False);
    node := nodes;
    while node <> nil do begin
        if InSnapshot(node, version) then begin
            length := stringSize(node^.Name);
            if not SnapshotHead(writer, cborText, length) or
                not SnapshotBytes(writer, PUInt8(node^.Name), length) then Exit(False);
            if node^.IsDirectory then begin
                if not SnapshotMap(writer, node^.Children, version) then Exit(False);
            end else if not SnapshotLeaf(writer, node) then Exit(False);
        end;
        node := node^.Next;
    end;
    Result := True;
end;

function MaterializeSnapshot(node : PNode) : Boolean;
var
    bytes : PUInt8;
    length : uint32;
begin
    while node <> nil do begin
        node^.PersistVersion := 1;
        if node^.IsDirectory then begin
            if not MaterializeSnapshot(node^.Children) then Exit(False);
        end else begin
            length := node^.Length;
            if length > cacheBudget - overrideBytes then Exit(False);
            bytes := PUInt8(kalloc(length + 1));
            if ReadNode(node, 0, bytes, length) = length then
                node^.OverrideValue := PrepareOverride(node, bytes, length);
            kfree(void(bytes));
            if node^.OverrideValue = nil then Exit(False);
            node^.Source := nil;
        end;
        node := node^.Next;
    end;
    Result := True;
end;

function ReadSave(path : PChar; allowMap, legacy : Boolean; var nodes : PNode;
                  var generation : QWord) : Boolean;
var
    source : TSource;
    reader : TReader;
    head : TCBORHead;
    error : TError;
    framed : Boolean;
begin
    Result := False;
    generation := 0;
    nodes := nil;
    reader.Handle := OpenFile(path, omRead, @error);
    if reader.Handle = 0 then Exit;
    reader.Size := FileSizeFromHandle(reader.Handle);
    reader.Position := 0;
    reader.BufferStart := 0;
    reader.BufferLength := 0;
    source.Path := path;
    if ReadHeader(reader, head) then begin
        if allowMap and (head.Kind = cborMap) then
            Result := ReadMap(reader, @source, head.Argument, 1, nodes)
        else if (head.Kind = cborArray) and
                ((head.Argument = 3) or (legacy and (head.Argument = 2))) then begin
            framed := head.Argument = 3;
            if ReadHeader(reader, head) and (head.Kind = cborUnsigned) then begin
                generation := head.Argument;
                Result := (generation <> 0) and ReadHeader(reader, head) and
                          (head.Kind = cborMap) and
                          ReadMap(reader, @source, head.Argument, 1, nodes);
                if Result and framed then
                    Result := ReadHeader(reader, head) and (head.Kind = cborUnsigned)
                              and (head.Argument = generation);
            end;
        end;
        Result := Result and (reader.Position = reader.Size) and MaterializeSnapshot(nodes);
    end;
    CloseFile(reader.Handle);
    if not Result then begin
        FreeNodes(nodes);
        nodes := nil;
    end;
end;

function ReadGeneration(path : PChar; legacy : Boolean) : QWord;
var
    reader : TReader;
    head : TCBORHead;
    error : TError;
begin
    Result := 0;
    reader.Handle := OpenFile(path, omRead, @error);
    if reader.Handle = 0 then Exit;
    reader.Size := FileSizeFromHandle(reader.Handle);
    reader.Position := 0;
    reader.BufferStart := 0;
    reader.BufferLength := 0;
    if ReadHeader(reader, head) and (head.Kind = cborArray) and
       ((head.Argument = 3) or (legacy and (head.Argument = 2))) and
        ReadHeader(reader, head) and (head.Kind = cborUnsigned) then
        Result := head.Argument;
    CloseFile(reader.Handle);
end;

function RestoreLegacy(prefix : PChar) : Boolean;
const
    FILES : array[0..3] of PChar =
        ('asuroa.cbr', 'asurob.cbr', 'asuro-save-a.cbor', 'asuro-save-b.cbor');
var
    paths : array[0..3] of PChar;
    generations : array[0..3] of QWord;
    best, i : uint32;
    nodes : PNode;
begin
    for i := Low(FILES) to High(FILES) do begin
        paths[i] := stringConcat(prefix, FILES[i]);
        generations[i] := ReadGeneration(paths[i], True);
    end;
    Result := False;
    repeat
        best := Low(FILES);
        for i := Low(FILES) + 1 to High(FILES) do
            if generations[i] > generations[best] then best := i;
        if generations[best] = 0 then Break;
        Result := ReadSave(paths[best], False, True, nodes, savedGeneration);
        if Result then Merge(root, nodes)
        else generations[best] := 0;
    until Result;
    if not Result then savedGeneration := 0;
    for i := Low(FILES) to High(FILES) do kfree(void(paths[i]));
end;

function RestoreWritable(path : PChar; allowMap : Boolean) : Boolean;
var
    nodes : PNode;
    source : PSource;
begin
    Result := ReadSave(path, allowMap, False, nodes, savedGeneration);
    if Result then begin
        Merge(root, nodes);
        Exit;
    end;

    { Preserve a valid database that is too large to materialize. }
    if PathValid(path) <> pvFile then Exit;
    source := PSource(kalloc(SizeOf(TSource)));
    source^.Path := path;
    source^.CanRead := True;
    Result := LoadSource(source);
    if Result then begin
        saveBlocked := True;
        savedGeneration := ReadGeneration(path, False);
        io.syslog.logln('registry', 'Writable database exceeds the save budget.');
    end else
        kfree(void(source));
end;

function RestoreSnapshot : Boolean;
var
    directory, prefix : PChar;
    primaryGeneration, recoveryGeneration : QWord;
begin
    directory := stringConcat('/disk/', writeSource^.Name);
    prefix := stringConcat(directory, '/sys/');
    saveDirectory := stringConcat(directory, '/sys');
    primarySavePath := stringConcat(prefix, 'asuro.db');
    recoverySavePath := stringConcat(prefix, '~asuro.db');
    kfree(void(directory));

    primaryGeneration := ReadGeneration(primarySavePath, False);
    recoveryGeneration := ReadGeneration(recoverySavePath, False);
    Result := False;
    if recoveryGeneration > primaryGeneration then begin
        Result := RestoreWritable(recoverySavePath, False);
        recoveryPending := Result;
    end;
    if not Result then Result := RestoreWritable(primarySavePath, True);
    if not Result and (recoveryGeneration <> 0) and (recoveryGeneration <= primaryGeneration) then begin
        Result := RestoreWritable(recoverySavePath, False);
        recoveryPending := Result;
    end;
    if not Result and not stringEquals(primarySavePath, writeSource^.Path) then
        Result := RestoreWritable(writeSource^.Path, True);
    if not Result then savedGeneration := 0;
    if savedGeneration = 0 then
        if RestoreLegacy(prefix) then Result := True;
    kfree(void(prefix));
end;

function PromoteRecovery : Boolean;
begin
    Result := False;
    if PathValid(primarySavePath) = pvFile then
        if DeleteFile(primarySavePath, nil) <> eNone then Exit;
    Result := RenameFile(recoverySavePath, 'asuro.db', nil) = eNone;
    if Result then recoveryPending := False;
end;

function SaveSnapshot(version : uint32) : Boolean;
var
    writer : TSnapshotWriter;
    error : TError;
begin
    Result := False;
    if recoveryPending then
        if not PromoteRecovery then Exit;
    if PathValid(saveDirectory) <> pvDirectory then
        if CreateDirectory(saveDirectory, nil) <> eNone then Exit;
    if PathValid(recoverySavePath) = pvFile then
        if DeleteFile(recoverySavePath, nil) <> eNone then Exit;
    writer.Handle := OpenFile(recoverySavePath, omCreate, @error);
    if writer.Handle = 0 then Exit;
    writer.Position := 0;
    writer.Used := 0;
    Result := SnapshotHead(writer, cborArray, 3) and
              SnapshotHead(writer, cborUnsigned, savedGeneration + 1) and
              SnapshotMap(writer, root, version) and (changeVersion = version) and
              SnapshotHead(writer, cborUnsigned, savedGeneration + 1) and
              FlushSnapshotBuffer(writer);
    if CloseFile(writer.Handle) <> eNone then Result := False;
    if Result then begin
        recoveryPending := True;
        Inc(savedGeneration);
        Result := PromoteRecovery;
    end;
end;

procedure LoadRegistry;
var
    listing : PHashMap;
    source : PSource;
    loaded : Boolean;
begin
    scanStarted := True;
    listing := GetDirectoryListingFrom('/disk', '/');
    if listing = nil then Exit;
    core.ds.hashmap.forEach(listing, @CollectVolume, nil);
    FreeDirectoryListing(listing);

    source := sources;
    while source <> nil do begin
        if source^.Writable then begin
            writeSource := source;
            Break;
        end;
        source := source^.Next;
    end;

    loaded := False;
    source := sources;
    while source <> nil do begin
        if source <> writeSource then
            if LoadSource(source) then loaded := True;
        source := source^.Next;
    end;
    if writeSource <> nil then
        if RestoreSnapshot then loaded := True;
    if not loaded and (writeSource = nil) then begin
        io.syslog.logln('registry', 'No valid registry database found.');
        Exit;
    end;
    CacheValues(root);
    if not driver.storage.fs.registry.Mount then begin
        io.syslog.logln('registry', 'Could not mount /cfg.');
        Exit;
    end;
    mounted := True;
    io.syslog.logln('registry', 'Mounted /cfg.');
end;

procedure RegistryMain(ctx : PProcessContext);
const
    SAVE_DELAY_MS = 1000;
    SAVE_POLL_MS = 100;
var
    version, savedVersion, quietIntervals : uint32;
begin
    LoadRegistry;
    scanComplete := True;
    if not mounted or (writeSource = nil) or saveBlocked then begin
        proc.mgr.proc_exit(0);
        Exit;
    end;

    savedVersion := 1;
    version := savedVersion;
    quietIntervals := 0;
    while True do begin
        proc.mgr.proc_sleep_ms(SAVE_POLL_MS);
        if version <> changeVersion then begin
            version := changeVersion;
            quietIntervals := 0;
        end else if version <> savedVersion then begin
            Inc(quietIntervals);
            if quietIntervals = SAVE_DELAY_MS div SAVE_POLL_MS then begin
                if SaveSnapshot(version) then savedVersion := version
                else io.syslog.logln('registry', 'Save failed. Retrying in one second.');
                quietIntervals := 0;
            end;
        end;
    end;
end;

procedure Init;
begin
    if proc.mgr.create('regd', @RegistryMain, nil, 2) = nil then begin
        io.syslog.logln('registry', 'Could not start registry loader.');
        scanComplete := True;
    end;
end;

procedure TestBatch(context : PTestContext);
var
    directory, width, height : TNode;
    widthChange, heightChange : TRegistryChange;
    newWidth, newHeight : uint8;
    readWidth, readHeight : uint8;
begin
    memset(uint32(@directory), 0, SizeOf(directory));
    memset(uint32(@width), 0, SizeOf(width));
    memset(uint32(@height), 0, SizeOf(height));
    directory.Name := 'display';
    directory.IsDirectory := true;
    directory.Children := @width;
    width.Name := 'width';
    width.Next := @height;
    width.ValueType := REGISTRY_UINT8;
    height.Name := 'height';
    height.ValueType := REGISTRY_UINT8;

    newWidth := 80;
    newHeight := 60;
    widthChange.Next := @heightChange;
    widthChange.Path := 'display/width';
    widthChange.Kind := REGISTRY_UINT8;
    widthChange.Bytes := @newWidth;
    widthChange.Length := 1;
    heightChange.Next := nil;
    heightChange.Path := 'display/height';
    heightChange.Kind := REGISTRY_UINT32;
    heightChange.Bytes := @newHeight;
    heightChange.Length := 1;

    test.harness.Assert(context, not ApplyChangesTo(@directory, @widthChange) and
                        (width.OverrideValue = nil) and (height.OverrideValue = nil),
                        'A wrong target type leaves the whole batch unchanged');

    heightChange.Kind := REGISTRY_UINT8;
    test.harness.Assert(context, ApplyChangesTo(@directory, @widthChange),
                        'Apply multiple typed targets together');
    ReadNode(@width, 0, @readWidth, 1);
    ReadNode(@height, 0, @readHeight, 1);
    test.harness.Assert(context, (readWidth = 80) and (readHeight = 60),
                        'Read both updated values after applying a batch');

    newWidth := 90;
    heightChange.Length := 0;
    test.harness.Assert(context, not ApplyChangesTo(@directory, @widthChange),
                        'Reject an invalid payload in a batch');
    ReadNode(@width, 0, @readWidth, 1);
    test.harness.Assert(context, readWidth = 80,
                        'Preserve an existing override when a later change fails');
    ReleaseOverride(width.OverrideValue);
    ReleaseOverride(height.OverrideValue);
end;

procedure TestSnapshotEncoding(context : PTestContext);
var
    node : TNode;
    writer : TSnapshotWriter;
    bytes : array[0..1] of uint8;
    offset : SizeUInt;
    head : TCBORHead;
begin
    memset(uint32(@node), 0, SizeOf(node));
    node.ValueType := REGISTRY_INT16;
    bytes[0] := $FE;
    bytes[1] := $FF;
    node.OverrideValue := PrepareOverride(@node, @bytes[0], SizeOf(bytes));
    writer.Used := 0;
    test.harness.Assert(context, SnapshotLeaf(writer, @node),
                        'Encode an overridden registry leaf');
    offset := 0;
    test.harness.Assert(context,
        (ReadHead(@writer.Buffer[0], writer.Used, offset, head) = cborOK) and
        (head.Kind = cborTag) and (head.Argument = REGISTRY_TAG_BASE + REGISTRY_INT16) and
        (ReadHead(@writer.Buffer[0], writer.Used, offset, head) = cborOK) and
        (head.Kind = cborNegative) and (head.Argument = 1),
        'Persist signed override bytes as a tagged negative CBOR value');
    ReleaseOverride(node.OverrideValue);
end;

procedure UnitTest;
var
    context : TTestContext;
    node : TNode;
    bytes : array[0..4] of uint8;
    count, versionBefore : uint32;
begin
    versionBefore := changeVersion;
    test.harness.Start(@context, 'svc.registry');
    memset(uint32(@node), 0, SizeOf(node));

    node.ValueType := REGISTRY_UINT32;
    test.harness.Assert(@context, ReadScalar(@node, MakeHead(cborUnsigned, 1920)),
                        'Decode a tagged UINT32');
    count := ReadNode(@node, 0, @bytes[0], SizeOf(bytes));
    test.harness.Assert(@context, (count = 4) and (bytes[0] = $80) and
                        (bytes[1] = 7) and (bytes[2] = 0) and (bytes[3] = 0),
                        'Read UINT32 as little-endian bytes');

    node.ValueType := REGISTRY_INT8;
    test.harness.Assert(@context, ReadScalar(@node, MakeHead(cborNegative, 127)),
                        'Decode minimum INT8');
    count := ReadNode(@node, 0, @bytes[0], 1);
    test.harness.Assert(@context, (count = 1) and (bytes[0] = $80),
                        'Read INT8 as two''s-complement bytes');
    test.harness.Assert(@context, not ReadScalar(@node, MakeHead(cborNegative, 128)),
                        'Reject INT8 underflow');
    node.ValueType := REGISTRY_UINT8;
    test.harness.Assert(@context, not ReadScalar(@node, MakeHead(cborUnsigned, 256)),
                        'Reject UINT8 overflow');

    test.harness.Assert(@context, stringEquals(TypeSuffix(REGISTRY_UINT8), '.u8'),
                        'Publish UINT8 with the .u8 suffix');
    test.harness.Assert(@context, stringEquals(TypeSuffix(REGISTRY_BYTES), ''),
                        'Publish raw bytes without a suffix');
    test.harness.Assert(@context, HasTypeSuffix('setting.txt') and
                        not HasTypeSuffix('setting.backup'),
                        'Reserve only recognised suffixes');

    bytes[0] := 32;
    bytes[1] := 0;
    test.harness.Assert(@context, WriteNode(@node, 0, @bytes[0], 1) = 1,
                        'Accept UINT8 payload without a type prefix');
    test.harness.Assert(@context, NodeSize(@node) = 1, 'Report the current payload size');
    test.harness.Assert(@context, WriteNode(@node, 1, @bytes[0], 1) = 0,
                        'Reject nonzero write offset');
    test.harness.Assert(@context, WriteNode(@node, 0, @bytes[0], 2) = 0,
                        'Reject a payload wider than the published type');
    count := ReadNode(@node, 0, @bytes[0], SizeOf(bytes));
    test.harness.Assert(@context, (count = 1) and (bytes[0] = 32),
                        'Rejected writes preserve the previous value');

    ReleaseOverride(node.OverrideValue);
    node.OverrideValue := nil;
    node.ValueType := REGISTRY_BOOLEAN;
    bytes[0] := 2;
    test.harness.Assert(@context, WriteNode(@node, 0, @bytes[0], 1) = 0,
                        'Reject invalid boolean payload');
    node.ValueType := REGISTRY_TEXT;
    bytes[0] := $FF;
    test.harness.Assert(@context, WriteNode(@node, 0, @bytes[0], 1) = 0,
                        'Reject invalid UTF-8 payload');
    bytes[0] := Ord('A');
    bytes[1] := Ord('s');
    test.harness.Assert(@context, WriteNode(@node, 0, @bytes[0], 2) = 2,
                        'Accept plain UTF-8 text');

    ReleaseOverride(node.OverrideValue);
    node.OverrideValue := nil;
    node.ValueType := REGISTRY_BYTES;
    bytes[0] := 0;
    test.harness.Assert(@context, WriteNode(@node, 0, @bytes[0], 1) = 1,
                        'Accept raw data starting with zero');
    count := ReadNode(@node, 0, @bytes[0], SizeOf(bytes));
    test.harness.Assert(@context, (count = 1) and (bytes[0] = 0),
                        'Allow zero in a raw-byte payload');

    ReleaseOverride(node.OverrideValue);
    TestBatch(@context);
    TestSnapshotEncoding(@context);
    changeVersion := versionBefore;
    test.harness.Finish(@context);
end;

initialization
    cacheBudget := REGISTRY_DEFAULT_CACHE_BYTES;
    boot.mgr.registerBoot('svc.registry', @Init, 'Load Settings Registry',
                          'driver.storage.vol.mount');

end.
