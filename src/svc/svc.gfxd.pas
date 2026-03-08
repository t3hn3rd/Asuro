{
    prog->GraphicsRefresh - Continuous graphics rendering process.

    Spawns a dedicated render process that loops indefinitely, driving the
    driver.video.desktop, LVGL and driver.video-flush pipeline.  The loop does real work every
    iteration (especially the 7.3 MB SSE framebuffer copy in driver.video.Flush),
    which keeps the vCPU active so the NEM/Hyper-V back-end never
    deschedules it and starves the PIT of interrupts.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit svc.gfxd;

interface

procedure init;

implementation

uses
    driver.video.desktop,
    app.uidebug,
    driver.video.lvgl,
    driver.video,
    driver.video.windows,
    proc.mgr,
    proc.types,
    io.syslog,
    arch.x86.isr.tmr0;

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
            driver.video.windows.reapOrphanedWindows;
            driver.video.desktop.update;
            app.uidebug.update;
            lvgl_handler;
            driver.video.Flush;
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
    arch.x86.isr.tmr0.hook(uint32(@tick));  { Register the tick handler to run on every timer interrupt }
    proc.mgr.create('gfxd', @render_loop, nil, 5);
    io.syslog.logln('gfxd', 'Render process spawned.');
end;

end.
