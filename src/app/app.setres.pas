{
    Prog->app.setres - Set display resolution via GPU driver framework.

    Usage: SETRES <width> <height>
    Example: SETRES 1024 768

    Uses the GPU driver framework to switch display modes. Tries BGA first,
    then falls back to VBE/VESA.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.setres;

interface

uses
    io.stdio, driver.video.gpu, core.util, arch.x86.util, core.strings, debug.tracer, io.syslog;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    w, h : uint32;
    wStr, hStr : pchar;
    info : TGPUModeInfo;

begin
    debug.tracer.push_trace('setres.run');

    if paramCount(params) < 2 then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Usage: SETRES <width> <height>');
        io.stdio.bufWriteStrLn(stderr_buf, 'Example: SETRES 1024 768');
        debug.tracer.pop_trace;
        exit;
    end;

    wStr := getParam(0, params);
    hStr := getParam(1, params);

    w := stringToInt(wStr);
    h := stringToInt(hStr);

    if (w = 0) or (h = 0) then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Error: Invalid resolution values.');
        debug.tracer.pop_trace;
        exit;
    end;

    io.stdio.bufWriteStr(stdout_buf, 'Setting resolution to ');
    io.stdio.bufWriteInt(stdout_buf, w);
    io.stdio.bufWriteStr(stdout_buf, 'x');
    io.stdio.bufWriteInt(stdout_buf, h);
    io.stdio.bufWriteStrLn(stdout_buf, 'x32...');

    { Step 1: Set display mode via GPU framework (tries BGA first, then VBE) }
    if not driver.video.gpu.setMode(w, h, 32, info) then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Error: Mode switch failed. Mode may not be supported.');
        debug.tracer.pop_trace;
        exit;
    end;

    io.stdio.bufWriteStr(stdout_buf, 'Mode set via ');
    io.stdio.bufWriteStrLn(stdout_buf, driver.video.gpu.activeDriverName());

    io.stdio.bufWriteStr(stdout_buf, 'Resolution set to ');
    io.stdio.bufWriteInt(stdout_buf, w);
    io.stdio.bufWriteStr(stdout_buf, 'x');
    io.stdio.bufWriteInt(stdout_buf, h);
    io.stdio.bufWriteStrLn(stdout_buf, 'x32 successfully.');

    debug.tracer.pop_trace;
end;

procedure init();
begin
    debug.tracer.push_trace('setres.init');
    io.stdio.registerCommand('SETRES', @Run, 'Set display resolution. Usage: SETRES <width> <height>');
    debug.tracer.pop_trace;
end;

end.
