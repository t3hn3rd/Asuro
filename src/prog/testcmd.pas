{
    Prog->TestCmd - Test command that prints 5 lines with 1-second delays.

    Demonstrates a long-running command that writes incrementally to stdout.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit testcmd;

interface

uses
    stdio, processmanager, tracer;

procedure init();

implementation

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    i : uint32;
begin
    for i := 1 to 5 do begin
        case i of
            1: stdio.bufWriteStrLn(stdout_buf, 'Test output 1 of 5');
            2: stdio.bufWriteStrLn(stdout_buf, 'Test output 2 of 5');
            3: stdio.bufWriteStrLn(stdout_buf, 'Test output 3 of 5');
            4: stdio.bufWriteStrLn(stdout_buf, 'Test output 4 of 5');
            5: stdio.bufWriteStrLn(stdout_buf, 'Test output 5 of 5');
        end;
        if i < 5 then
            processmanager.proc_sleep_ms(1000);
    end;
end;

procedure init();
begin
    tracer.push_trace('testcmd.init');
    stdio.registerCommand('TEST', @run, 'Print 5 lines with 1-second delays.');
end;

end.
