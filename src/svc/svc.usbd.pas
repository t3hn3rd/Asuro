{
    Prog->USBHotplug - driver.bus.usb hotplug daemon process.

    Spawns a dedicated 'usbd' process that polls for driver.bus.usb port changes
    approximately once per second using proc.mgr.proc_sleep_ms.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit svc.usbd;

interface

procedure init;

implementation

uses
    boot.mgr,
    driver.bus.usb.core,
    proc.mgr,
    proc.types,
    io.syslog;

{ driver.bus.usb daemon process entry point — polls for hotplug events once per second. }
procedure usbd_loop(ctx : PProcessContext);
begin
    while true do begin
        driver.bus.usb.core.usb_check_hotplug;
        proc.mgr.proc_sleep_ms(1000);
    end;
end;

procedure init;
begin
    proc.mgr.create('usbd', @usbd_loop, nil, 2);
    io.syslog.logln('usbd', 'driver.bus.usb hotplug daemon spawned.');
end;

Initialization
    boot.mgr.registerBoot('svc.usbd', @init, 'USB Daemon', BOOT_MGR_BARRIER_LATE);

end.
