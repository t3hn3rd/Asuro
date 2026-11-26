unit arch.common.power;

interface

{ Power off a QEMU PC with SeaBIOS. Halt if the machine stays on. }
procedure powerOff;

implementation

uses
    arch.platform.cpu;

const
    QEMU_PM1_CONTROL = $604;
    ACPI_SLEEP_ENABLE = $2000;

procedure powerOff;
begin
    outw(QEMU_PM1_CONTROL, ACPI_SLEEP_ENABLE);
    asm
        cli
    @halt:
        hlt
        jmp @halt
    end;
end;

end.
