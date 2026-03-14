unit driver.storage.boot;

interface

uses
    boot.mgr,
    driver.storage.mgr,
    arch.x86.multiboot;

implementation

procedure init();
begin
    driver.storage.mgr.set_boot_drive_byte((multibootinfo^.boot_device shr 24) and $FF);   
end;

initialization
    boot.mgr.registerBoot('driver.storage.boot', @init, 'Setup Boot Drive', 'driver.storage.mgr');

end.