{
    Prog->VTerminal - LVGL-based Visual Terminal Emulator.

    Provides a terminal window with a black background where
    users can type commands. Keyboard input is directed to the
    terminal when its window is focused (clicked).

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit vterminal;

interface

uses
    lvgl, video, windows, desktop, keyboard, serial, tracer,
    strings, util, lmemorymanager, asuro, stdio, vfs;

procedure init;

implementation

const
    TERM_W       = 640;
    TERM_H       = 400;
    MAX_TEXT     = 4096;   { max chars in scrollback buffer }
    MAX_LINE     = 1024;   { max input line length, matches TCommandBuffer }
    VISIBLE_LINES = 22;   { approximate visible lines at font size 14 }
    HIST_SIZE    = 10;    { number of history entries }

var
    win_id       : uint32;
    content      : Plv_obj;
    text_label   : Plv_obj;   { label displaying all terminal text }
    focused      : boolean;   { whether we currently own keyboard focus }

    { Scrollback text buffer — holds all visible text }
    text_buf     : array[0..MAX_TEXT-1] of char;
    text_len     : uint32;

    { Current input line buffer — sized to match stdio.TCommandBuffer }
    line_buf     : stdio.TCommandBuffer;
    line_len     : uint32;

    { Command history ring buffer }
    hist         : array[0..HIST_SIZE-1] of stdio.TCommandBuffer;
    hist_count   : uint32;  { total commands stored (max HIST_SIZE) }
    hist_head    : uint32;  { next write slot }
    hist_pos     : sint32;  { browsing position: -1 = current line, 0..hist_count-1 = offset from newest }
    saved_line   : stdio.TCommandBuffer;  { saved current input when browsing }
    saved_len    : uint32;

{ ============================================================
  Internal: append string to the scrollback buffer
  ============================================================ }
procedure appendText(s: pchar);
var
    slen, i: uint32;
begin
    if s = nil then exit;
    slen := stringSize(s);
    if slen = 0 then exit;
    { If buffer would overflow, shift out the first half }
    if text_len + slen >= MAX_TEXT - 1 then begin
        i := MAX_TEXT div 2;
        memcpy(uint32(@text_buf[i]), uint32(@text_buf[0]), text_len - i);
        text_len := text_len - i;
    end;
    memcpy(uint32(s), uint32(@text_buf[text_len]), slen);
    text_len := text_len + slen;
    text_buf[text_len] := #0;
end;

{ ============================================================
  Internal: append a single character
  ============================================================ }
procedure appendChar(c: char);
var
    tmp: array[0..1] of char;
begin
    tmp[0] := c;
    tmp[1] := #0;
    appendText(@tmp[0]);
end;

{ ============================================================
  Public write procedures — terminal output API
  These allow commands to write to this terminal.
  ============================================================ }
procedure writeStr(s: pchar);
begin
    appendText(s);
end;

procedure writeLn(s: pchar);
begin
    appendText(s);
    appendChar(#10);
end;

procedure writeInt(val: uint32);
begin
    appendText(intToString(val));
end;

{ ============================================================
  Internal: refresh the display label from the text buffer
  ============================================================ }
procedure refreshDisplay;
var
    sb: sint32;
begin
    if (text_label <> nil) and (content <> nil) then begin
        lv_label_set_text(text_label, @text_buf[0]);
        { Force full screen layout so LVGL recalculates the label height }
        lv_obj_update_layout(lv_screen_active);
        { Get remaining scrollable distance to bottom and scroll by that }
        sb := lv_obj_get_scroll_bottom(content);
        serial.sendString('[VT] scroll_bottom=');
        serial.sendString(intToString(sb));
        serial.sendString(#13#10);
        if sb > 0 then
            lv_obj_scroll_by(content, 0, -sb, LV_ANIM_OFF);
    end;
end;

{ ============================================================
  Internal: display the prompt
  ============================================================ }
procedure showPrompt;
begin
    appendText('asuro:');
    appendText(vfs.getWorkingDirectory);
    appendText('> ');
    refreshDisplay;
end;

{ ============================================================
  Internal: process the current input line as a command
  ============================================================ }
procedure processCommand;
var
    params     : PParamList;
    uppera     : pchar;
    cmd        : PCommand;
    outbuf     : POutBuf;
    stdin_buf  : POutBuf;
    stderr_buf : POutBuf;
begin
    { Null-terminate input }
    line_buf[line_len] := 0;

    { Echo the entered line }
    appendChar(#10);

    { Push non-empty lines into history }
    if line_len > 0 then begin
        memcpy(uint32(@line_buf[0]), uint32(@hist[hist_head][0]), line_len + 1);
        hist_head := (hist_head + 1) mod HIST_SIZE;
        if hist_count < HIST_SIZE then inc(hist_count);
    end;
    hist_pos := -1;

    if line_len = 0 then begin
        showPrompt;
        exit;
    end;

    { Parse parameters using stdio's parser }
    params := stdio.getParams(line_buf);

    if (params <> nil) and (params^.Param <> nil) then begin
        uppera := stringToUpper(params^.Param);

        { CLEAR is handled locally — it needs to reset the vterminal text buffer }
        if stringEquals(uppera, 'CLEAR') then begin
            text_len := 0;
            text_buf[0] := #0;
            kfree(void(uppera));
            stdio.freeParams(params);
            line_len := 0;
            memset(uint32(@line_buf[0]), 0, 1024);
            showPrompt;
            exit;
        end;

        { Look up any registered command }
        cmd := stdio.findCommand(uppera);
        kfree(void(uppera));

        if cmd <> nil then begin
            outbuf := stdio.createOutBuf(1024);
            stdin_buf := stdio.createOutBuf(0);
            stderr_buf := stdio.createOutBuf(1024);
            cmd^.method(params, stdin_buf, outbuf, stderr_buf);
            { Display stdout }
            if (outbuf <> nil) and (outbuf^.len > 0) then begin
                outbuf^.buf[outbuf^.len] := #0;  { null-terminate }
                appendText(outbuf^.buf);
            end;
            { Display stderr }
            if (stderr_buf <> nil) and (stderr_buf^.len > 0) then begin
                stderr_buf^.buf[stderr_buf^.len] := #0;  { null-terminate }
                appendText(stderr_buf^.buf);
            end;
            stdio.freeOutBuf(stdin_buf);
            stdio.freeOutBuf(outbuf);
            stdio.freeOutBuf(stderr_buf);
        end else begin
            writeLn('Unknown command. Type HELP for a list.');
        end;
    end;

    stdio.freeParams(params);

    { Reset input line }
    line_len := 0;
    memset(uint32(@line_buf[0]), 0, 1024);

    showPrompt;
end;

{ ============================================================
  Event: content area clicked — acquire keyboard focus
  ============================================================ }
procedure content_click_cb(e: Plv_event); cdecl;
var
    code: lv_event_code_t;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    if content = nil then exit;

    if not focused then begin
        focused := true;
        lv_group_add_obj(lvgl_get_kb_group, content);
        lv_group_focus_obj(content);
    end;
end;

{ ============================================================
  Event: content area receives a key event
  ============================================================ }
procedure content_key_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    key  : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_KEY then exit;

    key := lv_event_get_key(e);

    if key = LV_KEY_ENTER then begin
        processCommand;
        exit;
    end;

    { Up arrow — browse history backward (older) }
    if key = LV_KEY_UP then begin
        if hist_count > 0 then begin
            if hist_pos = -1 then begin
                { Save current input line }
                memcpy(uint32(@line_buf[0]), uint32(@saved_line[0]), line_len + 1);
                saved_len := line_len;
                hist_pos := 0;
            end else if uint32(hist_pos) < hist_count - 1 then
                inc(hist_pos)
            else
                exit;
            { Erase current input from display }
            if text_len >= line_len then
                text_len := text_len - line_len;
            text_buf[text_len] := #0;
            { Load history entry: index = (hist_head - 1 - hist_pos) mod HIST_SIZE }
            line_len := stringSize(@hist[(sint32(hist_head) - 1 - hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]);
            memcpy(uint32(@hist[(sint32(hist_head) - 1 - hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]),
                   uint32(@line_buf[0]), line_len + 1);
            appendText(@line_buf[0]);
            refreshDisplay;
        end;
        exit;
    end;

    { Down arrow — browse history forward (newer) }
    if key = LV_KEY_DOWN then begin
        if hist_pos >= 0 then begin
            { Erase current input from display }
            if text_len >= line_len then
                text_len := text_len - line_len;
            text_buf[text_len] := #0;
            dec(hist_pos);
            if hist_pos >= 0 then begin
                { Load newer history entry }
                line_len := stringSize(@hist[(sint32(hist_head) - 1 - hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]);
                memcpy(uint32(@hist[(sint32(hist_head) - 1 - hist_pos + HIST_SIZE * 2) mod HIST_SIZE][0]),
                       uint32(@line_buf[0]), line_len + 1);
            end else begin
                { Restore saved line }
                memcpy(uint32(@saved_line[0]), uint32(@line_buf[0]), saved_len + 1);
                line_len := saved_len;
            end;
            appendText(@line_buf[0]);
            refreshDisplay;
        end;
        exit;
    end;

    if key = LV_KEY_BACKSPACE then begin
        if line_len > 0 then begin
            dec(line_len);
            line_buf[line_len] := 0;
            { Remove last char from display buffer }
            if text_len > 0 then begin
                dec(text_len);
                text_buf[text_len] := #0;
            end;
            refreshDisplay;
        end;
        exit;
    end;

    { Printable characters (32..126) }
    if (key >= 32) and (key <= 126) then begin
        if line_len < 1023 then begin
            line_buf[line_len] := byte(key);
            inc(line_len);
            line_buf[line_len] := 0;
            appendChar(char(key));
            refreshDisplay;
        end;
    end;
end;

{ ============================================================
  Event: content loses focus
  ============================================================ }
procedure content_defocus_cb(e: Plv_event); cdecl;
var
    code: lv_event_code_t;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_DEFOCUSED then exit;
    focused := false;
end;

{ ============================================================
  Close handler
  ============================================================ }
procedure onClose(wid: uint32);
begin
    if focused and (content <> nil) then
        lv_group_remove_obj(content);
    focused := false;
    content := nil;
    text_label := nil;
    windows.destroyWindow(wid);
    win_id := 0;
end;

{ ============================================================
  Launch — called from the desktop program registry
  ============================================================ }
procedure launch;
var
    scr_w, scr_h : sint32;
    wx, wy       : sint32;
begin
    if windows.isWindowOpen(win_id) then begin
        windows.focusWindow(win_id);
        exit;
    end;

    scr_w := sint32(video.frontBufferWidth);
    scr_h := sint32(video.frontBufferHeight);
    wx := (scr_w - TERM_W) div 2;
    wy := (scr_h - TERM_H) div 2 - 30;

    win_id := windows.createWindow(
        'Terminal',
        wx, wy, TERM_W, TERM_H,
        @onClose,
        nil
    );
    if win_id = 0 then exit;

    content := windows.getWindowContent(win_id);
    if content = nil then exit;

    { Override content style: fully black, no padding for terminal feel }
    lv_obj_set_style_bg_color(content, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_bg_opa(content, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_left(content, 8, 0);
    lv_obj_set_style_pad_right(content, 8, 0);
    lv_obj_set_style_pad_top(content, 6, 0);
    lv_obj_set_style_pad_bottom(content, 6, 0);
    lv_obj_add_flag(content, LV_OBJ_FLAG_CLICKABLE);

    { Create a single label that fills the content area }
    text_label := lv_label_create(content);
    lv_obj_set_width(text_label, TERM_W - 16);
    lv_obj_set_style_text_color(text_label, lv_color_make(200, 255, 200), 0);
    lv_obj_set_style_text_font(text_label, @hack_14, 0);
    lv_label_set_long_mode(text_label, LV_LABEL_LONG_WRAP);
    lv_label_set_text(text_label, '');

    { Register event handlers }
    lv_obj_add_event_cb(content, @content_click_cb, LV_EVENT_CLICKED, nil);
    lv_obj_add_event_cb(content, @content_key_cb, LV_EVENT_KEY, nil);
    lv_obj_add_event_cb(content, @content_defocus_cb, LV_EVENT_DEFOCUSED, nil);

    { Initialize text buffer }
    text_len := 0;
    text_buf[0] := #0;
    line_len := 0;
    hist_pos := -1;
    memset(uint32(@line_buf[0]), 0, 1024);

    { Welcome message }
    writeLn('Asuro Terminal');
    writeLn('Type HELP for a list of commands.');
    appendChar(#10);
    showPrompt;
end;

{ ============================================================
  Init — register with the desktop program launcher
  ============================================================ }
procedure init;
begin
    tracer.push_trace('vterminal.init');
    win_id := 0;
    content := nil;
    text_label := nil;
    focused := false;
    text_len := 0;
    line_len := 0;
    hist_count := 0;
    hist_head := 0;
    hist_pos := -1;
    saved_len := 0;
    memset(uint32(@text_buf[0]), 0, MAX_TEXT);
    memset(uint32(@line_buf[0]), 0, 1024);
    memset(uint32(@hist[0][0]), 0, HIST_SIZE * 1024);
    memset(uint32(@saved_line[0]), 0, 1024);
    desktop.registerProgram('Terminal', @launch);
    tracer.pop_trace;
end;

end.
