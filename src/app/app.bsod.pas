unit app.bsod;

interface

uses
    io.stdio,
    debug.tracer,
    core.panic;

procedure init;

implementation

procedure terminal_command_bsod(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    push_trace('kernel.terminal_command_bsod');

    if paramCount(params) > 1 then begin
      core.panic.panic(getparam(0, params), getparam(1, params), nil);
    end else begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Invalid number of params.');
        io.stdio.bufWriteStrLn(stderr_buf, 'Usage: bsod <error> <info>');
    end;

    pop_trace;
end;

procedure init;
begin
    io.stdio.registerCommand('BSOD', @terminal_command_bsod, 'Force a Panic Screen.');
end;

end.