{
    Prog->setres - Set display resolution via GPU driver framework.

    Usage: SETRES <width> <height>
    Example: SETRES 1024 768

    Uses the GPU driver framework to switch display modes. Tries BGA first,
    then falls back to VBE/VESA.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit setres;

interface

uses
    stdio, gpu, util, strings, tracer, syslog;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    w, h : uint32;
    wStr, hStr : pchar;
    info : TGPUModeInfo;

begin
    tracer.push_trace('setres.run');

    if paramCount(params) < 2 then begin
        stdio.bufWriteStrLn(stderr_buf, 'Usage: SETRES <width> <height>');
        stdio.bufWriteStrLn(stderr_buf, 'Example: SETRES 1024 768');
        tracer.pop_trace;
        exit;
    end;

    wStr := getParam(0, params);
    hStr := getParam(1, params);

    w := stringToInt(wStr);
    h := stringToInt(hStr);

    if (w = 0) or (h = 0) then begin
        stdio.bufWriteStrLn(stderr_buf, 'Error: Invalid resolution values.');
        tracer.pop_trace;
        exit;
    end;

    stdio.bufWriteStr(stdout_buf, 'Setting resolution to ');
    stdio.bufWriteInt(stdout_buf, w);
    stdio.bufWriteStr(stdout_buf, 'x');
    stdio.bufWriteInt(stdout_buf, h);
    stdio.bufWriteStrLn(stdout_buf, 'x32...');

    { Step 1: Set display mode via GPU framework (tries BGA first, then VBE) }
    if not gpu.setMode(w, h, 32, info) then begin
        stdio.bufWriteStrLn(stderr_buf, 'Error: Mode switch failed. Mode may not be supported.');
        tracer.pop_trace;
        exit;
    end;

    stdio.bufWriteStr(stdout_buf, 'Mode set via ');
    stdio.bufWriteStrLn(stdout_buf, gpu.activeDriverName());

    stdio.bufWriteStr(stdout_buf, 'Resolution set to ');
    stdio.bufWriteInt(stdout_buf, w);
    stdio.bufWriteStr(stdout_buf, 'x');
    stdio.bufWriteInt(stdout_buf, h);
    stdio.bufWriteStrLn(stdout_buf, 'x32 successfully.');

    tracer.pop_trace;
end;

procedure init();
begin
    tracer.push_trace('setres.init');
    stdio.registerCommand('SETRES', @Run, 'Set display resolution. Usage: SETRES <width> <height>');
    tracer.pop_trace;
end;

end.
