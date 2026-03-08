{
    Prog->DiskCmd - Command-line tools for viewing physical storage devices.

    Shell command: DISK [subcommand]
    Subcommands:
        list                     - List all storage devices
        info    <disk>           - Show device details
        wipe    <disk>           - Zero entire disk (removes all partitions)

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.diskcmd;

interface

procedure init();

implementation

uses
    core.ds.lists,
    memory.heap,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,
    io.stdio,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vol.mgr;

var
    g_out : POutBuf;

{ ---------- helpers ---------- }

function wnd : uint32;
begin
    wnd := 0;
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
    io.stdio.bufWriteStr(g_out, s);
end;

procedure println(s : pchar);
begin
    io.stdio.bufWriteStrLn(g_out, s);
end;

procedure printint(v : uint32);
begin
    io.stdio.bufWriteInt(g_out, integer(v));
end;

procedure printhex(v : uint32);
begin
    io.stdio.bufWriteHex(g_out, v);
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

{ ---------- DISK LIST ---------- }

procedure cmd_list();
var
    i        : uint32;
    count    : uint32;
    device   : PStorage_Device;
    volCount : uint32;
begin
    count := driver.storage.mgr.get_device_count();

    if count = 0 then begin
        println('No storage devices registered.');
        exit;
    end;

    println('IDX  TYPE          WRITABLE  SIZE        PARTS');
    println('---  ----          --------  ----        -----');

    for i := 0 to count - 1 do begin
        device := driver.storage.mgr.get_device(i);
        if device = nil then continue;

        print(' ');
        printint(i);
        print('   ');

        print(driver.storage.mgr.controller_type_2_string(device^.controller));
        print('          ');

        if device^.writable then
            print('yes       ')
        else
            print('no        ');

        printsize(device^.maxSectorCount * device^.sectorSize);
        print('    ');

        if device^.volumes <> nil then
            volCount := DL_Size(device^.volumes)
        else
            volCount := 0;
        printint(volCount);

        println('');
    end;
end;

{ ---------- DISK INFO ---------- }

procedure cmd_info(params : PParamList);
var
    idx      : uint32;
    device   : PStorage_Device;
    volCount : uint32;
    freeSec  : uint32;
begin
    if paramCount(params) < 2 then begin
        println('Usage: DISK info <disk>');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: disk index must be a number.');
        exit;
    end;

    idx := str2int(getParam(1, params));
    device := driver.storage.mgr.get_device(idx);

    if device = nil then begin
        print('Error: device ');
        printint(idx);
        print(' not found (');
        printint(driver.storage.mgr.get_device_count());
        println(' devices registered).');
        exit;
    end;

    print('Device ID:       '); printint(device^.id); println('');
    print('Controller:      '); println(driver.storage.mgr.controller_type_2_string(device^.controller));
    print('Controller ID:   '); printhex(device^.controllerId0); println('');
    print('Writable:        ');
    if device^.writable then println('yes') else println('no');
    print('Sector Size:     '); printint(device^.sectorSize); println(' bytes');
    print('Total Sectors:   '); printint(device^.maxSectorCount); println('');
    print('Total Size:      '); printsize(device^.maxSectorCount * device^.sectorSize); println('');
    print('Start Sector:    '); printint(device^.start); println('');

    freeSec := driver.storage.vol.mgr.get_free_sector_count(device);
    print('Free Space:      '); printsize(freeSec * device^.sectorSize); println('');

    if device^.volumes <> nil then
        volCount := DL_Size(device^.volumes)
    else
        volCount := 0;
    print('Partitions:      '); printint(volCount); println('');
end;

{ ---------- DISK WIPE ---------- }

procedure cmd_wipe(params : PParamList);
var
    idx      : uint32;
    device   : PStorage_Device;
    buf      : puint32;
    sector   : uint32;
    batch    : uint32;
    remain   : uint32;
    bufSects : uint32;
begin
    if paramCount(params) < 2 then begin
        println('Usage: DISK wipe <disk>');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: disk index must be a number.');
        exit;
    end;

    idx := str2int(getParam(1, params));
    device := driver.storage.mgr.get_device(idx);

    if device = nil then begin
        print('Error: device ');
        printint(idx);
        print(' not found (');
        printint(driver.storage.mgr.get_device_count());
        println(' devices registered).');
        exit;
    end;

    if not device^.writable then begin
        println('Error: device is not writable.');
        exit;
    end;

    if device^.dispatchWrite = nil then begin
        println('Error: device has no write support.');
        exit;
    end;

    { Remove all volumes for this device first }
    driver.storage.vol.mgr.init_disk(device);

    { Allocate a zero buffer - 64 sectors at a time }
    bufSects := 64;
    buf := puint32(kalloc(bufSects * device^.sectorSize));
    memset(uint32(buf), 0, bufSects * device^.sectorSize);

    print('Wiping device ');
    printint(idx);
    print(' (');
    printsize(device^.maxSectorCount * device^.sectorSize);
    println(')...');

    sector := 0;
    while sector < device^.maxSectorCount do begin
        remain := device^.maxSectorCount - sector;
        if remain > bufSects then
            batch := bufSects
        else
            batch := remain;

        driver.storage.mgr.storage_write(device, sector, batch, buf);
        sector := sector + batch;
    end;

    kfree(buf);

    print('Device ');
    printint(idx);
    println(' wiped.');
end;

{ ---------- Main dispatcher ---------- }

procedure command_disk(params : PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    subcmd : pchar;
begin
    g_out := stdout_buf;
    push_trace('DiskCmd.command_disk');

    if paramCount(params) = 0 then begin
        println('Usage: DISK <list|info|wipe>');
        exit;
    end;

    subcmd := getParam(0, params);

    if stringEquals(subcmd, 'list') then begin
        cmd_list();
        exit;
    end;

    if stringEquals(subcmd, 'info') then begin
        cmd_info(params);
        exit;
    end;

    if stringEquals(subcmd, 'wipe') then begin
        cmd_wipe(params);
        exit;
    end;

    print('Unknown subcommand: ');
    println(subcmd);
end;

{ ---------- Init ---------- }

procedure init();
begin
    io.stdio.registerCommand('DISK', @command_disk, 'Storage device information.');
end;

end.
