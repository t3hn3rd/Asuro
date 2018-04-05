{ ************************************************
  * Asuro
  * Unit: Drivers/PCI
  * Description: PCI Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit PCI;

interface

uses
    util,
    console,
    drivertypes,
    ATA,
    lmemorymanager,
    drivermanagement;

type 

    TPCI_Device_Bridge = bitpacked record
        device_id          : uint16;
        vendor_id          : uint16;
        status             : uint16;
        command            : uint16;
        class_code         : uint8; 
        subclass_class     : uint8; 
        prog_if            : uint8;
        revision_id        : uint8;
        BIST               : uint8;
        header_type        : uint8;
        latency_timer      : uint8;
        cache_size         : uint8;
        address0           : uint32;
        address1           : uint32;
        latency_timer2     : uint8;
        subordinate_bus    : uint8;
        secondery_bus      : uint8;
        primary_bus        : uint8;
        secondery_status   : uint16;
        io_limit           : uint8;
        io_base            : uint8;
        memory_limit       : uint16;
        memory_base        : uint16;
        pref_memory_limit  : uint16;
        pref_memory_base   : uint16;
        pref_base_upper    : uint32;
        pref_limit_upper   : uint32;
        io_limit_upper     : uint16;
        io_base_upper      : uint16;
        reserved           : uint16;
        reserved0          : uint8;
        capability_pointer : uint8;
        epx_rom_addr       : uint32;
        bridge_control     : uint16;
        interrupt_pin      : uint8;
        interrupt_line     : uint8;
    end;

var
    devices : array[0..1024] of TPCI_Device;
    busses : array[0..256] of TPCI_Device_Bridge;

    device_count : uint16;
    bus_count : uint8 = 1;
    get_device_count : uint8;

procedure init();
procedure scanBus(bus : uint8);
function loadDeviceConfig(bus : uint8; slot : uint8; func : uint8) : boolean;
function getDeviceInfo(class_code : uint8; subclass_code : uint8; prog_if : uint8; var count : uint32) : TdeviceArray;  //(Will in future)returns TPCI_DEVICE.vendor_id := 0xFFFF if no device found.

implementation 

function load(ptr : void) : boolean;
var
    current_bus : uint8;

begin
    console.writestringln('PCI: Scanning Bus: 0');
    scanBus(0);
    //while unscanned busses scan busses
    current_bus := 1;
    while true do begin
        if current_bus < bus_count then begin
            console.writestringln('PCI: Scanning Bus: ');
            console.writeint(bus_count);
            scanBus(current_bus);
            current_bus := current_bus + 1;
        end else break;
    end;
    load:= true;
end;

procedure init();
var
    DevID : TDeviceIdentifier;

begin
    console.writestringln('PCI: INIT BEGIN.');
    DevID.Bus:= biUnknown;
    DevID.id0:= 0;
    DevID.id1:= 0;
    DevID.id2:= 0;
    DevID.id3:= 0;
    DevID.ex:= nil;
    drivermanagement.register_driver_ex('PCI Driver', @DevID, @load, true);
    console.writestringln('PCI: INIT END.');
end;

procedure scanBus(bus : uint8);
var
    slot : uint16;
    func : uint16;
    result : boolean;

begin
    for slot := 0 to 31 do begin
        result := loadDeviceConfig(bus, slot, 0);
        if result = true then begin
            if devices[device_count - 1].header_type and $40 = 40 then begin
                for func := 1 to 8 do begin
                    loadDeviceConfig(bus, slot, func);
                    psleep(1000);
                end;
            end;
        end;
    end;
end;

procedure requestConfig(bus : uint8; slot : uint8; func : uint8; row : uint8);
var
    packet : uint32;
    
begin
    packet := ($1 shl 31);
    packet := packet or (bus shl 16);
    packet := packet or ((slot) shl 11);
    packet := packet or ((func) shl 8);
    packet := packet or ((row) shl 2);

    outl($CF8, uint32(packet)); 
end;

procedure loadBusConfig(bus : uint8; slot : uint8; func : uint8; device : TPCI_Device);
var
    busT : TPCI_Device_Bridge;
    data : uint32;

begin

    busT.device_id := device.device_id;
    busT.vendor_id := device.vendor_id;
    busT.status := device.status;
    busT.command := device.command;
    busT.class_code := device.class_code;
    busT.subclass_class := device.subclass_class;
    busT.prog_if := device.prog_if;
    busT.revision_id := device.revision_id;
    busT.BIST := device.BIST;
    busT.header_type := device.header_type;
    busT.latency_timer := device.latency_timer;
    busT.cache_size := device.cache_size;

    requestConfig(bus, slot, func, 4);
    busT.address0 := inl($CFC);
    requestConfig(bus, slot, func, 5);
    busT.address1 := inl($CFC);

    requestConfig(bus, slot, func, 6);
    data := inl($CFC);
    busT.latency_timer2 := getbyte(data, 0);
    busT.subordinate_bus := getbyte(data, 1);
    busT.secondery_bus := getbyte(data, 2);
    busT.primary_bus := getbyte(data, 3);

    requestConfig(bus, slot, func, 7);
    data := inl($CFC);
    busT.secondery_status := getword(data, false);
    busT.io_limit := getbyte(data, 2);
    busT.io_base := getbyte(data, 3);

    requestConfig(bus, slot, func, 8);
    data := inl($CFC);
    busT.memory_limit := getword(data, false);
    busT.memory_base := getword(data, true);

    requestConfig(bus, slot, func, 9);
    data := inl($CFC);
    busT.pref_memory_limit := getword(data, false);
    busT.pref_memory_base := getword(data, true);

    requestConfig(bus, slot, func, 10);
    busT.pref_base_upper := inl($CFC);
    requestConfig(bus, slot, func, 11);
    busT.pref_limit_upper := inl($CFC);

    requestConfig(bus, slot, func, 11);
    data := inl($CFC);
    busT.io_limit_upper := getword(data, false);
    busT.io_base_upper := getword(data, true);

    requestConfig(bus, slot, func, 12);
    data := inl($CFC);
    busT.reserved := getword(data, false);
    busT.reserved0 := getbyte(data, 2);
    busT.capability_pointer := getbyte(data, 3);

    requestConfig(bus, slot, func, 13);
    busT.epx_rom_addr := inl($CFC);

    requestConfig(bus, slot, func, 14);
    data := inl($CFC);
    busT.bridge_control := getword(data, false);
    busT.interrupt_pin := getbyte(data, 2);
    busT.interrupt_line := getbyte(data, 3);

    busses[bus_count] := busT;
    bus_count := bus_count + 1;

end;

function loadDeviceConfig(bus : uint8; slot : uint8; func : uint8) : boolean;
var
    device : TPCI_Device;
    data : uint32;
    DevID : PDeviceIdentifier;

begin

    loadDeviceConfig := false;

    requestConfig(bus, slot, func, 0);
    data := inl($CFC);
    device.device_id := getword(data, false);
    device.vendor_id := getword(data, true);

    if device.vendor_id = $FFFF then exit;

    requestConfig(bus, slot, func, 1);
    data := inl($CFC);
    device.status := getword(data, false);
    device.command := getword(data, true);

    requestConfig(bus, slot, func, 2);
    data := inl($CFC);
    device.class_code := getbyte(data, 3);
    device.subclass_class := getbyte(data, 2);
    device.prog_if := getbyte(data, 1);
    device.revision_id := getbyte(data, 0);

    requestConfig(bus, slot, func, 3);
    data := inl($CFC);
    device.BIST := getbyte(data, 3);
    device.header_type := getbyte(data, 2);
    device.latency_timer := getbyte(data, 1);
    device.cache_size := getbyte(data, 0);

    if device.header_type and $7 = 0 then begin 
        loadDeviceConfig := true;
    end else begin
        loadBusConfig(bus, slot, func, device);
        exit(false);
    end;
     //TODO implement other types?

    requestConfig(bus, slot, func, 4);
    device.address0 := inl($CFC);
    requestConfig(bus, slot, func, 5);
    device.address1 := inl($CFC);
    requestConfig(bus, slot, func, 6);
    device.address2 := inl($CFC);
    requestConfig(bus, slot, func, 7);
    device.address3 := inl($CFC);
    requestConfig(bus, slot, func, 8);
    device.address4 := inl($CFC);
    requestConfig(bus, slot, func, 9);
    device.address5 := inl($CFC);
    
    requestConfig(bus, slot, func, 10);
    device.CIS_Pointer := inl($CFC);

    requestConfig(bus, slot, func, 11);
    data := inl($CFC);
    device.subsystem_id := getword(data, false);
    device.subsystem_vid := getword(data, true);
    
    requestConfig(bus, slot, func, 12);
    device.exp_rom_addr := inl($CFC);

    requestConfig(bus, slot, func, 13);
    data := inl($CFC);
    device.reserved0 := getword(data, false);
    device.reserved1 := getbyte(data, 2);
    device.capabilities := getbyte(data, 3);

    requestConfig(bus, slot, func, 14);
    device.reserved2 := inl($CFC);

    requestConfig(bus, slot, func, 15);
    data := inl($CFC);
    device.max_latency := getbyte(data, 0);
    device.min_grant := getbyte(data, 1);
    device.interrupt_pin := getbyte(data, 2);
    device.interrupt_line := getbyte(data, 3);

    DevID:= PDeviceIdentifier(kalloc(sizeof(TDeviceIdentifier)));
    DevID^.Bus:= biPCI;
    DevID^.id0:= device.device_id;
    DevID^.id1:= device.class_code;
    DevID^.id2:= device.subclass_class;
    DevID^.id3:= device.prog_if;
    DevID^.ex:= nil;

    console.writestring('PCI: Found Device: ');
    console.writehex(device.header_type);
    console.writestring('  ');
    console.writehex(device.device_id);        
    console.writestring('  ');        
    console.writehex(device.class_code);        
    console.writestring('  ');
    console.writehex(device.subclass_class);        
    console.writestring('  ');
    console.writehexln(device.prog_if);

    drivermanagement.register_device('PCI Device', DevID, @device);
    
    kfree(void(DevID));

    devices[device_count] := device;
    device_count := device_count + 1;

    //if device.class_code = 1 then ata.init(device);
    
end;

function getDeviceInfo(class_code : uint8; subclass_code : uint8; prog_if : uint8; var count : uint32) : TDeviceArray; 
var
    i : uint16;
    devices_out : array[0..31] of TPCI_Device;

begin
    console.writestring('DEV COUNT: ');
    console.writeintln(device_count);
    count := 0;
    if prog_if <> $FF then begin
        for i:=0 to device_count+1 do begin
            if (devices[i].class_code = class_code) and (devices[i].subclass_class = subclass_code) and (devices[i].prog_if = prog_if) then begin
                devices_out[count] := devices[i];
                count := count + 1;
            end;
        end;
    end else begin
        for i:=0 to device_count+1 do begin
            if (devices[i].class_code = class_code) and (devices[i].subclass_class = subclass_code) then begin
                devices_out[count] := devices[i];
                count := count + 1;
            end;
        end;
    end;

    getDeviceInfo := devices_out;
    
end;

end.