{
    Driver->Timer->USBHotplug - Timer-driven USB hotplug polling at ~1Hz.

    Hooks into the 1024Hz timer (TMR_0_ISR) and calls
    usbcore.usb_check_hotplug every 1024 ticks (approximately once per second).

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usbhotplug;

interface

procedure init;

implementation

uses
    util,
    TMR_0_ISR,
    usbcore,
    syslog;

const
    { 1024 ticks at 1024Hz ≈ 1 second }
    TICKS_PER_POLL = 1024;

var
    TickCounter : uint32;

procedure on_tick(data : void);
begin
    TickCounter := TickCounter + 1;
    if TickCounter >= TICKS_PER_POLL then begin
        TickCounter := 0;
        usbcore.usb_check_hotplug;
    end;
end;

procedure init;
begin
    TickCounter := 0;
    TMR_0_ISR.hook(uint32(@on_tick));
    syslog.logln('USBHOTPLUG', 'Hooked into 1024Hz timer (~1Hz polling).');
end;

end.
