{
    BGA - Bochs Graphics Adapter Driver.

    Supports the BGA/VBE display adapter emulated by VirtualBox, QEMU,
    and Bochs. Programs the display controller via I/O ports 01CE/01CF
    and reads the framebuffer address from driver.bus.pci BAR0.

    Supports arbitrary resolutions up to VRAM limit (typically 16MB+),
    including 1920x1080, 2560x1440, etc.

    driver.bus.pci device: vendor=$1234, device=$1111 (Bochs VBE Extensions)

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.video.bga;

interface

uses
    core.util, arch.platform.cpu, io.syslog, debug.tracer, driver.video.gpu, driver.bus.pci, driver.types, driver.mgr,
    arch.platform.memory, memory.heap;

procedure init;

implementation

const
    { BGA I/O ports }
    BGA_PORT_INDEX  = $01CE;
    BGA_PORT_DATA   = $01CF;

    { BGA register indices }
    BGA_REG_ID          = $00;
    BGA_REG_XRES        = $01;
    BGA_REG_YRES        = $02;
    BGA_REG_BPP         = $03;
    BGA_REG_ENABLE      = $04;
    BGA_REG_BANK        = $05;
    BGA_REG_VIRT_WIDTH  = $06;
    BGA_REG_VIRT_HEIGHT = $07;
    BGA_REG_X_OFFSET    = $08;
    BGA_REG_Y_OFFSET    = $09;

    { BGA enable flags }
    BGA_DISABLED    = $00;
    BGA_ENABLED     = $01;
    BGA_LFB_ENABLED = $40;

    { Expected BGA ID range (BGA versions 0-5) }
    BGA_ID_MIN = $B0C0;
    BGA_ID_MAX = $B0C5;

    { driver.bus.pci identification }
    BGA_PCI_VENDOR = $1234;
    BGA_PCI_DEVICE = $1111;

var
    BGAPresent    : boolean = false;
    BGAFramebuffer: uint32 = 0;
    BGAMemoryBytes: uint64 = 0;
    BGAPCIBus     : uint8 = 0;
    BGAPCISlot    : uint8 = 0;
    BGAPCIFunc    : uint8 = 0;

{ Write a value to a BGA register }
procedure bgaWriteReg(index : uint16; value : uint16);
begin
    outw(BGA_PORT_INDEX, index);
    outw(BGA_PORT_DATA, value);
end;

{ Read a value from a BGA register }
function bgaReadReg(index : uint16) : uint16;
begin
    outw(BGA_PORT_INDEX, index);
    bgaReadReg := inw(BGA_PORT_DATA);
end;

{ Drivermanagement load callback: called when driver.bus.pci finds a matching device }
function load(ptr : void) : boolean;
var
    dev    : PPCI_Device;
    bar0   : uint32;
    id     : uint16;
begin
    push_trace('driver.video.bga.load');
    load := false;

    if ptr = nil then begin
        io.syslog.logln('BGA', 'load: nil device pointer.');
        pop_trace;
        exit;
    end;

    dev := PPCI_Device(ptr);
    BGAPCIBus  := dev^.bus;
    BGAPCISlot := dev^.slot;
    BGAPCIFunc := dev^.func;

    { Read framebuffer address from driver.bus.pci BARs.
      Native BGA (vendor $1234): framebuffer is at BAR0.
      VMware SVGA (vendor $15AD): BAR0=I/O ports, framebuffer is at BAR1. }
    bar0 := 0;
    if (dev^.address0 and $01) = 0 then begin
        { BAR0 is MMIO — check if it's a plausible framebuffer address }
        bar0 := dev^.address0 and $FFFFFFF0;
        if bar0 < $100000 then
            bar0 := 0; { Too low — probably not the framebuffer }
    end;
    if bar0 = 0 then begin
        { Try BAR1 (VMware SVGA puts framebuffer there) }
        if (dev^.address1 and $01) = 0 then begin
            bar0 := dev^.address1 and $FFFFFFF0;
            if bar0 < $100000 then
                bar0 := 0;
        end;
    end;
    if bar0 <> 0 then begin
        BGAFramebuffer := bar0;
        io.syslog.log('BGA', 'driver.bus.pci framebuffer=$');
        io.syslog.writehexln(BGAFramebuffer);
    end;

    { Probe the BGA I/O port for a valid version ID }
    id := bgaReadReg(BGA_REG_ID);
    if (id >= BGA_ID_MIN) and (id <= BGA_ID_MAX) then begin
        BGAPresent := true;
        { PCI's legacy device_id field contains the vendor ID. VirtualBox's
          BGA data port returns VRAM bytes on a 32-bit read; index $0A is its
          monitor-count interface, not the Bochs 64 KiB memory register.
          See VirtualBox DevVGA.cpp, vgaIoPortReadVbeData. }
        if (dev^.device_id = $80EE) or (dev^.device_id = $15AD) then
            BGAMemoryBytes := inl(BGA_PORT_DATA)
        else if id >= $B0C5 then
            BGAMemoryBytes := uint64(bgaReadReg($0A)) * 65536
        else if id = $B0C4 then
            BGAMemoryBytes := 8 * 1024 * 1024
        else
            BGAMemoryBytes := 4 * 1024 * 1024;
        io.syslog.log('BGA', 'Detected BGA version $');
        io.syslog.writehexln(id);

        { If BAR0 was zero, use the well-known default }
        if BGAFramebuffer = 0 then begin
            BGAFramebuffer := $E0000000;
            io.syslog.log('BGA', 'Using default framebuffer=$');
            io.syslog.writehexln(BGAFramebuffer);
        end;

        { Notify GPU framework that BGA is available }
        driver.video.gpu.markAvailable('BGA');
        load := true;
    end else begin
        io.syslog.logln('BGA', 'load: No valid BGA ID at I/O port.');
    end;

    pop_trace;
end;

{ GPU framework: setMode callback }
function bgaSetMode(width, height : uint32; bpp : uint8;
                     var info : TGPUModeInfo) : boolean;
var
    mapped: pointer;
    bytes: uint64;
    oldWidth, oldHeight, oldBPP, oldEnable: uint16;
begin
    push_trace('driver.video.bga.bgaSetMode');
    bgaSetMode := false;

    if not BGAPresent then begin
        pop_trace;
        exit;
    end;

    if (width = 0) or (height = 0) or (width > 65535) or
       (height > 65535) or (bpp <> 32) then exit;
    bytes := uint64(width) * height * 4;
    if (BGAMemoryBytes = 0) or (bytes > BGAMemoryBytes) or
       (bytes > High(SizeUInt)) then exit;
    mapped := arch.platform.memory.mapDevice(BGAFramebuffer, SizeUInt(bytes));
    if mapped = nil then exit;
    oldWidth := bgaReadReg(BGA_REG_XRES);
    oldHeight := bgaReadReg(BGA_REG_YRES);
    oldBPP := bgaReadReg(BGA_REG_BPP);
    oldEnable := bgaReadReg(BGA_REG_ENABLE);

    { Disable the display while changing mode }
    bgaWriteReg(BGA_REG_ENABLE, BGA_DISABLED);

    { Set resolution and core.gfx.color depth }
    bgaWriteReg(BGA_REG_XRES, width and $FFFF);
    bgaWriteReg(BGA_REG_YRES, height and $FFFF);
    bgaWriteReg(BGA_REG_BPP, bpp);

    { Set virtual width to match physical (no scrolling) }
    bgaWriteReg(BGA_REG_VIRT_WIDTH, width and $FFFF);
    bgaWriteReg(BGA_REG_VIRT_HEIGHT, height and $FFFF);
    bgaWriteReg(BGA_REG_X_OFFSET, 0);
    bgaWriteReg(BGA_REG_Y_OFFSET, 0);

    { Enable with linear framebuffer }
    bgaWriteReg(BGA_REG_ENABLE, BGA_ENABLED or BGA_LFB_ENABLED);

    { Verify mode was set }
    if (bgaReadReg(BGA_REG_XRES) <> width) or
       (bgaReadReg(BGA_REG_YRES) <> height) or
       (bgaReadReg(BGA_REG_BPP) <> bpp) then begin
        bgaWriteReg(BGA_REG_ENABLE, BGA_DISABLED);
        bgaWriteReg(BGA_REG_XRES, oldWidth);
        bgaWriteReg(BGA_REG_YRES, oldHeight);
        bgaWriteReg(BGA_REG_BPP, oldBPP);
        bgaWriteReg(BGA_REG_VIRT_WIDTH, oldWidth);
        bgaWriteReg(BGA_REG_VIRT_HEIGHT, oldHeight);
        bgaWriteReg(BGA_REG_ENABLE, oldEnable);
        io.syslog.logln('BGA', 'setMode: XRES verify failed.');
        pop_trace;
        exit;
    end;



    { Fill in the mode info for the caller }
    info.Width       := width;
    info.Height      := height;
    info.BPP         := bpp;
    info.Framebuffer := PtrUInt(mapped);
    info.Pitch       := (width * uint32(bpp)) div 8;

    io.syslog.log('BGA', 'Mode set: ');
    io.syslog.writeint(width);
    io.syslog.writestring('x');
    io.syslog.writeint(height);
    io.syslog.writestring('x');
    io.syslog.writeint(bpp);
    io.syslog.writestring(' fb=$');
    io.syslog.writehexln(BGAFramebuffer);

    bgaSetMode := true;
    pop_trace;
end;

{ Initialize BGA driver: register with GPU framework and driver.mgr }
procedure init;
var
    devID : TDeviceIdentifier;
begin
    push_trace('driver.video.bga.init');
    io.syslog.logln('BGA', 'INIT BEGIN.');

    { Register with GPU framework for mode setting (priority 10 = preferred over VBE) }
    driver.video.gpu.registerDriver('BGA', 10, @bgaSetMode);

    { Register with driver.mgr for driver.bus.pci auto-detection.
      Match any VGA-compatible display controller (class=$03, subclass=$00).
      The load callback probes the BGA I/O ports to verify hardware support. }
    devID.Bus := biPCI;
    devID.id0 := idANY;            { device_id: any }
    devID.id1 := $03;              { class_code: display controller }
    devID.id2 := $00;              { subclass: VGA compatible }
    devID.id3 := idANY;            { prog_if: any }
    devID.id4 := idANY;            { vendor_id: any }
    devID.ex  := nil;
    driver.mgr.register_driver('BGA Display Driver', @devID, @load);

    io.syslog.logln('BGA', 'INIT END.');
    pop_trace;
end;


end.
