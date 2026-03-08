{
    ISR->IOAPIC - I/O APIC and Local APIC minimal support.

    On systems where VirtualBox (or real hardware) routes driver.bus.pci interrupts
    through the I/O APIC instead of the legacy 8259 PIC, we must program
    the IOAPIC redirection entry for each driver.bus.pci IRQ we want to receive.

    ISA interrupts (timer, driver.hid.keyboard) continue to work through the 8259
    PIC via Virtual Wire mode (PIC -> LINT0 -> Local APIC -> CPU).

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit arch.x86.isr.ioapic;

interface

uses
    core.util, arch.x86.util,
    memory.heap,
    io.syslog;

{ Initialise IOAPIC/LAPIC support — maps MMIO regions, ensures LAPIC
  is enabled.  Safe to call even if the hardware doesn't have an IOAPIC
  (will detect and bail out). }
procedure init();

{ Route a PCI interrupt through the IOAPIC.
    irq    — PCI IRQ number (the value from PCI config interrupt_line)
    vector — IDT vector to deliver (typically irq + 32) }
procedure route_pci_irq(irq : uint8; vector : uint8);

{ Send End-of-Interrupt to the Local APIC.
  Must be called for every IOAPIC-delivered (Fixed mode) interrupt.
  Safe no-op if IOAPIC support was not initialised. }
procedure lapic_eoi();

{ True after init() succeeds — ISR_N checks this to know whether LAPIC
  EOI is needed. }
var
    ioapic_present : boolean;

implementation

const
    IOAPIC_PHYS     = $FEC00000;
    LAPIC_PHYS      = $FEE00000;

    { IOAPIC register offsets (indirect via IOREGSEL / IOWIN) }
    IOREGSEL        = $00;
    IOWIN           = $10;

    { IOAPIC registers }
    IOAPIC_ID       = $00;
    IOAPIC_VER      = $01;
    IOAPIC_REDTBL   = $10;   { base — each entry is 2 dwords }

    { LAPIC register offsets }
    LAPIC_SVR       = $F0;   { Spurious Interrupt Vector Register }
    LAPIC_EOI_REG   = $B0;   { End-of-Interrupt register }

{ ---- low-level IOAPIC register access ---- }

procedure ioapic_write(reg : uint32; val : uint32);
begin
    puint32(IOAPIC_PHYS + IOREGSEL)^ := reg;
    puint32(IOAPIC_PHYS + IOWIN)^ := val;
end;

function ioapic_read(reg : uint32) : uint32;
begin
    puint32(IOAPIC_PHYS + IOREGSEL)^ := reg;
    ioapic_read := puint32(IOAPIC_PHYS + IOWIN)^;
end;

{ ---- public API ---- }

procedure init();
var
    ver   : uint32;
    svr   : uint32;
begin
    ioapic_present := false;

    { Map the IOAPIC and LAPIC MMIO pages so we can access them }
    kpalloc(IOAPIC_PHYS);
    kpalloc(LAPIC_PHYS);

    { Probe: read IOAPIC version register — should return non-zero/non-$FF }
    ver := ioapic_read(IOAPIC_VER);
    if (ver = 0) or (ver = $FFFFFFFF) then begin
        io.syslog.logln('IOAPIC', 'Not detected — driver.bus.pci interrupts rely on 8259 PIC.');
        exit;
    end;

    io.syslog.logln('IOAPIC', 'Detected.');

    { Ensure the Local APIC is software-enabled (bit 8 of SVR).
      We set the spurious vector to $FF which is unused. }
    svr := puint32(LAPIC_PHYS + LAPIC_SVR)^;
    if (svr and $100) = 0 then begin
        svr := svr or $100;        { Enable APIC }
        svr := (svr and $FFFFFF00) or $FF; { Spurious vector = 0xFF }
        puint32(LAPIC_PHYS + LAPIC_SVR)^ := svr;
        io.syslog.logln('IOAPIC', 'LAPIC software-enabled.');
    end;

    ioapic_present := true;
end;

procedure route_pci_irq(irq : uint8; vector : uint8);
var
    lo : uint32;
begin
    if not ioapic_present then exit;

    { Build low dword of redirection entry:
        bits  7:0  — delivery vector
        bits 10:8  — delivery mode  (000 = Fixed)
        bit  11    — destination mode (0 = Physical)
        bit  13    — pin polarity   (1 = active-low for driver.bus.pci)
        bit  15    — trigger mode   (1 = level for driver.bus.pci)
        bit  16    — mask           (0 = not masked) }
    lo := uint32(vector);
    lo := lo or (1 shl 13);    { active-low }
    lo := lo or (1 shl 15);    { level-triggered }

    { Write low dword first, then high dword (dest APIC = 0, the BSP) }
    ioapic_write(IOAPIC_REDTBL + uint32(irq) * 2, lo);
    ioapic_write(IOAPIC_REDTBL + uint32(irq) * 2 + 1, 0);

    io.syslog.log('IOAPIC', 'Routed IRQ ');
    io.syslog.writeint(irq);
    io.syslog.writestring(' -> vector ');
    io.syslog.writeint(vector);
    io.syslog.writestringln('');
end;

procedure lapic_eoi();
begin
    if ioapic_present then
        puint32(LAPIC_PHYS + LAPIC_EOI_REG)^ := 0;
end;

end.
