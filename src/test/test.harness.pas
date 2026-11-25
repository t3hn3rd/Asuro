unit test.harness;

interface

type
    THarnessContext = record
        UnitsSuccess: uint32;
        UnitsFailed:  uint32;
        UnitsTotal:   uint32;
        TestsRun:     uint32;
        TestsFailed:  uint32;
        TestsTotal:   uint32;
    end;
    PHarnessContext = ^THarnessContext;

    TTestContext = record
        UnitName:     pchar;
        UnitPrefix:   pchar;
        Failed:       boolean;
        FailedCount:  uint32;
        SuccessCount: uint32;
        TotalCount:   uint32;
    end;
    PTestContext = ^TTestContext;

procedure Start(TestContext: PTestContext; UnitName: pchar);
procedure Assert(TestContext: PTestContext; condition : boolean; testName : pchar);
procedure Finish(TestContext: PTestContext);
procedure Print;
procedure Init;

implementation

uses
    core.strings, memory.heap, io.syslog, arch.platform.cpu;

var
    HarnessContext: THarnessContext;

{ Keep serial test records intact when a driver logs from an interrupt. }
procedure writeResult(tag, message: pchar);
var
    flags: PtrUInt;
begin
    flags := arch.platform.cpu.lock;
    io.syslog.logln(tag, message);
    arch.platform.cpu.unlock(flags);
end;

procedure Start(TestContext: PTestContext; UnitName: pchar);
begin
    TestContext^.UnitName:= UnitName;
    TestContext^.UnitPrefix:= stringConcat('test:', UnitName);
    TestContext^.Failed:= false;
    TestContext^.FailedCount:= 0;
    TestContext^.SuccessCount:= 0;
    TestContext^.TotalCount:= 0;
    inc(HarnessContext.UnitsTotal);
    writeResult(TestContext^.UnitPrefix, 'Unit tests starting...');
end;

procedure Assert(TestContext: PTestContext; condition : boolean; testName : pchar);
var
    msg : pchar;

begin
    inc(HarnessContext.TestsRun);
    if condition then begin
        inc(TestContext^.SuccessCount);
        inc(TestContext^.TotalCount);
    end else begin
        inc(TestContext^.FailedCount);
        inc(TestContext^.TotalCount);
        inc(HarnessContext.TestsFailed);
        msg:= stringConcat('FAIL: ', testName);
        writeResult(TestContext^.UnitPrefix, msg);
        kfree(void(msg));
    end;
end;

procedure Summary(TestContext: PTestContext);
var
    pStr, fStr, msg, tmp : pchar;

begin
    pStr:= intToString(TestContext^.SuccessCount);
    fStr:= intToString(TestContext^.FailedCount);
    msg:= stringConcat(pStr, ' passed, ');
    tmp:= stringConcat(msg, fStr);
    kfree(void(msg));
    msg:= stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    writeResult(TestContext^.UnitPrefix, msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));
end;

procedure Finish(TestContext: PTestContext);
begin
    Summary(TestContext);
    kfree(void(TestContext^.UnitPrefix));
    TestContext^.UnitPrefix := nil;
    if TestContext^.FailedCount > 0 then
        inc(HarnessContext.UnitsFailed)
    else
        inc(HarnessContext.UnitsSuccess);
end;

procedure Init;
begin
    // Initialize the test harness here if needed
    HarnessContext.UnitsSuccess:= 0;
    HarnessContext.UnitsFailed:= 0;
    HarnessContext.UnitsTotal:= 0;
    HarnessContext.TestsRun:= 0;
    HarnessContext.TestsFailed:= 0;
    HarnessContext.TestsTotal:= 0;
end;

procedure Print;
var
    tStr, pStr, fStr, msg, tmp : pchar;

begin
    tStr:= intToString(HarnessContext.UnitsTotal);
    pStr:= intToString(HarnessContext.UnitsSuccess);
    fStr:= intToString(HarnessContext.UnitsFailed);
    msg:= stringConcat(tStr, ' units tested, ');
    kfree(void(tStr));
    tmp:= stringConcat(msg, pStr);
    kfree(void(msg));
    msg:= stringConcat(tmp, ' passed, ');
    kfree(void(tmp));
    tmp:= stringConcat(msg, fStr);
    kfree(void(msg));
    msg:= stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    writeResult('test', msg);
    kfree(void(msg));
    kfree(void(pStr));
    kfree(void(fStr));

    tStr:= intToString(HarnessContext.TestsRun);
    pStr:= intToString(HarnessContext.TestsRun - HarnessContext.TestsFailed);
    fStr:= intToString(HarnessContext.TestsFailed);
    msg:= stringConcat(tStr, ' tests run, ');
    tmp:= stringConcat(msg, pStr);
    kfree(void(msg));
    msg:= stringConcat(tmp, ' passed, ');
    kfree(void(tmp));
    tmp:= stringConcat(msg, fStr);
    kfree(void(msg));
    msg:= stringConcat(tmp, ' failed.');
    kfree(void(tmp));
    writeResult('test', msg);
    kfree(void(msg));
    kfree(void(tStr));
    kfree(void(pStr));
    kfree(void(fStr));
end;

end.
