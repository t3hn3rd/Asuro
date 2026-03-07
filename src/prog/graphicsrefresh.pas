{
    prog->GraphicsRefresh - Continuous graphics rendering process.

    Spawns a dedicated render process that loops indefinitely, driving the
    desktop, LVGL and video-flush pipeline.  The loop does real work every
    iteration (especially the 7.3 MB SSE framebuffer copy in video.Flush),
    which keeps the vCPU active so the NEM/Hyper-V back-end never
    deschedules it and starves the PIT of interrupts.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit graphicsrefresh;

interface

procedure init;

implementation

uses
    desktop,
    uidebug,
    lvgl,
    video,
    windows,
    processmanager,
    proctypes,
    syslog,
    TMR_0_ISR;

{ Render process entry point — runs as a normal scheduled process with
  interrupts enabled.  Continuously drives the full render pipeline so
  the vCPU is always executing real work (no HLT / PAUSE spin-waits
  that would trigger pause-loop exits under NEM/Hyper-V). }

const
    TICKS_PER_FRAME = 32;  { target ticks per frame; adjust as needed to balance refresh rate and CPU usage }

var
    LAST_UPDATE : uint32 = 0;
    CURRENT_TICK : uint32 = 0;

procedure render_loop(ctx : PProcessContext);
var
    should_update : boolean;

begin
    while true do begin
        should_update := (CURRENT_TICK - LAST_UPDATE) >= TICKS_PER_FRAME;
        should_update := should_update or (CURRENT_TICK < LAST_UPDATE);  { handle tick counter wraparound }
        if (should_update) then begin
            LAST_UPDATE := CURRENT_TICK;
            windows.reapOrphanedWindows;
            desktop.update;
            uidebug.update;
            lvgl_handler;
            video.Flush;
        end;
    end;
end;

procedure tick;
begin
    { This function is called on every timer tick (interrupt 32) via the ISR hooks.
      It can be used to trigger periodic tasks without needing a dedicated process. }
    CURRENT_TICK := CURRENT_TICK + 1;
end;

procedure init;
begin
    TMR_0_ISR.hook(uint32(@tick));  { Register the tick handler to run on every timer interrupt }
    processmanager.create('gfxd', @render_loop, nil, 5);
    syslog.logln('gfxd', 'Render process spawned.');
end;

end.
