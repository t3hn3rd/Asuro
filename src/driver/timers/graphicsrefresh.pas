{
    Driver->Timer->GraphicsRefresh - Timer-driven graphics refresh at ~120FPS.

    Hooks into the 1024Hz timer (TMR_0_ISR) and calls the desktop, uidebug,
    LVGL and video flush routines every ~9 ticks (1024/9 ≈ 113.8 FPS).

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit graphicsrefresh;

interface

procedure init;

implementation

uses
    util,
    TMR_0_ISR,
    desktop,
    uidebug,
    lvgl,
    video,
    windows,
    syslog;

const
    { 1024 / 4 ≈ 256 FPS }
    TICKS_PER_FRAME = 4;

var
    TickCounter : uint32;

procedure on_tick(data : void);
begin
    TickCounter := TickCounter + 1;
    if TickCounter >= TICKS_PER_FRAME then begin
        TickCounter := 0;
        windows.reapOrphanedWindows;
        desktop.update;
        uidebug.update;
        lvgl_handler;
        video.Flush;
    end;
end;

procedure init;
begin
    TickCounter := 0;
    TMR_0_ISR.hook(uint32(@on_tick));
    syslog.logln('GFXREFRESH', 'Hooked into 1024Hz timer (~120 FPS).');
end;

end.
