{
    prog->GraphicsRefresh - Continuous graphics rendering process.

    Spawns a dedicated render process that loops indefinitely, driving the
    driver.video.desktop, LVGL and driver.video-flush pipeline.  The loop does real work every
    iteration. LVGL presents only completed frames; polling does not copy
    unchanged framebuffer contents.

    @author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit svc.gfxd;

interface

var
    SHOULD_CRASH : boolean;  { set to true to intentionally trigger a crash for testing purposes }
    

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
    core.clock,
    arch.platform.interrupts;

{ Render process entry point — runs as a normal scheduled process with
  interrupts enabled.  Continuously drives the full render pipeline so
  the vCPU is always executing real work (no HLT / PAUSE spin-waits
  that would trigger pause-loop exits under NEM/Hyper-V). }

const
    POLL_INTERVAL_US = 1000;
    FALLBACK_TICKS = 8;

var
    LAST_UPDATE : uint32 = 0;
    CURRENT_TICK : uint32 = 0;

procedure render_loop(ctx : PProcessContext);
var
    should_update : boolean;
    last_poll, now_us: uint64;

begin
    last_poll := 0;
    while true do begin
        if core.clock.ready then begin
            now_us := core.clock.nowUS;
            should_update := now_us - last_poll >= POLL_INTERVAL_US;
        end else
            should_update := (puint32(@CURRENT_TICK)^ - LAST_UPDATE) >= FALLBACK_TICKS;
        if (should_update) then begin
            if core.clock.ready then last_poll := now_us;
            LAST_UPDATE := puint32(@CURRENT_TICK)^;
            lvgl_lock;
            driver.video.windows.reapOrphanedWindows;
            driver.video.desktop.update;
            app.uidebug.update;
            lvgl_handler;
            lvgl_unlock;
        end;
        if SHOULD_CRASH then begin
            asm
                XOR EAX, EAX
                DIV EAX  { this will trigger a divide by zero exception (interrupt 0) }
            end;
        end;
    end;
end;

procedure tick(data: void);
begin
    { This function is called on every timer tick (interrupt 32) via the ISR hooks.
      It can be used to trigger periodic tasks without needing a dedicated process. }
    CURRENT_TICK := CURRENT_TICK + 1;
end;

procedure init;
begin
    arch.platform.interrupts.registerTimer(@tick);  { Register the tick handler to run on every timer interrupt }
    proc.mgr.create('gfxd', @render_loop, nil, 5);
    io.syslog.logln('gfxd', 'Render process spawned.');
end;

end.
