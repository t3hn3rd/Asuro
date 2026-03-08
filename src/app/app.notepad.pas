{
    Prog->Notepad - GUI text editor

    Features:
      - Open / Save / Save As via inline file picker
      - Text selection (Shift+Arrow keys)
      - Delete selected range on Backspace / Del
      - Tab to indent selected lines (4 spaces), Shift+Tab to dedent
      - Ctrl+A to select all, Ctrl+S to save
      - Word-wrap toggle (via Wrap button)
      - Status bar showing Line, Col, filename, and dirty flag

    Key design notes:
      - lv_event_t.stop_processing (bit 1 at struct byte offset 24) is set
        directly to prevent LVGL's default textarea key handler from also
        acting on keys we have fully handled ourselves.
      - Shift state is read from driver.hid.keyboard.is_shift / driver.hid.keyboard.is_ctrl.
      - selection anchor (sel_anchor) is stored as a sint32 byte offset;
        -1 means no selection is active.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.notepad;

interface

procedure init();

implementation

uses
    driver.video.desktop,
    app.filepicker,
    driver.hid.keyboard,
    memory.heap,
    driver.video.lvgl,
    proc.mgr,
    proc.types,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vfs,
    driver.video,
    driver.video.windows;

const
    WIN_W          = 700;
    WIN_H          = 500;
    TOOLBAR_H      = 40;
    STATUSBAR_H    = 24;

    { LV_DRAW_LABEL_NO_TXT_SEL — sentinel returned when no selection is set }
    LV_NO_SEL      = $FFFF;
    { LV_TEXTAREA_CURSOR_LAST — pass to set_cursor_pos to go to end-of-text }
    LV_CURSOR_LAST = $7FFF;

    FILE_BUF_SIZE  = 65536;   { 64 KB read / write buffer }

    {
      Byte offset and bitmask for lv_event_t.stop_processing.
      struct lv_event_t (32-bit ABI):
        offset  0: current_target  (ptr)
        offset  4: original_target (ptr)
        offset  8: code            (uint32  — lv_event_code_t)
        offset 12: user_data       (ptr)
        offset 16: param           (ptr)
        offset 20: prev            (ptr)
        offset 24: flags byte      [bit0=deleted, bit1=stop_processing, bit2=stop_bubbling]
    }
    LV_EVT_STOP_OFF = 24;
    LV_EVT_STOP_BIT = 2;    { bit 1 = stop_processing }

type
    PNotepadState = ^TNotepadState;
    TNotepadState = record
        win_id             : uint32;
        pid          : uint32;
        ta           : Plv_obj;
        status_label : Plv_obj;
        dirty_label  : Plv_obj;
        currentPath  : pchar;
        isDirty      : boolean;
        sel_anchor   : sint32;
    end;

{ ============================================================
  Module-level state (single-instance)
  ============================================================ }
var
    win_id  : uint32;
    g_state : PNotepadState;

{ ============================================================
  Forward declarations
  ============================================================ }
procedure notepad_entry(ctx: PProcessContext); forward;
procedure launch; forward;
procedure onClose(wid: uint32); forward;
procedure updateStatusBar(state: PNotepadState); forward;
procedure saveFile(state: PNotepadState); forward;
procedure loadFile(state: PNotepadState; path: pchar); forward;
procedure performNew(state: PNotepadState); forward;
procedure freeState(state: PNotepadState); forward;
procedure doCloseWindow; forward;
procedure showDiscardMsgbox(discard_cb: lv_event_cb_t); forward;
procedure showErrorMsgbox(title: pchar; msg: pchar); forward;
procedure mbox_cancel_cb(e: Plv_event); cdecl; forward;
procedure np_open_done_cb(path: pchar; userdata: pointer); cdecl; forward;
procedure np_saveas_done_cb(path: pchar; userdata: pointer); cdecl; forward;

{ ============================================================
  stopEvent — set LVGL's stop_processing flag in the event
  struct so the widget's default key handler does not run.
  User callbacks fire BEFORE the widget class handler, so this
  correctly suppresses LVGL's default action.
  ============================================================ }
procedure stopEvent(e: Plv_event);
begin
    puint8(uint32(e) + LV_EVT_STOP_OFF)^ :=
        puint8(uint32(e) + LV_EVT_STOP_OFF)^ or LV_EVT_STOP_BIT;
end;

{ ============================================================
  buildSplicedString
  Returns a new kalloc'd pchar containing:
      src[0 .. from_idx)  +  insert  +  src[to_idx .. end)
  insert may be nil (no insertion).  Caller must kfree result.
  ============================================================ }
function buildSplicedString(src: pchar; from_idx, to_idx: uint32;
                            insert: pchar): pchar;
var
    src_len    : uint32;
    ins_len    : uint32;
    result_len : uint32;
    buf        : pchar;
    pos        : uint32;
begin
    src_len := stringSize(src);
    if insert <> nil then ins_len := stringSize(insert)
    else                   ins_len := 0;
    if from_idx > src_len then from_idx := src_len;
    if to_idx   > src_len then to_idx   := src_len;
    if to_idx   < from_idx then to_idx  := from_idx;
    result_len := from_idx + ins_len + (src_len - to_idx);
    buf := pchar(kalloc(result_len + 1));
    memset(uint32(buf), 0, result_len + 1);
    pos := 0;
    if from_idx > 0 then begin
        memcpy(uint32(src), uint32(buf), from_idx);
        pos := from_idx;
    end;
    if ins_len > 0 then begin
        memcpy(uint32(insert), uint32(@buf[pos]), ins_len);
        pos := pos + ins_len;
    end;
    if to_idx < src_len then
        memcpy(uint32(@src[to_idx]), uint32(@buf[pos]), src_len - to_idx);
    buildSplicedString := buf;
end;

{ ============================================================
  applyIndent
  Indent (or dedent) every line that overlaps [sel_start, sel_end)
  by 4 spaces.  Returns a new kalloc'd string.  Caller must kfree.
  ============================================================ }
function applyIndent(src: pchar; sel_start, sel_end: uint32;
                     dedent: boolean): pchar;
var
    src_len  : uint32;
    out_buf  : pchar;
    out_pos  : uint32;
    i        : uint32;
    first_ls : uint32;
    j        : uint32;
begin
    src_len := stringSize(src);
    if sel_end   > src_len then sel_end   := src_len;
    if sel_start > src_len then sel_start := src_len;

    { Find start of the line that contains sel_start }
    first_ls := sel_start;
    while (first_ls > 0) and (src[first_ls - 1] <> char(10)) do
        dec(first_ls);

    { Generous output buffer: original + 4 bytes per line (worst case ~512 lines) }
    out_buf := pchar(kalloc(src_len + 2049));
    memset(uint32(out_buf), 0, src_len + 2049);
    out_pos := 0;

    { Copy everything before the affected region verbatim }
    if first_ls > 0 then begin
        memcpy(uint32(src), uint32(out_buf), first_ls);
        out_pos := first_ls;
    end;

    { Process from first_ls onward, line by line }
    i := first_ls;
    while i <= src_len do begin
        if i = src_len then break;   { nothing left }

        if i >= sel_end then begin
            { Past the affected region: copy the remainder verbatim }
            if i < src_len then begin
                memcpy(uint32(@src[i]), uint32(@out_buf[out_pos]), src_len - i);
                out_pos := out_pos + (src_len - i);
            end;
            break;
        end;

        { Apply indent / dedent at the start of this affected line }
        if not dedent then begin
            out_buf[out_pos]     := ' ';
            out_buf[out_pos + 1] := ' ';
            out_buf[out_pos + 2] := ' ';
            out_buf[out_pos + 3] := ' ';
            out_pos := out_pos + 4;
        end else begin
            { Strip up to 4 leading spaces }
            j := 0;
            while (j < 4) and (i < src_len) and (src[i] = ' ') do begin
                inc(i);
                inc(j);
            end;
        end;

        { Copy the rest of the line up to and including the newline }
        while i < src_len do begin
            out_buf[out_pos] := src[i];
            inc(out_pos);
            if src[i] = char(10) then begin
                inc(i);
                break;
            end;
            inc(i);
        end;
    end;

    out_buf[out_pos] := char(0);
    applyIndent := out_buf;
end;

{ ============================================================
  computeLineCol
  Calculate 1-based line and column numbers for a byte offset.
  ============================================================ }
procedure computeLineCol(src: pchar; byte_pos: uint32;
                         var line_out, col_out: uint32);
var
    i    : uint32;
    line : uint32;
    col  : uint32;
    len  : uint32;
begin
    line := 1;
    col  := 1;
    len  := stringSize(src);
    if byte_pos > len then byte_pos := len;
    i := 0;
    while i < byte_pos do begin
        if src[i] = char(10) then begin
            inc(line);
            col := 1;
        end else
            inc(col);
        inc(i);
    end;
    line_out := line;
    col_out  := col;
end;

{ ============================================================
  freeState — release all kalloc'd fields and the record itself.
  ============================================================ }
procedure freeState(state: PNotepadState);
begin
    if state = nil then exit;
    if state^.ta <> nil then lv_group_remove_obj(state^.ta);
    if state^.currentPath <> nil then kfree(void(state^.currentPath));
    kfree(void(state));
end;

{ ============================================================
  doCloseWindow — unconditionally destroy window + free state.
  Called by discard-confirm dialogs and by onClose when clean.
  ============================================================ }
procedure notepad_entry(ctx : PProcessContext);
begin
    while (ctx^.State <> psFinished) and (ctx^.PendingMsg <> smKill) and (ctx^.PendingMsg <> smTerminate) do
        proc.mgr.proc_yield;
end;

procedure doCloseWindow;
begin
    if g_state <> nil then begin
        if g_state^.pid <> 0 then begin
            proc.mgr.kill(g_state^.pid);
            g_state^.pid := 0;
        end;
        freeState(g_state);
        g_state := nil;
    end;
    driver.video.windows.destroyWindow(win_id);
    win_id := 0;
end;

{ ============================================================
  updateStatusBar
  ============================================================ }
procedure updateStatusBar(state: PNotepadState);
var
    txt         : pchar;
    cpos        : uint32;
    line, col   : uint32;
    s1, s2, s3  : pchar;
begin
    if (state = nil) or (state^.status_label = nil) then exit;
    txt  := lv_textarea_get_text(state^.ta);
    cpos := lv_textarea_get_cursor_pos(state^.ta);
    computeLineCol(txt, cpos, line, col);

    s1 := intToString(line);
    s2 := stringConcat('Ln ', s1);
    kfree(void(s1));
    s1 := intToString(col);
    s3 := stringConcat(s2, stringConcat('  Col ', s1));
    kfree(void(s2));
    kfree(void(s1));

    if state^.currentPath <> nil then
        s1 := stringConcat('    ', state^.currentPath)
    else
        s1 := stringCopy('    Untitled');
    s2 := stringConcat(s3, s1);
    kfree(void(s3));
    kfree(void(s1));

    lv_label_set_text(state^.status_label, s2);
    kfree(void(s2));

    if state^.isDirty then
        lv_label_set_text(state^.dirty_label, '*')
    else
        lv_label_set_text(state^.dirty_label, '');
end;

{ ============================================================
  saveFile
  ============================================================ }
procedure saveFile(state: PNotepadState);
var
    fHandle : driver.storage.vfs.TFileHandle;
    fError  : driver.storage.types.TError;
    txt     : pchar;
    buf     : pchar;
    len     : uint32;
    written : uint32;
    s1, s2  : pchar;
begin
    debug.tracer.push_trace('notepad.saveFile');
    if state^.currentPath = nil then begin
        app.filepicker.show_save('Save As', '/disk', nil, nil, @np_saveas_done_cb, state);
        debug.tracer.pop_trace;
        exit;
    end;
    { Show Saving... immediately for feedback before the blocking I/O call }
    lv_label_set_text(state^.status_label, 'Saving...');
    txt := lv_textarea_get_text(state^.ta);
    len := stringSize(txt);
    if len > FILE_BUF_SIZE - 1 then len := FILE_BUF_SIZE - 1;
    buf := pchar(kalloc(FILE_BUF_SIZE));
    memset(uint32(buf), 0, FILE_BUF_SIZE);
    memcpy(uint32(txt), uint32(buf), len);
    fHandle := driver.storage.vfs.OpenFile(state^.currentPath, omReadWrite, @fError);
    if fHandle = 0 then
        fHandle := driver.storage.vfs.OpenFile(state^.currentPath, omCreate, @fError);
    if fHandle = 0 then begin
        kfree(void(buf));
        io.syslog.logln('NOTEPAD', 'saveFile: OpenFile failed');
        showErrorMsgbox('Save Failed', 'Could not open file for writing.');
        updateStatusBar(state);
        debug.tracer.pop_trace;
        exit;
    end;
    written := driver.storage.vfs.WriteFile(fHandle, 0, puint8(buf), len);
    driver.storage.vfs.CloseFile(fHandle);
    kfree(void(buf));
    if written = 0 then begin
        io.syslog.logln('NOTEPAD', 'saveFile: WriteFile returned 0');
        showErrorMsgbox('Save Failed', 'File write failed. Check filesystem.');
        updateStatusBar(state);
        debug.tracer.pop_trace;
        exit;
    end;
    state^.isDirty := false;
    s1 := stringCopy('Saved: ');
    s2 := stringConcat(s1, state^.currentPath);
    kfree(void(s1));
    lv_label_set_text(state^.status_label, s2);
    kfree(void(s2));
    lv_label_set_text(state^.dirty_label, '');
    debug.tracer.pop_trace;
end;

{ ============================================================
  loadFile
  ============================================================ }
procedure loadFile(state: PNotepadState; path: pchar);
var
    fHandle : driver.storage.vfs.TFileHandle;
    fError  : driver.storage.types.TError;
    buf     : pchar;
begin
    debug.tracer.push_trace('notepad.loadFile');
    fHandle := driver.storage.vfs.OpenFile(path, omRead, @fError);
    if (fHandle = 0) or (fError <> eNone) then begin
        io.syslog.logln('NOTEPAD', 'loadFile: could not open file');
        showErrorMsgbox('Open Failed', 'Could not open file for reading.');
        debug.tracer.pop_trace;
        exit;
    end;
    buf := pchar(kalloc(FILE_BUF_SIZE));
    memset(uint32(buf), 0, FILE_BUF_SIZE);
    driver.storage.vfs.ReadFile(fHandle, 0, puint8(buf), FILE_BUF_SIZE - 1);
    driver.storage.vfs.CloseFile(fHandle);
    if state^.currentPath <> nil then kfree(void(state^.currentPath));
    state^.currentPath := stringCopy(path);
    lv_textarea_set_text(state^.ta, buf);
    { lv_textarea_set_text fires VALUE_CHANGED which marks dirty — reset it }
    state^.isDirty := false;
    lv_textarea_clear_selection(state^.ta);
    state^.sel_anchor := -1;
    lv_textarea_set_cursor_pos(state^.ta, 0);
    updateStatusBar(state);
    kfree(void(buf));
    debug.tracer.pop_trace;
end;

{ ============================================================
  performNew — clear buffer and reset path
  ============================================================ }
procedure performNew(state: PNotepadState);
begin
    lv_textarea_set_text(state^.ta, '');
    state^.isDirty := false;
    state^.sel_anchor := -1;
    lv_textarea_clear_selection(state^.ta);
    if state^.currentPath <> nil then begin
        kfree(void(state^.currentPath));
        state^.currentPath := nil;
    end;
    updateStatusBar(state);
end;

{ ============================================================
  Discard-confirmation msgbox callbacks
  ============================================================ }

{ Generic cancel: just close the msgbox (passed as user_data) }
procedure mbox_cancel_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    mbox : Plv_obj;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    mbox := Plv_obj(lv_event_get_user_data(e));
    lv_obj_delete(mbox);
end;

{ Discard + close window }
procedure mbox_close_discard_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    mbox : Plv_obj;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    mbox := Plv_obj(lv_event_get_user_data(e));
    lv_obj_delete(mbox);
    doCloseWindow;
end;

{ Discard + new document }
procedure mbox_new_discard_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    mbox  : Plv_obj;
    state : PNotepadState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    mbox  := Plv_obj(lv_event_get_user_data(e));
    state := g_state;
    lv_obj_delete(mbox);
    if state <> nil then performNew(state);
end;

{ ============================================================
  showDiscardMsgbox — generic "Unsaved changes / Discard?" dialog.
  discard_cb receives the mbox pointer as user_data.
  ============================================================ }
procedure showDiscardMsgbox(discard_cb: lv_event_cb_t);
var
    mbox      : Plv_obj;
    scr       : Plv_obj;
    discard_b : Plv_obj;
    cancel_b  : Plv_obj;
begin
    scr       := lv_screen_active;
    mbox      := lv_msgbox_create(scr);
    lv_msgbox_add_title(mbox, 'Unsaved Changes');
    lv_msgbox_add_close_button(mbox);
    cancel_b  := lv_msgbox_add_footer_button(mbox, 'Cancel');
    discard_b := lv_msgbox_add_footer_button(mbox, 'Discard');
    lv_obj_add_event_cb(discard_b, discard_cb,      LV_EVENT_CLICKED, mbox);
    lv_obj_add_event_cb(cancel_b,  @mbox_cancel_cb, LV_EVENT_CLICKED, mbox);
end;

{ ============================================================
  showErrorMsgbox — modal error dialog with OK button
  ============================================================ }
procedure showErrorMsgbox(title: pchar; msg: pchar);
var
    mbox : Plv_obj;
    ok_b : Plv_obj;
begin
    mbox := lv_msgbox_create(lv_screen_active);
    lv_msgbox_add_title(mbox, title);
    lv_msgbox_add_text(mbox, msg);
    ok_b := lv_msgbox_add_footer_button(mbox, 'OK');
    lv_obj_add_event_cb(ok_b, @mbox_cancel_cb, LV_EVENT_CLICKED, mbox);
end;

{ ============================================================
  File picker done callbacks
  ============================================================ }

procedure np_open_done_cb(path: pchar; userdata: pointer); cdecl;
var
    state: PNotepadState;
begin
    state := PNotepadState(userdata);
    if (path = nil) or (state = nil) then begin
        if path <> nil then kfree(void(path));
        exit;
    end;
    loadFile(state, path);
    kfree(void(path));
end;

procedure np_saveas_done_cb(path: pchar; userdata: pointer); cdecl;
var
    state: PNotepadState;
begin
    state := PNotepadState(userdata);
    if (path = nil) or (state = nil) then begin
        if path <> nil then kfree(void(path));
        exit;
    end;
    if state^.currentPath <> nil then kfree(void(state^.currentPath));
    state^.currentPath := stringCopy(path);
    kfree(void(path));
    saveFile(state);
end;

{ ============================================================
  Toolbar callbacks
  ============================================================ }

procedure new_btn_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PNotepadState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PNotepadState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.isDirty then
        showDiscardMsgbox(@mbox_new_discard_cb)
    else
        performNew(state);
end;

procedure open_btn_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PNotepadState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PNotepadState(lv_event_get_user_data(e));
    if state = nil then exit;
    app.filepicker.show_open('Open File', '/disk', nil, @np_open_done_cb, state);
end;

procedure save_btn_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PNotepadState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PNotepadState(lv_event_get_user_data(e));
    if state = nil then exit;
    saveFile(state);
end;

procedure saveas_btn_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PNotepadState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PNotepadState(lv_event_get_user_data(e));
    if state = nil then exit;
    app.filepicker.show_save('Save As', '/disk', nil, nil, @np_saveas_done_cb, state);
end;

{ ============================================================
  Main textarea — key handler
  User callbacks fire BEFORE the widget default handler.
  We call stopEvent(e) for every key we handle ourselves so
  LVGL does not also act on it.
  ============================================================ }
procedure ta_key_cb(e: Plv_event); cdecl;
var
    code     : lv_event_code_t;
    state    : PNotepadState;
    key      : uint32;
    ta       : Plv_obj;
    lbl      : Plv_obj;
    curr_pos : uint32;
    new_pos  : uint32;
    anchor   : uint32;
    sel_s    : uint32;
    sel_e    : uint32;
    src      : pchar;
    new_text : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_KEY then exit;
    state := PNotepadState(lv_event_get_user_data(e));
    if state = nil then exit;
    ta       := state^.ta;
    lbl      := lv_textarea_get_label(ta);
    key      := lv_event_get_key(e);
    curr_pos := lv_textarea_get_cursor_pos(ta);

    { ---- Ctrl+S: save ---- }
    if driver.hid.keyboard.is_ctrl and (key = ord('s')) then begin
        saveFile(state);
        stopEvent(e);
        exit;
    end;

    { ---- Ctrl+A: select all ---- }
    if driver.hid.keyboard.is_ctrl and (key = ord('a')) then begin
        src := lv_textarea_get_text(ta);
        state^.sel_anchor := 0;
        lv_label_set_text_selection_start(lbl, 0);
        lv_label_set_text_selection_end(lbl, stringSize(src));
        lv_textarea_set_cursor_pos(ta, LV_CURSOR_LAST);
        stopEvent(e);
        exit;
    end;

    { ---- Plain arrow keys (no Shift): clear any existing selection ---- }
    if (not driver.hid.keyboard.is_shift) and
       ((key = LV_KEY_LEFT)  or (key = LV_KEY_RIGHT) or
        (key = LV_KEY_UP)    or (key = LV_KEY_DOWN)) then begin
        if state^.sel_anchor <> -1 then begin
            state^.sel_anchor := -1;
            lv_textarea_clear_selection(ta);
        end;
        { Let LVGL handle cursor movement — do NOT call stopEvent }
        exit;
    end;

    { ---- Home / End: clear selection, let LVGL handle position ---- }
    if (key = LV_KEY_HOME) or (key = LV_KEY_END) then begin
        state^.sel_anchor := -1;
        lv_textarea_clear_selection(ta);
        exit;
    end;

    { ---- Shift+Arrow: extend / create selection ---- }
    if driver.hid.keyboard.is_shift and
       ((key = LV_KEY_LEFT)  or (key = LV_KEY_RIGHT) or
        (key = LV_KEY_UP)    or (key = LV_KEY_DOWN)) then begin
        { Initialise anchor on first Shift+Arrow }
        if state^.sel_anchor = -1 then
            state^.sel_anchor := sint32(curr_pos);
        { Move cursor ourselves so we get the updated position }
        case key of
            LV_KEY_LEFT  : lv_textarea_cursor_left(ta);
            LV_KEY_RIGHT : lv_textarea_cursor_right(ta);
            LV_KEY_UP    : lv_textarea_cursor_up(ta);
            LV_KEY_DOWN  : lv_textarea_cursor_down(ta);
        end;
        new_pos := lv_textarea_get_cursor_pos(ta);
        anchor  := uint32(state^.sel_anchor);
        if new_pos < anchor then begin
            lv_label_set_text_selection_start(lbl, new_pos);
            lv_label_set_text_selection_end(lbl, anchor);
        end else begin
            lv_label_set_text_selection_start(lbl, anchor);
            lv_label_set_text_selection_end(lbl, new_pos);
        end;
        { Stop LVGL from also moving the cursor (would double-move) }
        stopEvent(e);
        exit;
    end;

    { ---- Backspace / Del with active selection: delete the selection ---- }
    if ((key = LV_KEY_BACKSPACE) or (key = LV_KEY_DEL)) and
       (state^.sel_anchor <> -1) then begin
        anchor := uint32(state^.sel_anchor);
        if anchor < curr_pos then begin
            sel_s := anchor;
            sel_e := curr_pos;
        end else begin
            sel_s := curr_pos;
            sel_e := anchor;
        end;
        src      := lv_textarea_get_text(ta);
        new_text := buildSplicedString(src, sel_s, sel_e, nil);
        lv_textarea_set_text(ta, new_text);
        kfree(void(new_text));
        lv_textarea_set_cursor_pos(ta, sint32(sel_s));
        state^.sel_anchor := -1;
        lv_textarea_clear_selection(ta);
        state^.isDirty := true;
        updateStatusBar(state);
        stopEvent(e);   { prevent LVGL from also deleting one more char }
        exit;
    end;

    { ---- Tab key ---- }
    if key = LV_KEY_NEXT then begin
        if state^.sel_anchor <> -1 then begin
            { Indent or dedent the selected lines }
            anchor := uint32(state^.sel_anchor);
            if anchor < curr_pos then begin
                sel_s := anchor;
                sel_e := curr_pos;
            end else begin
                sel_s := curr_pos;
                sel_e := anchor;
            end;
            src      := lv_textarea_get_text(ta);
            new_text := applyIndent(src, sel_s, sel_e, driver.hid.keyboard.is_shift);
            lv_textarea_set_text(ta, new_text);
            kfree(void(new_text));
            state^.sel_anchor := -1;
            lv_textarea_clear_selection(ta);
            state^.isDirty := true;
            updateStatusBar(state);
        end else begin
            { No selection: insert 4 spaces }
            lv_textarea_add_text(ta, '    ');
        end;
        stopEvent(e);   { prevent LVGL from inserting a raw tab char }
        exit;
    end;

    { ---- Any other key with selection active: clear selection, let LVGL type ---- }
    if state^.sel_anchor <> -1 then begin
        state^.sel_anchor := -1;
        lv_textarea_clear_selection(ta);
    end;
end;

{ ============================================================
  Main textarea — VALUE_CHANGED (dirty tracking + status bar)
  ============================================================ }
procedure ta_changed_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PNotepadState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_VALUE_CHANGED then exit;
    state := PNotepadState(lv_event_get_user_data(e));
    if state = nil then exit;
    state^.isDirty := true;
    updateStatusBar(state);
end;

{ ============================================================
  makeToolBtn — compact toolbar button helper
  ============================================================ }
function makeToolBtn(parent: Plv_obj; text: pchar; w: sint32;
                     state_ptr: PNotepadState;
                     cb: lv_event_cb_t): Plv_obj;
var
    btn, lbl_obj : Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, w, 30);
    lv_obj_set_style_bg_color(btn, lv_color_make(45, 50, 68), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, 4, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lbl_obj := lv_label_create(btn);
    lv_label_set_text(lbl_obj, text);
    lv_obj_set_style_text_color(lbl_obj, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(lbl_obj, @lv_font_montserrat_14, 0);
    lv_obj_add_event_cb(btn, cb, LV_EVENT_CLICKED, state_ptr);
    makeToolBtn := btn;
end;

{ ============================================================
  onClose — called by the driver.video.windows unit when the X button is pressed
  ============================================================ }
procedure onClose(wid: uint32);
begin
    debug.tracer.push_trace('notepad.onClose');
    if (g_state <> nil) and g_state^.isDirty then begin
        { Show discard confirmation; leave window open for now }
        showDiscardMsgbox(@mbox_close_discard_cb);
        debug.tracer.pop_trace;
        exit;
    end;
    doCloseWindow;
    debug.tracer.pop_trace;
end;

{ ============================================================
  launch — create the window and populate the UI
  ============================================================ }
procedure launch;
var
    scr_w, scr_h : sint32;
    wx, wy       : sint32;
    content      : Plv_obj;
    toolbar      : Plv_obj;
    statusbar    : Plv_obj;
    ta           : Plv_obj;
    sl    : Plv_obj;
    dl    : Plv_obj;
    state : PNotepadState;
    ctx   : PProcessContext;
begin
    debug.tracer.push_trace('notepad.launch');

    if driver.video.windows.isWindowOpen(win_id) then begin
        debug.tracer.pop_trace; exit;
    end;

    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);
    wx    := (scr_w - WIN_W) div 2;
    wy    := (scr_h - WIN_H) div 2 - 30;

    win_id := driver.video.windows.createWindow('Notepad', wx, wy, WIN_W, WIN_H,
                                   @onClose, nil);
    if win_id = 0 then begin
        debug.tracer.pop_trace; exit;
    end;

    content := driver.video.windows.getWindowContent(win_id);
    if content = nil then begin
        driver.video.windows.destroyWindow(win_id);
        win_id := 0;
        debug.tracer.pop_trace; exit;
    end;

    { Allocate and zero-initialise state }
    state := PNotepadState(kalloc(sizeof(TNotepadState)));
    memset(uint32(state), 0, sizeof(TNotepadState));
    state^.win_id     := win_id;
    state^.sel_anchor := -1;
    g_state := state;

    { ---- Content area: flex column ---- }
    lv_obj_set_style_layout(content, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(content, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_all(content, 0, 0);
    lv_obj_set_style_pad_row(content, 0, 0);
    lv_obj_remove_flag(content, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(content, lv_color_make(28, 31, 40), 0);
    lv_obj_set_style_bg_opa(content, LV_OPA_COVER, 0);

    { ---- Toolbar ---- }
    toolbar := lv_obj_create(content);
    lv_obj_remove_style_all(toolbar);
    lv_obj_set_size(toolbar, lv_pct(100), TOOLBAR_H);
    lv_obj_set_style_bg_color(toolbar, lv_color_make(28, 31, 40), 0);
    lv_obj_set_style_bg_opa(toolbar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(toolbar, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_side(toolbar, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_width(toolbar, 1, 0);
    lv_obj_set_style_pad_all(toolbar, 5, 0);
    lv_obj_set_style_pad_column(toolbar, 4, 0);
    lv_obj_set_style_layout(toolbar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(toolbar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(toolbar, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                         LV_FLEX_ALIGN_CENTER);
    lv_obj_remove_flag(toolbar, LV_OBJ_FLAG_SCROLLABLE);

    { File group: New, Open, Save, Save As }
    makeToolBtn(toolbar, 'New',     58, state, @new_btn_cb);
    makeToolBtn(toolbar, 'Open',    64, state, @open_btn_cb);
    makeToolBtn(toolbar, 'Save',    58, state, @save_btn_cb);
    makeToolBtn(toolbar, 'Save As', 80, state, @saveas_btn_cb);

    { ---- Main textarea ---- }
    ta := lv_textarea_create(content);
    lv_obj_set_size(ta, lv_pct(100), 0);
    lv_obj_set_flex_grow(ta, 1);
    lv_textarea_set_text(ta, '');
    lv_textarea_set_text_selection(ta, true);
    { Background and text }
    lv_obj_set_style_bg_color(ta, lv_color_make(20, 22, 32), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(ta, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_text_color(ta, lv_color_make(210, 218, 240), LV_PART_MAIN);
    lv_obj_set_style_text_font(ta, @hack_14, LV_PART_MAIN);
    lv_obj_set_style_border_width(ta, 0, LV_PART_MAIN);
    lv_obj_set_style_radius(ta, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(ta, 8, LV_PART_MAIN);
    { Cursor }
    lv_obj_set_style_bg_color(ta, lv_color_make(100, 160, 255), LV_PART_CURSOR);
    lv_obj_set_style_border_width(ta, 0, LV_PART_CURSOR);
    { Selection highlight }
    lv_obj_set_style_bg_color(ta, lv_color_make(55, 90, 190), LV_PART_SELECTED);
    lv_obj_set_style_bg_opa(ta, LV_OPA_COVER, LV_PART_SELECTED);
    { Register with driver.hid.keyboard group }
    lv_group_add_obj(lvgl_get_kb_group, ta);
    lv_group_focus_obj(ta);
    { Always wrap — set before attaching callbacks }
    lv_label_set_long_mode(lv_textarea_get_label(ta), LV_LABEL_LONG_WRAP);
    { Attach event callbacks (state passed as user_data) }
    lv_obj_add_event_cb(ta, @ta_key_cb,     LV_EVENT_KEY,          state);
    lv_obj_add_event_cb(ta, @ta_changed_cb, LV_EVENT_VALUE_CHANGED, state);
    state^.ta := ta;

    { ---- Status bar ---- }
    statusbar := lv_obj_create(content);
    lv_obj_remove_style_all(statusbar);
    lv_obj_set_size(statusbar, lv_pct(100), STATUSBAR_H);
    lv_obj_set_style_bg_color(statusbar, lv_color_make(28, 31, 40), 0);
    lv_obj_set_style_bg_opa(statusbar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(statusbar, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_side(statusbar, LV_BORDER_SIDE_TOP, 0);
    lv_obj_set_style_border_width(statusbar, 1, 0);
    lv_obj_set_style_layout(statusbar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(statusbar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(statusbar, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                         LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_left(statusbar, 8, 0);
    lv_obj_remove_flag(statusbar, LV_OBJ_FLAG_SCROLLABLE);

    sl := lv_label_create(statusbar);
    lv_label_set_text(sl, 'Ln 1  Col 1    Untitled');
    lv_obj_set_style_text_color(sl, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(sl, @lv_font_montserrat_14, 0);
    state^.status_label := sl;

    dl := lv_label_create(statusbar);
    lv_label_set_text(dl, '');
    lv_obj_set_style_text_color(dl, lv_color_make(255, 180, 60), 0);
    lv_obj_set_style_text_font(dl, @lv_font_montserrat_14, 0);
    state^.dirty_label := dl;

    { Create process so app.notepad appears in PS and is manageable }
    ctx := proc.mgr.create('Notepad', @notepad_entry, void(state), 1);
    if ctx <> nil then begin
        state^.pid := ctx^.ProcessID;
        driver.video.windows.setWindowOwner(win_id, ctx^.ProcessID);
    end;

    debug.tracer.pop_trace;
end;

{ ============================================================
  init — register with the driver.video.desktop program launcher
  ============================================================ }
procedure init();
begin
    debug.tracer.push_trace('notepad.init');
    win_id  := 0;
    g_state := nil;
    driver.video.desktop.registerProgram('Notepad', @launch);
    debug.tracer.pop_trace;
end;

end.
