unit app.bsod;
{$DEFINE NOT_DANGLING} { Registered by each x86 startup. }

interface

uses
    io.stdio,
    debug.tracer;

procedure init;

implementation

uses arch.platform.diagnostics;

procedure terminal_command_bsod(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    push_trace('kernel.terminal_command_bsod');

    if paramCount(params) > 1 then begin
      arch.platform.diagnostics.fatal(getparam(0, params), getparam(1, params));
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