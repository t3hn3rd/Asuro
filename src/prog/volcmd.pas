{
    Prog->VolCmd - Command-line tools for viewing volumes.

    Shell command: VOL [subcommand]
    Subcommands:
        list                           - List all volumes (device, size, FS)
        info     <index>               - Show volume details

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit volcmd;

interface

procedure init();

implementation

uses
    console,
    lists,
    lmemorymanager,
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

{ Check whether a string contains only digit characters }
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

{ Print a byte count in human-readable form: B, KB, MB or GB }
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

{ ---------- VOL LIST ---------- }

procedure cmd_list();
var
    i      : uint32;
    count  : uint32;
    vol    : PStorage_Volume;
begin
    count := volumemanager.get_volume_count();

    if count = 0 then begin
        println('No volumes registered.');
        exit;
    end;

    println('IDX  DEVICE        SIZE        FS');
    println('---  ------        ----        --');

    for i := 0 to count - 1 do begin
        vol := volumemanager.get_volume(i);
        if vol = nil then continue;

        print(' ');
        printint(i);
        print('   ');

        { Device info }
        if vol^.device <> nil then begin
            printint(vol^.device^.id);
            print(' (');
            print(storagemanager.controller_type_2_string(vol^.device^.controller));
            print(')');
        end else
            print('?');
        print('     ');

        { Size }
        printsize(vol^.sectorCount * vol^.sectorSize);
        print('      ');

        { Filesystem }
        if vol^.filesystem <> nil then
            print(vol^.filesystem^.sName)
        else
            print('none');

        println('');
    end;
end;

{ ---------- VOL INFO ---------- }

procedure cmd_info(params : PParamList);
var
    idx    : uint32;
    vol    : PStorage_Volume;
begin
    if paramCount(params) < 2 then begin
        println('Usage: VOL info <index>');
        exit;
    end;

    if not isNumeric(getParam(1, params)) then begin
        println('Error: volume index must be a number.');
        exit;
    end;

    idx := str2int(getParam(1, params));
    vol := volumemanager.get_volume(idx);

    if vol = nil then begin
        print('Error: volume ');
        printint(idx);
        print(' not found (');
        printint(volumemanager.get_volume_count());
        println(' volumes registered).');
        exit;
    end;

    print('Sector Start:   '); printint(vol^.sectorStart); println('');
    print('Sector Count:   '); printint(vol^.sectorCount); println('');
    print('Sector Size:    '); printint(vol^.sectorSize); println(' bytes');

    print('Size:           '); printsize(vol^.sectorCount * vol^.sectorSize); println('');

    print('Free:           '); printsize(vol^.freeSectors * vol^.sectorSize); println('');
    print('Boot Drive:     ');
    if vol^.isBootDrive then println('yes') else println('no');

    print('Filesystem:     ');
    if vol^.filesystem <> nil then
        println(vol^.filesystem^.sName)
    else
        println('none');

    print('Device:         ');
    if vol^.device <> nil then begin
        printint(vol^.device^.id);
        print(' (');
        print(storagemanager.controller_type_2_string(vol^.device^.controller));
        println(')');
    end else
        println('none');
end;

{ ---------- Main dispatcher ---------- }

procedure command_vol(params : PParamList);
var
    subcmd : pchar;
begin
    push_trace('VolCmd.command_vol');

    if paramCount(params) = 0 then begin
        println('Usage: VOL <list|info>');
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

    print('Unknown subcommand: ');
    println(subcmd);
end;

{ ---------- Init ---------- }

procedure init();
begin
    terminal.registerCommand('VOL', @command_vol, 'Volume information & management.');
end;

end.
