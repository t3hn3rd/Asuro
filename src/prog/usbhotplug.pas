{
    Prog->USBHotplug - USB hotplug daemon process.

    Spawns a dedicated 'usbd' process that polls for USB port changes
    approximately once per second using processmanager.proc_sleep_ms.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usbhotplug;

interface

procedure init;

implementation

uses
    usbcore,
    processmanager,
    proctypes,
    syslog;

{ USB daemon process entry point — polls for hotplug events once per second. }
procedure usbd_loop(ctx : PProcessContext);
begin
    while true do begin
        usbcore.usb_check_hotplug;
        processmanager.proc_sleep_ms(1000);
    end;
end;

procedure init;
begin
    processmanager.create('usbd', @usbd_loop, nil, 2);
    syslog.logln('usbd', 'USB hotplug daemon spawned.');
end;

end.
