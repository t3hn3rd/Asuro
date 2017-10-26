{ ************************************************
  * Asuro
  * Unit: Drivers/ATA
  * Description: ATA DMA Driver
  * currently a hack needs to be re-written if works
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit ATA;

interface

uses
    util,
    drivertypes,
    console,
    terminal,
    isr76;

type 

    intptr = ^uint32;

    ATA_Device = record 
        reading : boolean;
        master  : boolean;
        primary : boolean;
        currentIndex : uint16;
        device_lba : uint32;
        Command_Register : uint32;
        Status_Register  : uint32;
        PRDT_Address_Reg : uint32;
    end;

    Physical_Region_Descriptor = bitpacked record 
        empty0       : 0..1;
        MRPB_Address : 1..32; // memory address
        Byte_Count   : 32..47; // size in bytes (0 is 64K)
        empty1       : 47..63;
        EOT          : 63..64; // end of table
        empty2       : 64..65;
    end;

    ATA_Command_Buffer = bitpacked record
        start_stop_bit : 0..1; // 0 stopped
        read_write_bit : 3..4; // 0 read
    end;

    ATA_Status_Buffer = bitpacked record end;

    ATA_IO_PORT = record
        data         : uint16;
        error        : uint8;
        sector_count : uint8;
        lba_low      : uint8;
        lba_mid      : uint8;
        lba_hi       : uint8;
        drive        : uint8;
        command      : uint8; 
    end;

var 
    ports : ATA_IO_PORT;
    devices : array[0..4] of ATA_Device;
    PRD_Table : array[0..100] of Physical_Region_Descriptor; // up 64K r/w each, upto 8000 supported per table.
    controller : TPCI_device;

procedure init(_controller : TPCI_device);
procedure read(address : uint32; data_lba : uint32; data_bytes : uint32);
procedure write(address : uint32);
procedure callback(data : void);

implementation

procedure init(_controller : TPCI_device);
begin
    console.writestringln('ATA Driver INIT');
    isr76.hook(uint32(@callback));

    controller := _controller;
    devices[0].primary := true;
    devices[0].Command_Register := controller.address4;
    devices[0].Status_Register := controller.address4 + 2;
    devices[0].PRDT_Address_Reg := controller.address4 + 4;

    ports.command := $1F7;
    ports.lba_low := $1F3; 
    ports.lba_mid := $1F4;
    ports.lba_hi  := $1F5;
    ports.drive   := $1F6;
    ports.sector_count := $F2;

end;

procedure read(address : uint32; data_lba : uint32; data_bytes : uint32);
var
    PRD : Physical_Region_Descriptor;
    empty_table : array[0..100] of Physical_Region_Descriptor;
    i : uint32;
    ptr : intptr;
    sector_count : uint8;
    cb : ATA_Command_Buffer;
begin
    devices[0].device_lba := data_lba;
    devices[0].reading := true;
    PRD_Table := empty_table;
    PRD.MRPB_Address := address;

    //limit
    if data_bytes > 6400000 then exit;

    if data_bytes < 64001 then begin
        PRD.EOT := 1;
        if data_bytes = 64000 then begin
            PRD.Byte_Count := 0
        end else begin
            PRD.Byte_Count := data_bytes;
        end;
    end else begin
        while data_bytes > 64000 do begin
            PRD.EOT := 0;
            PRD.MRPB_Address := address;
            PRD.Byte_Count := 0;

            data_bytes := data_bytes - 64000;
            address := address + 64000;
        end;

        PRD.EOT := 1;
        PRD.MRPB_Address := address;
        PRD.Byte_Count := data_bytes;

    end;

    ptr := intptr(devices[0].PRDT_Address_Reg);
    ptr^ := uint32(@PRD_Table);

    ptr := intptr(devices[0].Status_Register);
    ptr^ := 0;

    outb(ports.drive, $A0);
    outb(ports.sector_count, 125);
    outb(ports.lba_low, (data_lba and $000000FF));
    outb(ports.lba_mid, (data_lba and $0000FF00) SHR 8);
    outb(ports.lba_hi, (data_lba and $0000FF00) SHR 16);
    outb(ports.command, $C8);
    devices[0].currentIndex := 1;

    cb.start_stop_bit := 1;
    cb.read_write_bit := 0;

    ptr := intptr(devices[0].Command_Register);
    ptr^ := uint8(cb);
    
end;

procedure write(address : uint32); begin
end;

procedure callback(data : void); //need r/w, is last
var
    cb : ATA_Command_Buffer;
    ptr : intptr;
    tmp : uint16;
begin
    if(PRD_Table[devices[0].currentIndex - 1].EOT = 1) then begin
        //other stuff
        exit;
    end;

    if(devices[0].reading = true) then begin
        if(PRD_Table[devices[0].currentIndex].EOT = 0) then begin 
            outb(ports.sector_count, 125);
            outb(ports.lba_low, (devices[0].device_lba + (64000 * devices[0].currentIndex)) and $000000FF);
            outb(ports.lba_mid, (((devices[0].device_lba + (64000 * devices[0].currentIndex))) and $0000FF00) SHR 8);
            outb(ports.lba_hi, (((devices[0].device_lba + (64000 * devices[0].currentIndex))) and $0000FF00) SHR 16); 
            outb(ports.command, $C8);
        end else begin
           tmp := uint16((PRD_Table[devices[0].currentIndex].Byte_Count and $FFFF) DIV 512); 
            outb(ports.sector_count, uint16(tmp)); // wont work if 64k
            outb(ports.lba_low, (devices[0].device_lba + (64000 * devices[0].currentIndex)) and $000000FF);
            outb(ports.lba_mid, (((devices[0].device_lba + (64000 * devices[0].currentIndex))) and $0000FF00) SHR 8);
            outb(ports.lba_hi, (((devices[0].device_lba + (64000 * devices[0].currentIndex))) and $0000FF00) SHR 16);
            outb(ports.command, $C8);
        end;

            cb.start_stop_bit := 1;
            cb.read_write_bit := 0;

            ptr := intptr(devices[0].Command_Register);
            ptr^ := uint8(cb);

        devices[0].currentIndex := devices[0].currentIndex + 1;
    end;
end;



end.