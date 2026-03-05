{
    Prog->VTerminal - LVGL-based Visual Terminal Emulator.

    Multi-instance design: each launch allocates a TVTermState record
    on the heap.  All callbacks retrieve their state via LVGL
    user_data, so multiple terminals can coexist independently.

    Commands are executed as preemptive processes via
    processmanager.runCommand.  A per-instance LVGL timer polls the
    foreground process for incremental output.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit vterminal;

interface

uses
    lvgl, video, windows, desktop, keyboard, tracer,
    strings, util, lmemorymanager, asuro, stdio, vfs,
    processmanager, proctypes, lists, hashmap, filedispatch;

procedure init;

implementation

const
    TERM_W        = 640;
    TERM_H        = 400;
    MAX_TEXT      = 4096;   { max chars in scrollback buffer }
    MAX_LINE      = 1024;   { max input line length, matches TCommandBuffer }
    HIST_SIZE     = 10;     { number of history entries }
    DRAIN_PERIOD  = 100;    { ms between output-drain polls }

type
    PBackgroundJob = ^TBackgroundJob;
    TBackgroundJob = record
        PID        : uint32;
        JobNum     : uint32;
        CmdName    : array[0..31] of char;
        StdOut     : POutBuf;
        StdErr     : POutBuf;
        LastDrain  : uint32;
        LastDrainE : uint32;
    end;

    PVTermState = ^TVTermState;
    TVTermState = record
        { LVGL widgets }
        win_id       : uint32;
        content      : Plv_obj;
        text_label   : Plv_obj;
        focused      : boolean;
        drain_timer  : Plv_timer;

        { Scrollback text buffer }
        text_buf     : array[0..MAX_TEXT-1] of char;
        text_len     : uint32;

        { Current input line }
        line_buf     : TCommandBuffer;
        line_len     : uint32;

        { Command history ring }
        hist         : array[0..HIST_SIZE-1] of TCommandBuffer;
        hist_count   : uint32;
        hist_head    : uint32;
        hist_pos     : sint32;
        saved_line   : TCommandBuffer;
        saved_len    : uint32;

        { Foreground process integration }
        ForegroundPID  : uint32;
        fg_stdout      : POutBuf;
        fg_stderr      : POutBuf;
        fg_stdin       : POutBuf;
        last_drain     : uint32;
        last_drain_err : uint32;
        fg_params      : PParamList;

        { Terminal process }
        TerminalPID    : uint32;

        { Per-terminal working directory }
        cwd            : pchar;
        dir_stack      : PLinkedListBase;

        { Background jobs }
        bg_jobs        : PDList;
        bg_next_job    : uint32;
    end;

{ ============================================================
  terminal_entry — process entry point for the terminal itself
  Loops yielding until terminated.  This makes each terminal
  visible in PS and manageable via KILL/TERMINATE.
  ============================================================ }
procedure terminal_entry(ctx : PProcessContext);
begin
    while (ctx^.State <> psFinished) and (ctx^.PendingMsg <> smKill) and (ctx^.PendingMsg <> smTerminate) do
        processmanager.proc_yield;
end;

{ ============================================================
  Internal helpers — all take state explicitly
  ============================================================ }

procedure appendText(state : PVTermState; s: pchar);
var
    slen, i: uint32;
begin
    if s = nil then exit;
    slen := stringSize(s);
    if slen = 0 then exit;
    if state^.text_len + slen >= MAX_TEXT - 1 then begin
        i := MAX_TEXT div 2;
        memcpy(uint32(@state^.text_buf[i]), uint32(@state^.text_buf[0]), state^.text_len - i);
        state^.text_len := state^.text_len - i;
    end;
    memcpy(uint32(s), uint32(@state^.text_buf[state^.text_len]), slen);
    state^.text_len := state^.text_len + slen;
    state^.text_buf[state^.text_len] := #0;
end;

procedure appendChar(state : PVTermState; c: char);
var
    tmp: array[0..1] of char;
begin
    tmp[0] := c;
    tmp[1] := #0;
    appendText(state, @tmp[0]);
end;

procedure refreshDisplay(state : PVTermState);
var
    sb: sint32;
begin
    if (state^.text_label <> nil) and (state^.content <> nil) then begin
        lv_label_set_text(state^.text_label, @state^.text_buf[0]);
        lv_obj_update_layout(lv_screen_active);
        sb := lv_obj_get_scroll_bottom(state^.content);
        if sb > 0 then
            lv_obj_scroll_by(state^.content, 0, -sb, LV_ANIM_OFF);
    end;
end;

procedure showPrompt(state : PVTermState);
begin
    appendText(state, 'asuro:');
    if state^.cwd <> nil then
        appendText(state, state^.cwd)
    else
        appendText(state, '/');
    appendText(state, '> ');
    refreshDisplay(state);
end;

{ ============================================================
  drainOutput — called from per-instance LVGL timer
  Pulls new content from the foreground process's stdout/stderr
  into the scrollback, and cleans up when the process finishes.
  ============================================================ }
procedure drainOutput(state : PVTermState);
var
    ctx : PProcessContext;
    finished : boolean;
    dirty : boolean;
begin
    if state^.ForegroundPID = 0 then exit;
    ctx := processmanager.findByID(state^.ForegroundPID);
    dirty := false;

    { Drain any new stdout since last check }
    if (state^.fg_stdout <> nil) and (state^.fg_stdout^.len > state^.last_drain) then begin
        state^.fg_stdout^.buf[state^.fg_stdout^.len] := #0;
        appendText(state, @state^.fg_stdout^.buf[state^.last_drain]);
        state^.last_drain := state^.fg_stdout^.len;
        dirty := true;
    end;

    { Drain any new stderr }
    if (state^.fg_stderr <> nil) and (state^.fg_stderr^.len > state^.last_drain_err) then begin
        state^.fg_stderr^.buf[state^.fg_stderr^.len] := #0;
        appendText(state, @state^.fg_stderr^.buf[state^.last_drain_err]);
        state^.last_drain_err := state^.fg_stderr^.len;
        dirty := true;
    end;

    { Check if process is done }
    finished := (ctx = nil) or (ctx^.State = psFinished) or (ctx^.State = psError);
    if finished then begin
        if state^.fg_stdout <> nil then begin
            stdio.freeOutBuf(state^.fg_stdout);
            state^.fg_stdout := nil;
        end;
        if state^.fg_stderr <> nil then begin
            stdio.freeOutBuf(state^.fg_stderr);
            state^.fg_stderr := nil;
        end;
        if state^.fg_stdin <> nil then begin
            stdio.freeOutBuf(state^.fg_stdin);
            state^.fg_stdin := nil;
        end;
        if state^.fg_params <> nil then begin
            stdio.freeParams(state^.fg_params);
            state^.fg_params := nil;
        end;
        state^.ForegroundPID := 0;
        state^.last_drain := 0;
        state^.last_drain_err := 0;
        showPrompt(state);
        exit; { showPrompt already refreshes }
    end;

    if dirty then
        refreshDisplay(state);
end;

{ ============================================================
  drainBackgroundJobs — check background jobs for output and
  reap finished ones.
  ============================================================ }
procedure drainBackgroundJobs(state : PVTermState);
var
    i       : sint32;
    slotPtr : ^uint32;
    job     : PBackgroundJob;
    ctx     : PProcessContext;
    finished: boolean;
    dirty   : boolean;
    ns      : pchar;
begin
    if state^.bg_jobs = nil then exit;
    dirty := false;
    for i := sint32(DL_Size(state^.bg_jobs)) - 1 downto 0 do begin
        slotPtr := DL_Get(state^.bg_jobs, uint32(i));
        if slotPtr = nil then continue;
        job := PBackgroundJob(slotPtr^);
        if job = nil then continue;
        ctx := processmanager.findByID(job^.PID);
        finished := (ctx = nil) or (ctx^.State = psFinished) or (ctx^.State = psError);
        if finished then begin
            { Drain final output }
            if (job^.StdOut <> nil) and (job^.StdOut^.len > job^.LastDrain) then begin
                job^.StdOut^.buf[job^.StdOut^.len] := #0;
                appendText(state, @job^.StdOut^.buf[job^.LastDrain]);
                dirty := true;
            end;
            if (job^.StdErr <> nil) and (job^.StdErr^.len > job^.LastDrainE) then begin
                job^.StdErr^.buf[job^.StdErr^.len] := #0;
                appendText(state, @job^.StdErr^.buf[job^.LastDrainE]);
                dirty := true;
            end;
            { Notify user }
            appendChar(state, #10);
            appendText(state, '[');
            ns := intToString(job^.JobNum);
            appendText(state, ns);
            kfree(void(ns));
            appendText(state, ']  Done  ');
            appendText(state, @job^.CmdName[0]);
            appendChar(state, #10);
            dirty := true;
            { Free I/O buffers }
            if job^.StdOut <> nil then stdio.freeOutBuf(job^.StdOut);
            if job^.StdErr <> nil then stdio.freeOutBuf(job^.StdErr);
            kfree(void(job));
            DL_Delete(state^.bg_jobs, uint32(i));
        end;
    end;
    if dirty then
        refreshDisplay(state);
end;

{ LVGL timer callback wrapper }
procedure drain_timer_cb(timer: Plv_timer); cdecl;
var
    state : PVTermState;
begin
    state := PVTermState(lv_timer_get_user_data(timer));
    if state <> nil then begin
        drainOutput(state);
        drainBackgroundJobs(state);
    end;
end;

{ ============================================================
  killForeground — terminate the running foreground process
  and clean up its I/O state (called by Ctrl+C handler).
  ============================================================ }
procedure killForeground(state : PVTermState);
var
    ctx : PProcessContext;
begin
    if state^.ForegroundPID = 0 then exit;
    ctx := processmanager.findByID(state^.ForegroundPID);
    if ctx <> nil then
        processmanager.kill(state^.ForegroundPID);
    { Drain any final output before freeing buffers }
    drainOutput(state);
    { If drainOutput didn’t already clean up (process may not be reaped yet) }
    if state^.fg_stdout <> nil then begin stdio.freeOutBuf(state^.fg_stdout); state^.fg_stdout := nil; end;
    if state^.fg_stderr <> nil then begin stdio.freeOutBuf(state^.fg_stderr); state^.fg_stderr := nil; end;
    if state^.fg_stdin  <> nil then begin stdio.freeOutBuf(state^.fg_stdin);  state^.fg_stdin  := nil; end;
    if state^.fg_params <> nil then begin stdio.freeParams(state^.fg_params); state^.fg_params := nil; end;
    state^.ForegroundPID := 0;
    state^.last_drain := 0;
    state^.last_drain_err := 0;
    appendChar(state, #10);
    appendText(state, '^C');
    appendChar(state, #10);
    showPrompt(state);
    { Clear any partial input line }
    state^.line_len := 0;
    memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
end;

{ ============================================================
  Per-terminal filesystem builtins
  ============================================================ }
procedure builtin_cd(state : PVTermState; params : PParamList);
var
    Path      : pchar;
    Temp1     : pchar;
    Temp2     : pchar;
    NewDir    : pchar;
    Validity  : TIsPathValid;
    i         : uint32;
begin
    if ParamCount(params) < 1 then exit;
    { Reconstruct the path argument (may contain spaces) }
    for i := 0 to ParamCount(params) - 1 do begin
        if i = 0 then begin
            Temp1 := StringCopy(GetParam(i, params));
            Path := StringCopy(Temp1);
            kfree(void(Temp1));
        end else begin
            Temp1 := StringConcat(' ', GetParam(i, params));
            Temp2 := StringConcat(Path, Temp1);
            kfree(void(Temp1));
            kfree(void(Path));
            Path := Temp2;
        end;
    end;
    { Resolve relative to per-terminal cwd }
    Validity := vfs.changeDirectoryFrom(Path, state^.cwd, NewDir);
    case Validity of
        pvDirectory: begin
            kfree(void(state^.cwd));
            state^.cwd := NewDir;
        end;
        pvFile: begin
            appendText(state, '"');
            appendText(state, Path);
            appendText(state, '" is not a directory.');
            appendChar(state, #10);
        end;
        pvInvalid: begin
            appendText(state, '"');
            appendText(state, Path);
            appendText(state, '" is not a valid path.');
            appendChar(state, #10);
        end;
    end;
    kfree(void(Path));
end;

procedure builtin_ls(state : PVTermState; params : PParamList);
var
    Map  : PHashMap;
    Item : PHashItem;
    i    : uint32;
begin
    Map := vfs.GetDirectoryListingFrom('.', state^.cwd);
    if Map <> nil then begin
        for i := 0 to Map^.Size - 1 do begin
            Item := Map^.Table[i];
            while Item <> nil do begin
                appendText(state, ' ');
                appendText(state, Item^.Key);
                appendChar(state, #10);
                Item := Item^.Next;
            end;
        end;
    end else begin
        appendText(state, 'An internal error occured!');
        appendChar(state, #10);
    end;
end;

procedure builtin_pushd(state : PVTermState; params : PParamList);
var
    wd     : pchar;
    Output : pchar;
begin
    wd := StringCopy(state^.cwd);
    STRLL_Add(state^.dir_stack, wd);
    Output := StringConcat(wd, ' saved to stack.');
    appendText(state, Output);
    appendChar(state, #10);
    kfree(void(Output));
end;

procedure builtin_popd(state : PVTermState; params : PParamList);
var
    wd        : pchar;
    Output    : pchar;
    NewDir    : pchar;
    Validity  : TIsPathValid;
begin
    if STRLL_Size(state^.dir_stack) > 0 then begin
        wd := STRLL_Get(state^.dir_stack, STRLL_Size(state^.dir_stack) - 1);
        Validity := vfs.changeDirectoryFrom(wd, state^.cwd, NewDir);
        if Validity = pvDirectory then begin
            kfree(void(state^.cwd));
            state^.cwd := NewDir;
            Output := StringConcat(wd, ' popped from the stack.');
            appendText(state, Output);
            appendChar(state, #10);
            kfree(void(Output));
        end else begin
            Output := StringConcat(wd, ' popped, but was invalid!');
            appendText(state, Output);
            appendChar(state, #10);
            kfree(void(Output));
        end;
        STRLL_Delete(state^.dir_stack, STRLL_Size(state^.dir_stack) - 1);
    end else begin
        appendText(state, 'No working directory in the stack!');
        appendChar(state, #10);
    end;
end;

{ ============================================================
  processCommand — execute the current input line
  ============================================================ }
procedure processCommand(state : PVTermState);
var
    params     : PParamList;
    uppera     : pchar;
    cmd        : PCommand;
    ctx        : PProcessContext;
    is_bg      : boolean;
    pcount     : uint32;
    lastParam  : pchar;
    job        : PBackgroundJob;
    slotPtr    : ^uint32;
    absPath    : pchar;
    dispatchPID : uint32;
begin
    { Null-terminate input }
    state^.line_buf[state^.line_len] := 0;

    { Echo the entered line }
    appendChar(state, #10);

    { Push non-empty lines into history }
    if state^.line_len > 0 then begin
        memcpy(uint32(@state^.line_buf[0]),
               uint32(@state^.hist[state^.hist_head][0]),
               state^.line_len + 1);
        state^.hist_head := (state^.hist_head + 1) mod HIST_SIZE;
        if state^.hist_count < HIST_SIZE then inc(state^.hist_count);
    end;
    state^.hist_pos := -1;

    if state^.line_len = 0 then begin
        showPrompt(state);
        state^.line_len := 0;
        memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
        exit;
    end;

    { Parse parameters }
    params := stdio.getParams(state^.line_buf);

    if (params <> nil) and (params^.Param <> nil) then begin
        uppera := stringToUpper(params^.Param);

        { CLEAR handled locally }
        if stringEquals(uppera, 'CLEAR') then begin
            state^.text_len := 0;
            state^.text_buf[0] := #0;
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
            exit;
        end;

        { Filesystem builtins — per-terminal CWD }
        if stringEquals(uppera, 'CD') then begin
            builtin_cd(state, params);
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
            exit;
        end;
        if stringEquals(uppera, 'LS') then begin
            builtin_ls(state, params);
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
            exit;
        end;
        if stringEquals(uppera, 'PUSHD') then begin
            builtin_pushd(state, params);
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
            exit;
        end;
        if stringEquals(uppera, 'POPD') then begin
            builtin_popd(state, params);
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
            exit;
        end;

        { JOBS — list background jobs }
        if stringEquals(uppera, 'JOBS') then begin
            if (state^.bg_jobs <> nil) and (DL_Size(state^.bg_jobs) > 0) then begin
                for pcount := 0 to DL_Size(state^.bg_jobs) - 1 do begin
                    slotPtr := DL_Get(state^.bg_jobs, pcount);
                    if (slotPtr <> nil) then begin
                        job := PBackgroundJob(slotPtr^);
                        if job <> nil then begin
                            appendText(state, '[');
                            lastParam := intToString(job^.JobNum);
                            appendText(state, lastParam);
                            kfree(void(lastParam));
                            appendText(state, ']  ');
                            ctx := processmanager.findByID(job^.PID);
                            if ctx <> nil then begin
                                case ctx^.State of
                                    psRunning:   appendText(state, 'Running   ');
                                    psReady:     appendText(state, 'Running   ');
                                    psSuspended: appendText(state, 'Stopped   ');
                                    psAwaiting:  appendText(state, 'Waiting   ');
                                else
                                    appendText(state, 'Done      ');
                                end;
                            end else
                                appendText(state, 'Done      ');
                            appendText(state, @job^.CmdName[0]);
                            appendChar(state, #10);
                        end;
                    end;
                end;
            end else begin
                appendText(state, 'No background jobs.');
                appendChar(state, #10);
            end;
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
            exit;
        end;

        { FG — bring a background job to foreground }
        if stringEquals(uppera, 'FG') then begin
            if (state^.bg_jobs <> nil) and (DL_Size(state^.bg_jobs) > 0) then begin
                { Use first bg job if no arg given }
                slotPtr := DL_Get(state^.bg_jobs, 0);
                if (slotPtr <> nil) then begin
                    job := PBackgroundJob(slotPtr^);
                    if job <> nil then begin
                        { Transfer to foreground }
                        state^.ForegroundPID := job^.PID;
                        state^.fg_stdout := job^.StdOut;
                        state^.fg_stderr := job^.StdErr;
                        state^.fg_stdin := nil;
                        state^.last_drain := job^.LastDrain;
                        state^.last_drain_err := job^.LastDrainE;
                        state^.fg_params := nil;
                        appendText(state, @job^.CmdName[0]);
                        appendChar(state, #10);
                        { Remove from bg_jobs without freeing I/O (now owned by fg) }
                        kfree(void(job));
                        DL_Delete(state^.bg_jobs, 0);
                    end;
                end;
            end else begin
                appendText(state, 'No background jobs.');
                appendChar(state, #10);
                showPrompt(state);
            end;
            kfree(void(uppera));
            stdio.freeParams(params);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            exit;
        end;

        { Check for trailing & (background launch) }
        is_bg := false;
        pcount := stdio.paramCount(params);
        if pcount > 0 then begin
            lastParam := stdio.getParam(pcount - 1, params);
            if (lastParam <> nil) and (lastParam[0] = '&') and (lastParam[1] = #0) then
                is_bg := true;
        end;

        cmd := stdio.findCommand(uppera);
        kfree(void(uppera));

        if cmd <> nil then begin
            if is_bg then begin
                { --- Background launch --- }
                job := PBackgroundJob(kalloc(SizeOf(TBackgroundJob)));
                if job <> nil then begin
                    memset(uint32(job), 0, SizeOf(TBackgroundJob));
                    job^.StdOut := stdio.createOutBuf(1024);
                    job^.StdErr := stdio.createOutBuf(1024);
                    job^.LastDrain := 0;
                    job^.LastDrainE := 0;
                    inc(state^.bg_next_job);
                    job^.JobNum := state^.bg_next_job;

                    { Copy command name }
                    pcount := stringSize(params^.Param);
                    if pcount > 31 then pcount := 31;
                    memcpy(uint32(params^.Param), uint32(@job^.CmdName[0]), pcount);
                    job^.CmdName[pcount] := #0;

                    { Launch but don't set ForegroundPID }
                    ctx := processmanager.runCommand(
                        params^.Param, cmd^.method, params,
                        nil, job^.StdOut, job^.StdErr
                    );

                    if ctx <> nil then begin
                        job^.PID := ctx^.ProcessID;
                        if state^.bg_jobs = nil then
                            state^.bg_jobs := DL_New(SizeOf(uint32));
                        slotPtr := DL_Add(state^.bg_jobs);
                        slotPtr^ := uint32(job);
                        appendText(state, '[');
                        lastParam := intToString(job^.JobNum);
                        appendText(state, lastParam);
                        kfree(void(lastParam));
                        appendText(state, '] ');
                        lastParam := intToString(job^.PID);
                        appendText(state, lastParam);
                        kfree(void(lastParam));
                        appendChar(state, #10);
                    end else begin
                        appendText(state, 'Error: failed to create process.');
                        appendChar(state, #10);
                        stdio.freeOutBuf(job^.StdOut);
                        stdio.freeOutBuf(job^.StdErr);
                        kfree(void(job));
                    end;
                end;
                stdio.freeParams(params);
                showPrompt(state);
            end else begin
                { --- Foreground launch --- }
                state^.fg_stdout := stdio.createOutBuf(1024);
                state^.fg_stderr := stdio.createOutBuf(1024);
                state^.fg_stdin  := stdio.createOutBuf(0);
                state^.last_drain := 0;
                state^.last_drain_err := 0;
                state^.fg_params := params;

                ctx := processmanager.runCommand(
                    params^.Param, cmd^.method, params,
                    state^.fg_stdin, state^.fg_stdout, state^.fg_stderr
                );

                if ctx <> nil then begin
                    state^.ForegroundPID := ctx^.ProcessID;
                end else begin
                    appendText(state, 'Error: failed to create process.');
                    appendChar(state, #10);
                    stdio.freeOutBuf(state^.fg_stdout);  state^.fg_stdout := nil;
                    stdio.freeOutBuf(state^.fg_stderr);  state^.fg_stderr := nil;
                    stdio.freeOutBuf(state^.fg_stdin);   state^.fg_stdin := nil;
                    stdio.freeParams(params);
                    state^.fg_params := nil;
                    state^.ForegroundPID := 0;
                    showPrompt(state);
                end;
            end;
        end else begin
            { No built-in command found — try file dispatch }
            absPath := vfs.makeAbsolutePathFrom(params^.Param, state^.cwd);
            if absPath <> nil then begin
                if is_bg then begin
                    { Background file dispatch }
                    job := PBackgroundJob(kalloc(SizeOf(TBackgroundJob)));
                    if job <> nil then begin
                        memset(uint32(job), 0, SizeOf(TBackgroundJob));
                        job^.StdOut := stdio.createOutBuf(1024);
                        job^.StdErr := stdio.createOutBuf(1024);
                        job^.LastDrain := 0;
                        job^.LastDrainE := 0;
                        inc(state^.bg_next_job);
                        job^.JobNum := state^.bg_next_job;
                        pcount := stringSize(params^.Param);
                        if pcount > 31 then pcount := 31;
                        memcpy(uint32(params^.Param), uint32(@job^.CmdName[0]), pcount);
                        job^.CmdName[pcount] := #0;

                        dispatchPID := filedispatch.dispatch(absPath, params,
                                                             nil, job^.StdOut, job^.StdErr);
                        if dispatchPID > 0 then begin
                            job^.PID := dispatchPID;
                            if state^.bg_jobs = nil then
                                state^.bg_jobs := DL_New(SizeOf(uint32));
                            slotPtr := DL_Add(state^.bg_jobs);
                            slotPtr^ := uint32(job);
                            appendText(state, '[');
                            lastParam := intToString(job^.JobNum);
                            appendText(state, lastParam);
                            kfree(void(lastParam));
                            appendText(state, '] ');
                            lastParam := intToString(job^.PID);
                            appendText(state, lastParam);
                            kfree(void(lastParam));
                            appendChar(state, #10);
                        end else begin
                            appendText(state, 'Unknown command. Type HELP for a list.');
                            appendChar(state, #10);
                            stdio.freeOutBuf(job^.StdOut);
                            stdio.freeOutBuf(job^.StdErr);
                            kfree(void(job));
                        end;
                    end;
                    kfree(void(absPath));
                    stdio.freeParams(params);
                    showPrompt(state);
                end else begin
                    { Foreground file dispatch }
                    state^.fg_stdout := stdio.createOutBuf(1024);
                    state^.fg_stderr := stdio.createOutBuf(1024);
                    state^.fg_stdin  := stdio.createOutBuf(0);
                    state^.last_drain := 0;
                    state^.last_drain_err := 0;
                    state^.fg_params := params;

                    dispatchPID := filedispatch.dispatch(absPath, params,
                                                         state^.fg_stdin, state^.fg_stdout, state^.fg_stderr);
                    kfree(void(absPath));

                    if dispatchPID > 0 then begin
                        state^.ForegroundPID := dispatchPID;
                    end else begin
                        appendText(state, 'Unknown command. Type HELP for a list.');
                        appendChar(state, #10);
                        stdio.freeOutBuf(state^.fg_stdout);  state^.fg_stdout := nil;
                        stdio.freeOutBuf(state^.fg_stderr);  state^.fg_stderr := nil;
                        stdio.freeOutBuf(state^.fg_stdin);   state^.fg_stdin := nil;
                        stdio.freeParams(params);
                        state^.fg_params := nil;
                        state^.ForegroundPID := 0;
                        showPrompt(state);
                    end;
                end;
            end else begin
                appendText(state, 'Unknown command. Type HELP for a list.');
                appendChar(state, #10);
                stdio.freeParams(params);
                showPrompt(state);
            end;
        end;
    end else begin
        if params <> nil then stdio.freeParams(params);
        showPrompt(state);
    end;

    { Reset input line }
    state^.line_len := 0;
    memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
end;

{ ============================================================
  LVGL event callbacks — retrieve state from user_data
  ============================================================ }

procedure content_click_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PVTermState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PVTermState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.content = nil then exit;

    if not state^.focused then begin
        state^.focused := true;
        lv_group_add_obj(lvgl_get_kb_group, state^.content);
        lv_group_focus_obj(state^.content);
    end;
end;

procedure content_key_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    key   : uint32;
    state : PVTermState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_KEY then exit;
    state := PVTermState(lv_event_get_user_data(e));
    if state = nil then exit;

    key := lv_event_get_key(e);

    { Ctrl+C — kill foreground process regardless of state }
    if key = LV_KEY_CTRLC then begin
        if state^.ForegroundPID <> 0 then
            killForeground(state)
        else begin
            { No foreground process — just print ^C and new prompt }
            appendChar(state, #10);
            appendText(state, '^C');
            appendChar(state, #10);
            state^.line_len := 0;
            memset(uint32(@state^.line_buf[0]), 0, MAX_LINE);
            showPrompt(state);
        end;
        exit;
    end;

    { Block input while a foreground process is running }
    if state^.ForegroundPID <> 0 then exit;

    if key = LV_KEY_ENTER then begin
        processCommand(state);
        exit;
    end;

    { Up arrow — browse history backward (older) }
    if key = LV_KEY_UP then begin
        if state^.hist_count > 0 then begin
            if state^.hist_pos = -1 then begin
                memcpy(uint32(@state^.line_buf[0]),
                       uint32(@state^.saved_line[0]),
                       state^.line_len + 1);
                state^.saved_len := state^.line_len;
                state^.hist_pos := 0;
            end else if uint32(state^.hist_pos) < state^.hist_count - 1 then
                inc(state^.hist_pos)
            else
                exit;
            if state^.text_len >= state^.line_len then
                state^.text_len := state^.text_len - state^.line_len;
            state^.text_buf[state^.text_len] := #0;
            state^.line_len := stringSize(
                @state^.hist[(sint32(state^.hist_head) - 1 - state^.hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]);
            memcpy(uint32(@state^.hist[(sint32(state^.hist_head) - 1 - state^.hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]),
                   uint32(@state^.line_buf[0]),
                   state^.line_len + 1);
            appendText(state, @state^.line_buf[0]);
            refreshDisplay(state);
        end;
        exit;
    end;

    { Down arrow — browse history forward (newer) }
    if key = LV_KEY_DOWN then begin
        if state^.hist_pos >= 0 then begin
            if state^.text_len >= state^.line_len then
                state^.text_len := state^.text_len - state^.line_len;
            state^.text_buf[state^.text_len] := #0;
            dec(state^.hist_pos);
            if state^.hist_pos >= 0 then begin
                state^.line_len := stringSize(
                    @state^.hist[(sint32(state^.hist_head) - 1 - state^.hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]);
                memcpy(uint32(@state^.hist[(sint32(state^.hist_head) - 1 - state^.hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]),
                       uint32(@state^.line_buf[0]),
                       state^.line_len + 1);
            end else begin
                memcpy(uint32(@state^.saved_line[0]),
                       uint32(@state^.line_buf[0]),
                       state^.saved_len + 1);
                state^.line_len := state^.saved_len;
            end;
            appendText(state, @state^.line_buf[0]);
            refreshDisplay(state);
        end;
        exit;
    end;

    if key = LV_KEY_BACKSPACE then begin
        if state^.line_len > 0 then begin
            dec(state^.line_len);
            state^.line_buf[state^.line_len] := 0;
            if state^.text_len > 0 then begin
                dec(state^.text_len);
                state^.text_buf[state^.text_len] := #0;
            end;
            refreshDisplay(state);
        end;
        exit;
    end;

    { Printable characters (32..126) }
    if (key >= 32) and (key <= 126) then begin
        if state^.line_len < MAX_LINE - 1 then begin
            state^.line_buf[state^.line_len] := byte(key);
            inc(state^.line_len);
            state^.line_buf[state^.line_len] := 0;
            appendChar(state, char(key));
            refreshDisplay(state);
        end;
    end;
end;

procedure content_defocus_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PVTermState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_DEFOCUSED then exit;
    state := PVTermState(lv_event_get_user_data(e));
    if state <> nil then
        state^.focused := false;
end;

{ ============================================================
  onClose — clean up instance
  ============================================================ }
procedure onClose(wid: uint32);
var
    cnt     : Plv_obj;
    state   : PVTermState;
    slotPtr : ^uint32;
    bgJob   : PBackgroundJob;
    scr_w   : sint32;
begin
    cnt := windows.getWindowContent(wid);
    state := nil;
    if cnt <> nil then
        state := PVTermState(lv_obj_get_user_data(cnt));

    if state <> nil then begin
        { Kill the terminal process }
        if state^.TerminalPID <> 0 then begin
            processmanager.kill(state^.TerminalPID);
            state^.TerminalPID := 0;
        end;
        { Kill foreground process if running }
        if state^.ForegroundPID <> 0 then begin
            processmanager.kill(state^.ForegroundPID);
            state^.ForegroundPID := 0;
        end;
        { Free any remaining I/O buffers }
        if state^.fg_stdout <> nil then begin stdio.freeOutBuf(state^.fg_stdout); state^.fg_stdout := nil; end;
        if state^.fg_stderr <> nil then begin stdio.freeOutBuf(state^.fg_stderr); state^.fg_stderr := nil; end;
        if state^.fg_stdin  <> nil then begin stdio.freeOutBuf(state^.fg_stdin);  state^.fg_stdin  := nil; end;
        if state^.fg_params <> nil then begin stdio.freeParams(state^.fg_params); state^.fg_params := nil; end;
        { Kill and free background jobs }
        if state^.bg_jobs <> nil then begin
            for scr_w := sint32(DL_Size(state^.bg_jobs)) - 1 downto 0 do begin
                slotPtr := DL_Get(state^.bg_jobs, uint32(scr_w));
                if slotPtr <> nil then begin
                    bgJob := PBackgroundJob(slotPtr^);
                    if bgJob <> nil then begin
                        processmanager.kill(bgJob^.PID);
                        if bgJob^.StdOut <> nil then stdio.freeOutBuf(bgJob^.StdOut);
                        if bgJob^.StdErr <> nil then stdio.freeOutBuf(bgJob^.StdErr);
                        kfree(void(bgJob));
                    end;
                end;
            end;
            DL_Free(state^.bg_jobs);
            state^.bg_jobs := nil;
        end;
        { Remove focus }
        if state^.focused and (state^.content <> nil) then
            lv_group_remove_obj(state^.content);
        { Delete the drain timer }
        if state^.drain_timer <> nil then begin
            lv_timer_delete(state^.drain_timer);
            state^.drain_timer := nil;
        end;
        { Free per-terminal CWD and dir stack }
        if state^.cwd <> nil then begin
            kfree(void(state^.cwd));
            state^.cwd := nil;
        end;
        if state^.dir_stack <> nil then begin
            STRLL_Free(state^.dir_stack);
            state^.dir_stack := nil;
        end;
        { Free instance state }
        kfree(void(state));
    end;

    windows.destroyWindow(wid);
end;

{ ============================================================
  launch — create a new terminal instance
  ============================================================ }
procedure launch;
var
    state        : PVTermState;
    ctx          : PProcessContext;
    scr_w, scr_h : sint32;
    wx, wy       : sint32;
begin
    { Allocate a new instance }
    state := PVTermState(kalloc(SizeOf(TVTermState)));
    if state = nil then exit;
    memset(uint32(state), 0, SizeOf(TVTermState));

    state^.hist_pos := -1;
    state^.cwd := stringCopy('/');
    state^.dir_stack := STRLL_New;

    scr_w := sint32(video.frontBufferWidth);
    scr_h := sint32(video.frontBufferHeight);
    wx := (scr_w - TERM_W) div 2;
    wy := (scr_h - TERM_H) div 2 - 30;

    state^.win_id := windows.createWindow(
        'Terminal',
        wx, wy, TERM_W, TERM_H,
        @onClose,
        nil
    );
    if state^.win_id = 0 then begin
        kfree(void(state));
        exit;
    end;

    state^.content := windows.getWindowContent(state^.win_id);
    if state^.content = nil then begin
        windows.destroyWindow(state^.win_id);
        kfree(void(state));
        exit;
    end;

    { Store state on the content object for retrieval in onClose }
    lv_obj_set_user_data(state^.content, state);

    { Style: black background, terminal feel }
    lv_obj_set_style_bg_color(state^.content, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_bg_opa(state^.content, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_left(state^.content, 8, 0);
    lv_obj_set_style_pad_right(state^.content, 8, 0);
    lv_obj_set_style_pad_top(state^.content, 6, 0);
    lv_obj_set_style_pad_bottom(state^.content, 6, 0);
    lv_obj_add_flag(state^.content, LV_OBJ_FLAG_CLICKABLE);

    { Create text label }
    state^.text_label := lv_label_create(state^.content);
    lv_obj_set_width(state^.text_label, TERM_W - 16);
    lv_obj_set_style_text_color(state^.text_label, lv_color_make(200, 255, 200), 0);
    lv_obj_set_style_text_font(state^.text_label, @hack_14, 0);
    lv_label_set_long_mode(state^.text_label, LV_LABEL_LONG_WRAP);
    lv_label_set_text(state^.text_label, '');

    { Register event handlers with state as user_data }
    lv_obj_add_event_cb(state^.content, @content_click_cb, LV_EVENT_CLICKED, state);
    lv_obj_add_event_cb(state^.content, @content_key_cb, LV_EVENT_KEY, state);
    lv_obj_add_event_cb(state^.content, @content_defocus_cb, LV_EVENT_DEFOCUSED, state);

    { Create per-instance drain timer }
    state^.drain_timer := lv_timer_create(@drain_timer_cb, DRAIN_PERIOD, state);

    { Create terminal process so it appears in PS }
    ctx := processmanager.create('Terminal', @terminal_entry, void(state), 1);
    if ctx <> nil then begin
        state^.TerminalPID := ctx^.ProcessID;
        windows.setWindowOwner(state^.win_id, ctx^.ProcessID);
    end else
        state^.TerminalPID := 0;

    { Welcome message }
    appendText(state, 'Asuro Terminal');
    appendChar(state, #10);
    appendText(state, 'Type HELP for a list of commands.');
    appendChar(state, #10);
    appendChar(state, #10);
    showPrompt(state);
end;

{ ============================================================
  init — register Terminal in the desktop program launcher
  ============================================================ }
procedure init;
begin
    tracer.push_trace('vterminal.init');
    desktop.registerProgram('Terminal', @launch);
    tracer.pop_trace;
end;

end.
