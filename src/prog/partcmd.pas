{
    Prog->PartCmd - Command-line tools for partition table management.

    Shell command: PART [subcommand]
    Subcommands:
        list     <disk>                 - Show partition table
        add      <disk> [size]          - Add a partition (auto-inits MBR;
                                          uses all remaining space if size
                                          omitted; accepts B, KB, MB, GB)
        rm       <disk> <slot>          - Remove a partition by slot number
        format   <disk> <slot> <fsname> - Format a partition with a filesystem

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit partcmd;

interface

procedure init();

implementation

uses
    console,
    filesystemmanager,
    lists,
    lmemorymanager,
    MBR,
    storagemanager,
    storagetypes,
    strings,
    terminal,
    tracer,
    volumemanager;

{ ---------- helpers ---------- }

function wnd : uint32;
begin
    wnd := getTerminalHWND;
end;

function str2int(s : pchar) : uint32;
begin
    str2int := stringToInt(s);
end;

function isNumeric(s : pchar) : boolean;
var
    i   : uint32;
    len : uint32;
begin
    isNumeric := false;
    len := stringSize(s);
    if len = 0 then exit;
    for i := 0 to len - 1 do begin
        if (s[i] < '0') or (s[i] > '9') then exit;
    end;
    isNumeric := true;
end;

procedure print(s : pchar);
begin
    console.writestringWND(s, wnd);
end;

procedure println(s : pchar);
begin
    console.writestringlnWND(s, wnd);
end;

procedure printint(v : uint32);
begin
    console.writeintWND(v, wnd);
end;

procedure printhex(v : uint32);
begin
    console.writehexWND(v, wnd);
end;

procedure printsize(bytes : uint32);
begin
    if bytes >= 1073741824 then begin
        printint(bytes div 1073741824);
        print(' GB');
    end else if bytes >= 1048576 then begin
        printint(bytes div 1048576);
        print(' MB');
    end else if bytes >= 1024 then begin
        printint(bytes div 1024);
        print(' KB');
    end else begin
        printint(bytes);
        print(' B');
    end;
end;

{ Parse a size string (e.g. '500MB', '2GB', '1024KB', '4096B', '1024')
  into a sector count. Plain numbers are treated as bytes.
  Returns 0 on invalid input. }
function parsesize(s : pchar; sectorSize : uint32) : uint32;
var
    len     : uint32;
    last    : char;
    prev    : char;
    numEnd  : uint32;
    value   : uint32;
    bytes   : uint32;
begin
    parsesize := 0;
    len := stringSize(s);
    if len = 0 then exit;

    last := s[len - 1];

    if (last = 'B') or (last = 'b') then begin
        if len >= 3 then
            prev := s[len - 2]
        else
            prev := #0;

        if (prev = 'G') or (prev = 'g') then begin
            numEnd := len - 2;
            s[numEnd] := #0;
            value := stringToInt(s);
            s[numEnd] := prev;
            bytes := value * 1073741824;
        end else if (prev = 'M') or (prev = 'm') then begin
            numEnd := len - 2;
            s[numEnd] := #0;
            value := stringToInt(s);
            s[numEnd] := prev;
            bytes := value * 1048576;
        end else if (prev = 'K') or (prev = 'k') then begin
            numEnd := len - 2;
            s[numEnd] := #0;
            value := stringToInt(s);
            s[numEnd] := prev;
            bytes := value * 1024;
        end else begin
            numEnd := len - 1;
            s[numEnd] := #0;
            value := stringToInt(s);
            s[numEnd] := last;
            bytes := value;
        end;
    end else begin
        bytes := stringToInt(s);
    end;

    if sectorSize = 0 then exit;
    parsesize := bytes div sectorSize;
end;

{ ---------- PART LIST ---------- }

procedure cmd_list(params : PParamList);
var
    idx        : uint32;
    device     : PStorage_Device;
    bootrecord : PMaster_Boot_Record;
    i          : uint32;
    part       : TPartition_table;
    hasAny     : boolean;
begin
    if paramCount(params) < 2 then begin
        println('Usage: PART list <disk>');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: disk index must be a number.');
        exit;
    end;

    idx := str2int(getParam(1, params));
    device := storagemanager.get_device(idx);

    if device = nil then begin
        print('Error: device ');
        printint(idx);
        print(' not found (');
        printint(storagemanager.get_device_count());
        println(' devices registered).');
        exit;
    end;

    if (device^.readCallback = nil) and (device^.readCallbackAsync = nil) then begin
        println('Error: device has no read support.');
        exit;
    end;

    bootrecord := storagemanager.read_mbr(device);

    if bootrecord = nil then begin
        println('Error: failed to read MBR (memory allocation failed).');
        exit;
    end;

    print('MBR Signature:  '); printhex(bootrecord^.signature); println('');
    print('Boot Marker:    '); printhex(bootrecord^.boot_sector); println('');

    if bootrecord^.boot_sector <> $AA55 then
        println('Warning: invalid boot marker (expected 0xAA55).');

    println('');
    println('SLOT  SYS_ID  START       SIZE        BOOT');
    println('----  ------  -----       ----        ----');

    hasAny := false;
    for i := 0 to 3 do begin
        part := bootrecord^.partition[i];
        if (part.LBA_start <> 0) or (part.sector_count <> 0) then
            hasAny := true;
        print(' ');
        printint(i);
        print('    ');
        printhex(part.system_id);
        print('    ');
        printint(part.LBA_start);
        print('        ');
        printsize(part.sector_count * device^.sectorSize);
        print('        ');
        if mbr.get_bootable(@part) then
            println('yes')
        else
            println('no');
    end;

    if not hasAny then
        println('(all partition slots are empty)');

    kfree(puint32(bootrecord));
end;

{ ---------- PART ADD ---------- }

procedure cmd_add(params : PParamList);
var
    idx        : uint32;
    slot       : sint32;
    lba        : uint32;
    sectors    : uint32;
    freeSec    : uint32;
    device     : PStorage_Device;
    part       : TPartition_table;
    bootrecord : PMaster_Boot_Record;
begin
    if paramCount(params) < 2 then begin
        println('Usage: PART add <disk> [size]');
        println('  size examples: 500MB, 2GB, 1024KB, 4096B');
        println('  omit size to use all remaining space.');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: disk index must be a number.');
        exit;
    end;

    idx := str2int(getParam(1, params));
    device := storagemanager.get_device(idx);

    if device = nil then begin
        print('Error: device ');
        printint(idx);
        print(' not found (');
        printint(storagemanager.get_device_count());
        println(' devices registered).');
        exit;
    end;

    if not device^.writable then begin
        println('Error: device is not writable.');
        exit;
    end;

    if (device^.writeCallback = nil) and (device^.writeCallbackAsync = nil) then begin
        println('Error: device has no write support.');
        exit;
    end;

    { Auto-init: create fresh MBR if none present }
    bootrecord := storagemanager.read_mbr(device);
    if bootrecord <> nil then begin
        if bootrecord^.boot_sector <> $AA55 then begin
            println('No valid MBR found, initialising disk...');
            volumemanager.init_disk(device);
        end;
        kfree(puint32(bootrecord));
    end;

    slot := volumemanager.find_free_slot(device);
    if slot < 0 then begin
        println('Error: no free partition slots (max 4).');
        exit;
    end;

    freeSec := volumemanager.get_free_sector_count(device);

    if freeSec = 0 then begin
        println('Error: no free space on device.');
        exit;
    end;

    if paramCount(params) >= 3 then begin
        sectors := parsesize(getParam(2, params), device^.sectorSize);
        if sectors = 0 then begin
            print('Error: invalid size "');
            print(getParam(2, params));
            println('". Use e.g. 500MB, 2GB, 1024KB, 4096B.');
            exit;
        end;
        if sectors > freeSec then begin
            print('Error: requested ');
            printsize(sectors * device^.sectorSize);
            print(' but only ');
            printsize(freeSec * device^.sectorSize);
            println(' available.');
            exit;
        end;
    end else
        sectors := freeSec;

    lba := volumemanager.find_free_space(device, sectors);
    if lba = 0 then begin
        print('Error: cannot find ');
        printsize(sectors * device^.sectorSize);
        println(' of contiguous space.');
        exit;
    end;

    mbr.setup_partition(@part, lba, sectors);
    part.system_id := 0;
    volumemanager.add_partition(device, slot, part);

    print('Partition added in slot ');
    printint(slot);
    print(': LBA ');
    printint(lba);
    print(', ');
    printsize(sectors * device^.sectorSize);
    println('.');
end;

{ ---------- PART RM ---------- }

procedure cmd_rm(params : PParamList);
var
    idx    : uint32;
    slot   : uint32;
    device : PStorage_Device;
    old    : TPartition_table;
begin
    if paramCount(params) < 3 then begin
        println('Usage: PART rm <disk> <slot>');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: disk index must be a number.');
        exit;
    end;

    if not isNumeric(getParam(2, params)) then begin
        println('Error: slot must be a number (0-3).');
        exit;
    end;

    idx  := str2int(getParam(1, params));
    slot := str2int(getParam(2, params));

    device := storagemanager.get_device(idx);

    if device = nil then begin
        print('Error: device ');
        printint(idx);
        print(' not found (');
        printint(storagemanager.get_device_count());
        println(' devices registered).');
        exit;
    end;

    if slot > 3 then begin
        println('Error: slot must be 0-3.');
        exit;
    end;

    if not device^.writable then begin
        println('Error: device is not writable.');
        exit;
    end;

    if (device^.writeCallback = nil) and (device^.writeCallbackAsync = nil) then begin
        println('Error: device has no write support.');
        exit;
    end;

    old := volumemanager.get_partition(device, slot);
    if (old.LBA_start = 0) and (old.sector_count = 0) then begin
        print('Slot ');
        printint(slot);
        println(' is already empty.');
        exit;
    end;

    volumemanager.remove_partition(device, slot);

    print('Partition slot ');
    printint(slot);
    print(' removed (was LBA ');
    printint(old.LBA_start);
    print(', ');
    printsize(old.sector_count * device^.sectorSize);
    println(').');
end;

{ ---------- PART FORMAT ---------- }

procedure cmd_format(params : PParamList);
var
    idx    : uint32;
    slot   : uint32;
    fsName : pchar;
    device : PStorage_Device;
    part   : TPartition_table;
    vol    : PStorage_Volume;
    fs     : PFilesystem;
    i      : uint32;
begin
    if paramCount(params) < 4 then begin
        println('Usage: PART format <disk> <slot> <fsname>');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: disk index must be a number.');
        exit;
    end;

    if not isNumeric(getParam(2, params)) then begin
        println('Error: slot must be a number (0-3).');
        exit;
    end;

    idx    := str2int(getParam(1, params));
    slot   := str2int(getParam(2, params));
    fsName := getParam(3, params);

    device := storagemanager.get_device(idx);
    if device = nil then begin
        print('Error: device ');
        printint(idx);
        print(' not found (');
        printint(storagemanager.get_device_count());
        println(' devices registered).');
        exit;
    end;

    if slot > 3 then begin
        println('Error: slot must be 0-3.');
        exit;
    end;

    if not device^.writable then begin
        println('Error: device is not writable.');
        exit;
    end;

    part := volumemanager.get_partition(device, slot);
    if (part.LBA_start = 0) and (part.sector_count = 0) then begin
        print('Error: partition slot ');
        printint(slot);
        println(' is empty.');
        exit;
    end;

    { Find the corresponding volume, or create it }
    vol := nil;
    for i := 0 to volumemanager.get_volume_count() - 1 do begin
        vol := volumemanager.get_volume(i);
        if (vol^.device = device) and (vol^.sectorStart = part.LBA_start) then
            break;
        vol := nil;
    end;

    if vol = nil then begin
        volumemanager.create_volume_from_partition(device, part.LBA_start, part.sector_count);
        vol := volumemanager.get_volume(volumemanager.get_volume_count() - 1);
    end;

    if vol^.filesystem <> nil then begin
        print('Warning: already has filesystem "');
        print(vol^.filesystem^.sName);
        println('", overwriting.');
    end;

    fs := filesystemmanager.find_filesystem_by_name(fsName);
    if fs = nil then begin
        print('Error: filesystem "');
        print(fsName);
        println('" not registered.');
        print('Registered: ');
        if filesystemmanager.get_filesystem_count() = 0 then
            println('(none)')
        else begin
            for i := 0 to filesystemmanager.get_filesystem_count() - 1 do begin
                if i > 0 then print(', ');
                print(filesystemmanager.get_filesystem(i)^.sName);
            end;
            println('');
        end;
        exit;
    end;

    if fs^.createCallback = nil then begin
        print('Error: filesystem "');
        print(fsName);
        println('" does not support formatting.');
        exit;
    end;

    vol^.filesystem := fs;
    fs^.createCallback(vol, vol^.sectorCount, vol^.sectorStart, nil);

    { Re-probe filesystem so identify picks up the new signature }
    filesystemmanager.probe_volume(vol);

    print('Partition ');
    printint(slot);
    print(' on disk ');
    printint(idx);
    print(' formatted with ');
    print(fsName);
    print(' (');
    printsize(vol^.sectorCount * vol^.sectorSize);
    println(').');
end;

{ ---------- Main dispatcher ---------- }

procedure command_part(params : PParamList);
var
    subcmd : pchar;
begin
    push_trace('PartCmd.command_part');

    if paramCount(params) = 0 then begin
        println('Usage: PART <list|add|rm|format>');
        exit;
    end;

    subcmd := getParam(0, params);

    if stringEquals(subcmd, 'list') then begin
        cmd_list(params);
        exit;
    end;

    if stringEquals(subcmd, 'add') then begin
        cmd_add(params);
        exit;
    end;

    if stringEquals(subcmd, 'rm') then begin
        cmd_rm(params);
        exit;
    end;

    if stringEquals(subcmd, 'format') then begin
        cmd_format(params);
        exit;
    end;

    print('Unknown subcommand: ');
    println(subcmd);
end;

{ ---------- Init ---------- }

procedure init();
begin
    terminal.registerCommand('PART', @command_part, 'Partition management.');
end;

end.
