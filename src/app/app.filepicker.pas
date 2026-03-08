{
    Prog->FilePicker - OS-level reusable file picker dialog

    Features:
      - Two-pane layout: bookmarks sidebar + sorted file list
      - Navigation history: Back / Forward / Up buttons
      - Sorted display: directories first then files, both alphabetical
      - File size shown inline per entry
      - Extension filter (caller-supplied; nil = all files)
      - Inline New Folder creation (no sub-modal)
      - Save-mode overwrite guard: two-click confirmation
      - Status bar: "X dirs, Y files"

    Usage:
        filepicker.show_open(title, start_dir, filter, callback, userdata)
        filepicker.show_save(title, start_dir, initial_name, filter, callback, userdata)

    The callback receives a kalloc'd path string the caller must kfree,
    or nil when the user cancels.

    Design:
      - A full-screen semi-transparent backdrop (child of lv_screen_active)
        absorbs clicks, preventing interaction with the app behind.
      - A centered panel is a child of the backdrop so a single
        lv_obj_delete(backdrop) tears down everything.
      - Entry row user_data holds stringCopy'd entry names freed in
        free_list_items before any list repopulation or close.
      - Bookmark button user_data holds stringCopy'd paths freed in
        free_bkmk_items before close.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.filepicker;

interface

const
    FP_FILTER_ALL = nil;   { pass as filter param to show all file core.types }

type
    TPickerCallback = procedure(path: pchar; userdata: pointer); cdecl;

procedure show_open(title     : pchar;
                    start_dir : pchar;
                    filter    : pchar;
                    cb        : TPickerCallback;
                    userdata  : pointer);

procedure show_save(title        : pchar;
                    start_dir    : pchar;
                    initial_name : pchar;
                    filter       : pchar;
                    cb           : TPickerCallback;
                    userdata     : pointer);

implementation

uses
    core.ds.hashmap,
    memory.heap,
    driver.video.lvgl,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer,
    core.util, arch.x86.util,
    driver.storage.vfs;

const
    PANEL_W   = 580;
    PANEL_H   = 480;
    BKMK_W    = 120;   { bookmarks sidebar fixed width }
    HIST_MAX  = 16;    { navigation history depth cap  }
    ENTRY_MAX = 256;   { max entries collected per pass in do_refresh }

type
    { Flat name buffer — heap-alloc'd in do_refresh to avoid stack bloat }
    TNameBuf  = array[0..ENTRY_MAX - 1] of pchar;
    PNameBuf  = ^TNameBuf;
    TSizeBuf  = array[0..ENTRY_MAX - 1] of uint32;
    PSizeBuf  = ^TSizeBuf;

    { Per-call context passed to the forEach collect callback }
    PFPCollectCtx = ^TFPCollectCtx;
    TFPCollectCtx = record
        dir_names  : PNameBuf;
        file_names : PNameBuf;
        file_sizes : PSizeBuf;
        dir_count  : uint32;
        file_count : uint32;
        filter     : pchar;
    end;

    PPicker = ^TPicker;
    TPicker = record
        { Root UI object — deleting this tears down everything }
        backdrop      : Plv_obj;
        { Navigation row }
        path_bar      : Plv_obj;
        back_btn      : Plv_obj;
        fwd_btn       : Plv_obj;
        { Content area }
        bkmk_panel    : Plv_obj;
        file_list     : Plv_obj;   { flex-column scrollable container }
        { Info strip }
        status_label  : Plv_obj;
        { Save mode }
        fname_bar     : Plv_obj;   { nil in open mode }
        { Bottom rows }
        action_row    : Plv_obj;
        newfolder_row : Plv_obj;
        newfolder_bar : Plv_obj;
        { State }
        cur_dir         : pchar;
        cb              : TPickerCallback;
        userdata        : pointer;
        is_save         : boolean;
        pending_refresh : boolean;
        confirm_pending : boolean;  { save: waiting for 2nd-click overwrite }
        filter          : pchar;    { nil=all; else extension e.g. '.txt' }
        { Navigation history: history[0..hist_len-1] are kalloc'd pchars }
        history  : array[0..HIST_MAX - 1] of pchar;
        hist_len : sint32;
        hist_pos : sint32;   { index in history of current location }
    end;

{ ============================================================
  Forward declarations
  ============================================================ }
procedure picker_close(p: PPicker; sel_path: pchar); forward;
procedure do_refresh(p: PPicker); forward;
procedure fp_collect_cb(key: pchar; data: void; ud: void); forward;
procedure schedule_refresh(p: PPicker); forward;
procedure navigate_to(p: PPicker; newDir: pchar); forward;
procedure fp_refresh_timer_cb(tmr: Plv_timer); cdecl; forward;
procedure fp_dir_cb(e: Plv_event); cdecl; forward;
procedure fp_file_cb(e: Plv_event); cdecl; forward;
procedure fp_confirm_cb(e: Plv_event); cdecl; forward;
procedure fp_cancel_cb(e: Plv_event); cdecl; forward;
procedure fp_up_cb(e: Plv_event); cdecl; forward;
procedure fp_back_cb(e: Plv_event); cdecl; forward;
procedure fp_fwd_cb(e: Plv_event); cdecl; forward;
procedure fp_bkmk_cb(e: Plv_event); cdecl; forward;
procedure fp_newfolder_btn_cb(e: Plv_event); cdecl; forward;
procedure fp_newfolder_create_cb(e: Plv_event); cdecl; forward;
procedure fp_newfolder_cancel_cb(e: Plv_event); cdecl; forward;

{ ============================================================
  free_list_items / free_bkmk_items
  kfree the stringCopy'd core.strings stored in child user_data.
  ============================================================ }
procedure free_children_userdata(container: Plv_obj);
var
    n   : uint32;
    i   : uint32;
    obj : Plv_obj;
    ud  : pchar;
begin
    if container = nil then exit;
    n := lv_obj_get_child_count(container);
    if n = 0 then exit;
    for i := 0 to n - 1 do begin
        obj := lv_obj_get_child(container, sint32(i));
        if obj = nil then continue;
        ud := pchar(lv_obj_get_user_data(obj));
        if ud <> nil then kfree(void(ud));
    end;
end;

{ ============================================================
  History helpers
  ============================================================ }

{ Push a new path. Discards any forward history beyond hist_pos.
  Caps at HIST_MAX by dropping the oldest entry. }
procedure push_history(p: PPicker; path: pchar);
var
    i: sint32;
begin
    { Trim forward entries }
    for i := p^.hist_pos + 1 to p^.hist_len - 1 do
        if p^.history[i] <> nil then begin
            kfree(void(p^.history[i]));
            p^.history[i] := nil;
        end;
    p^.hist_len := p^.hist_pos + 1;

    { Drop oldest when full }
    if p^.hist_len = HIST_MAX then begin
        if p^.history[0] <> nil then kfree(void(p^.history[0]));
        for i := 0 to HIST_MAX - 2 do
            p^.history[i] := p^.history[i + 1];
        p^.history[HIST_MAX - 1] := nil;
        p^.hist_len := HIST_MAX - 1;
        p^.hist_pos := HIST_MAX - 2;
    end;

    p^.history[p^.hist_len] := stringCopy(path);
    p^.hist_len := p^.hist_len + 1;
    p^.hist_pos := p^.hist_len - 1;
end;

{ Sync back/fwd button enabled state with history position }
procedure update_nav_btns(p: PPicker);
begin
    if p^.back_btn <> nil then begin
        if p^.hist_pos > 0 then begin
            lv_obj_add_flag(p^.back_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(p^.back_btn, LV_OPA_COVER, 0);
        end else begin
            lv_obj_remove_flag(p^.back_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(p^.back_btn, 80, 0);
        end;
    end;
    if p^.fwd_btn <> nil then begin
        if p^.hist_pos < p^.hist_len - 1 then begin
            lv_obj_add_flag(p^.fwd_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(p^.fwd_btn, LV_OPA_COVER, 0);
        end else begin
            lv_obj_remove_flag(p^.fwd_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(p^.fwd_btn, 80, 0);
        end;
    end;
end;

{ ============================================================
  navigate_to
  Central navigation point — updates cur_dir, pushes history,
  resets confirm state, schedules refresh.
  ============================================================ }
procedure navigate_to(p: PPicker; newDir: pchar);
begin
    push_history(p, newDir);
    if p^.cur_dir <> nil then kfree(void(p^.cur_dir));
    p^.cur_dir      := stringCopy(newDir);
    p^.confirm_pending := false;
    update_nav_btns(p);
    schedule_refresh(p);
end;

{ ============================================================
  picker_close
  Free all state, destroy UI, fire callback.
  ============================================================ }
procedure picker_close(p: PPicker; sel_path: pchar);
var
    cb       : TPickerCallback;
    userdata : pointer;
    backdrop : Plv_obj;
    i        : sint32;
begin
    cb       := p^.cb;
    userdata := p^.userdata;
    backdrop := p^.backdrop;
    free_children_userdata(p^.file_list);
    free_children_userdata(p^.bkmk_panel);
    if p^.cur_dir <> nil then kfree(void(p^.cur_dir));
    for i := 0 to p^.hist_len - 1 do
        if p^.history[i] <> nil then kfree(void(p^.history[i]));
    kfree(void(p));
    lv_obj_delete(backdrop);
    if cb <> nil then cb(sel_path, userdata);
end;

{ ============================================================
  fmtFileSize — returns a kalloc'd human-readable size string.
  Caller must kfree the result.
  ============================================================ }
function fmtFileSize(sz: uint32): pchar;
var
    whole, frac     : uint32;
    s1, s2, s3, res : pchar;
begin
    if sz < 1024 then begin
        s1  := intToString(sz);
        res := stringConcat(s1, ' B');
        kfree(void(s1));
    end else if sz < uint32(1024 * 1024) then begin
        whole := sz div 1024;
        frac  := (sz mod 1024) * 10 div 1024;
        s1  := intToString(whole);
        s2  := stringConcat(s1, '.');         kfree(void(s1));
        s3  := intToString(frac);
        s1  := stringConcat(s2, s3);          kfree(void(s2)); kfree(void(s3));
        res := stringConcat(s1, ' KB');       kfree(void(s1));
    end else begin
        whole := sz div (1024 * 1024);
        frac  := (sz mod (1024 * 1024)) * 10 div (1024 * 1024);
        s1  := intToString(whole);
        s2  := stringConcat(s1, '.');         kfree(void(s1));
        s3  := intToString(frac);
        s1  := stringConcat(s2, s3);          kfree(void(s2)); kfree(void(s3));
        res := stringConcat(s1, ' MB');       kfree(void(s1));
    end;
    fmtFileSize := res;
end;

{ ============================================================
  matchesFilter
  Returns true when name ends with the filter extension, or
  when filter is nil (show everything).
  ============================================================ }
function matchesFilter(name: pchar; fltr: pchar): boolean;
var
    nlen, flen, i: uint32;
begin
    matchesFilter := true;
    if fltr = nil then exit;
    nlen := stringSize(name);
    flen := stringSize(fltr);
    if flen = 0 then exit;
    if nlen < flen then begin matchesFilter := false; exit; end;
    for i := 0 to flen - 1 do
        if name[nlen - flen + i] <> fltr[i] then begin
            matchesFilter := false;
            exit;
        end;
end;

{ ============================================================
  strLess — case-sensitive alphabetical comparison for sort
  ============================================================ }
function strLess(a, b: pchar): boolean;
var
    i: uint32;
begin
    strLess := false;
    if (a = nil) or (b = nil) then exit;
    i := 0;
    while (a[i] <> #0) and (b[i] <> #0) do begin
        if ord(a[i]) < ord(b[i]) then begin strLess := true; exit; end;
        if ord(a[i]) > ord(b[i]) then exit;
        i := i + 1;
    end;
    strLess := (a[i] = #0) and (b[i] <> #0);
end;

{ Simple insertion sort on a pchar array of length n }
procedure sortNames(var arr: array of pchar; n: uint32);
var
    i, j : uint32;
    tmp  : pchar;
begin
    if n < 2 then exit;
    for i := 1 to n - 1 do begin
        tmp := arr[i];
        j   := i;
        while (j > 0) and strLess(tmp, arr[j - 1]) do begin
            arr[j] := arr[j - 1];
            j := j - 1;
        end;
        arr[j] := tmp;
    end;
end;

{ Insertion sort on name array, swapping a parallel size array in lockstep }
procedure sortNamesWithSizes(var names: array of pchar; var sizes: array of uint32; n: uint32);
var
    i, j  : uint32;
    tmpN  : pchar;
    tmpS  : uint32;
begin
    if n < 2 then exit;
    for i := 1 to n - 1 do begin
        tmpN := names[i];
        tmpS := sizes[i];
        j    := i;
        while (j > 0) and strLess(tmpN, names[j - 1]) do begin
            names[j] := names[j - 1];
            sizes[j] := sizes[j - 1];
            j := j - 1;
        end;
        names[j] := tmpN;
        sizes[j] := tmpS;
    end;
end;

{ ============================================================
  fp_collect_cb
  core.ds.hashmap.forEach callback: classifies each VFS entry as dir or file
  and appends to the appropriate name array in the context.
  ============================================================ }
procedure fp_collect_cb(key: pchar; data: void; ud: void);
var
    ctx : PFPCollectCtx;
    obj : PVFSObject;
begin
    ctx := PFPCollectCtx(ud);
    obj := PVFSObject(data);
    if (ctx = nil) or (obj = nil) then exit;
    case obj^.ObjectType of
        otVDIRECTORY, otDRIVE, otDIRECTORY, otMOUNT, otSYMLINK:
            if ctx^.dir_count < ENTRY_MAX then begin
                ctx^.dir_names^[ctx^.dir_count] := key;
                ctx^.dir_count := ctx^.dir_count + 1;
            end;
        otFILE, otVFILE:
            if matchesFilter(key, ctx^.filter) then
                if ctx^.file_count < ENTRY_MAX then begin
                    ctx^.file_names^[ctx^.file_count] := key;
                    ctx^.file_sizes^[ctx^.file_count] := obj^.FileSize;
                    ctx^.file_count := ctx^.file_count + 1;
                end;
    end;
end;

{ ============================================================
  do_refresh
  Repopulate file_list for p^.cur_dir.
  Dirs collected and sorted first, then files (filtered + sorted).
  Each row is a flex-row button: [name, flex_grow] [size/type, 70px].
  ============================================================ }
procedure do_refresh(p: PPicker);
var
    Map        : PHashMap;
    ctx        : TFPCollectCtx;
    dir_names  : PNameBuf;   { heap-alloc'd to avoid blowing the core.version stack }
    file_names : PNameBuf;
    file_sizes : PSizeBuf;
    dir_count  : uint32;
    file_count : uint32;
    i          : uint32;
    row, name_lbl, size_lbl : Plv_obj;
    sep        : pchar;
    copy       : pchar;
    szStr      : pchar;
    s1, s2, s3 : pchar;
begin
    debug.tracer.push_trace('filepicker.do_refresh');
    io.syslog.logln('FPCIK', 'do_refresh: enter');
    if p^.file_list = nil then begin
        io.syslog.logln('FPCIK', 'do_refresh: file_list nil - exit');
        debug.tracer.pop_trace; exit;
    end;

    io.syslog.logln('FPCIK', 'do_refresh: kalloc name bufs');
    dir_names  := PNameBuf(kalloc(sizeof(TNameBuf)));
    file_names := PNameBuf(kalloc(sizeof(TNameBuf)));
    file_sizes := PSizeBuf(kalloc(sizeof(TSizeBuf)));
    memset(uint32(dir_names),  0, sizeof(TNameBuf));
    memset(uint32(file_names), 0, sizeof(TNameBuf));
    memset(uint32(file_sizes), 0, sizeof(TSizeBuf));

    { Sync path bar }
    if p^.path_bar <> nil then
        lv_textarea_set_text(p^.path_bar, p^.cur_dir);

    { Release old entries }
    free_children_userdata(p^.file_list);
    lv_obj_clean(p^.file_list);

    io.syslog.logln('FPCIK', 'do_refresh: calling GetDirectoryListingFrom');
    io.syslog.logln('FPCIK', p^.cur_dir);
    Map := driver.storage.vfs.GetDirectoryListingFrom(p^.cur_dir, '/');
    io.syslog.logln('FPCIK', 'do_refresh: GetDirectoryListingFrom returned');
    if Map = nil then begin
        io.syslog.logln('FPCIK', 'do_refresh: map nil - bad dir');
        if p^.status_label <> nil then
            lv_label_set_text(p^.status_label, 'Could not read directory');
        kfree(void(dir_names));
        kfree(void(file_names));
        kfree(void(file_sizes));
        debug.tracer.pop_trace;
        exit;
    end;
    if Map^.Table = nil then begin
        io.syslog.logln('FPCIK', 'do_refresh: map table nil - corrupt map');
        driver.storage.vfs.FreeDirectoryListing(Map);
        kfree(void(dir_names));
        kfree(void(file_names));
        kfree(void(file_sizes));
        debug.tracer.pop_trace;
        exit;
    end;
    io.syslog.logln('FPCIK', 'do_refresh: map ok, collecting entries');

    ctx.dir_names  := dir_names;
    ctx.file_names := file_names;
    ctx.file_sizes := file_sizes;
    ctx.dir_count  := 0;
    ctx.file_count := 0;
    ctx.filter     := p^.filter;
    core.ds.hashmap.forEach(Map, @fp_collect_cb, void(@ctx));
    dir_count  := ctx.dir_count;
    file_count := ctx.file_count;

    io.syslog.logln('FPCIK', 'do_refresh: collection done, sorting');

    { --- Sort both collections alphabetically --- }
    if dir_count  > 0 then sortNames(dir_names^,  dir_count);
    if file_count > 0 then sortNamesWithSizes(file_names^, file_sizes^, file_count);

    { --- Build directory rows --- }
    if dir_count > 0 then
    for i := 0 to dir_count - 1 do begin
        { Full path only needed for user_data (nav); no size call needed }
        row := lv_obj_create(p^.file_list);
        lv_obj_remove_style_all(row);
        lv_obj_set_size(row, lv_pct(100), 30);
        lv_obj_set_style_bg_color(row, lv_color_make(38, 42, 56), 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(row, lv_color_make(50, 55, 72), LV_STATE_PRESSED);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, LV_STATE_PRESSED);
        lv_obj_set_style_pad_left(row, 8, 0);
        lv_obj_set_style_pad_right(row, 8, 0);
        lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);

        { Name label with folder indicator }
        name_lbl := lv_label_create(row);
        sep      := stringConcat('[/] ', dir_names^[i]);
        lv_label_set_text(name_lbl, sep);
        kfree(void(sep));
        lv_obj_set_flex_grow(name_lbl, 1);
        lv_obj_set_style_text_color(name_lbl, lv_color_make(200, 215, 240), 0);
        lv_obj_set_style_text_font(name_lbl, @lv_font_montserrat_14, 0);

        { Type indicator }
        size_lbl := lv_label_create(row);
        lv_label_set_text(size_lbl, '<DIR>');
        lv_obj_set_width(size_lbl, 70);
        lv_obj_set_style_text_color(size_lbl, lv_color_make(100, 160, 255), 0);
        lv_obj_set_style_text_font(size_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_style_text_align(size_lbl, LV_TEXT_ALIGN_RIGHT, 0);

        copy := stringCopy(dir_names^[i]);
        lv_obj_set_user_data(row, copy);
        lv_obj_add_event_cb(row, @fp_dir_cb, LV_EVENT_CLICKED, p);
    end;

    { --- Build file rows --- }
    if file_count > 0 then
    for i := 0 to file_count - 1 do begin
        row := lv_obj_create(p^.file_list);
        lv_obj_remove_style_all(row);
        lv_obj_set_size(row, lv_pct(100), 30);
        lv_obj_set_style_bg_color(row, lv_color_make(28, 31, 44), 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(row, lv_color_make(42, 46, 62), LV_STATE_PRESSED);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, LV_STATE_PRESSED);
        lv_obj_set_style_pad_left(row, 8, 0);
        lv_obj_set_style_pad_right(row, 8, 0);
        lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);

        name_lbl := lv_label_create(row);
        lv_label_set_text(name_lbl, file_names^[i]);
        lv_obj_set_flex_grow(name_lbl, 1);
        lv_obj_set_style_text_color(name_lbl, lv_color_make(210, 215, 230), 0);
        lv_obj_set_style_text_font(name_lbl, @lv_font_montserrat_14, 0);

        { File size column: use metadata from directory listing }
        size_lbl := lv_label_create(row);
        szStr := fmtFileSize(file_sizes^[i]);
        lv_label_set_text(size_lbl, szStr);
        kfree(void(szStr));
        lv_obj_set_width(size_lbl, 70);
        lv_obj_set_style_text_color(size_lbl, lv_color_make(100, 110, 130), 0);
        lv_obj_set_style_text_font(size_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_style_text_align(size_lbl, LV_TEXT_ALIGN_RIGHT, 0);

        copy := stringCopy(file_names^[i]);
        lv_obj_set_user_data(row, copy);
        lv_obj_add_event_cb(row, @fp_file_cb, LV_EVENT_CLICKED, p);
    end;

    io.syslog.logln('FPCIK', 'do_refresh: building UI rows done, freeing map');
    driver.storage.vfs.FreeDirectoryListing(Map);

    kfree(void(dir_names));
    kfree(void(file_names));
    kfree(void(file_sizes));

    { Update status label: "X dirs, Y files" }
    if p^.status_label <> nil then begin
        s1 := intToString(dir_count);
        s2 := stringConcat(s1, ' dirs, ');   kfree(void(s1));
        s1 := intToString(file_count);
        s3 := stringConcat(s2, s1);          kfree(void(s1)); kfree(void(s2));
        s1 := stringConcat(s3, ' files');    kfree(void(s3));
        lv_label_set_text(p^.status_label, s1);
        lv_obj_set_style_text_color(p^.status_label, lv_color_make(140, 150, 170), 0);
        kfree(void(s1));
    end;

    io.syslog.logln('FPCIK', 'do_refresh: exit');
    debug.tracer.pop_trace;
end;

{ ============================================================
  schedule_refresh / fp_refresh_timer_cb
  Defers do_refresh via a 1 ms LVGL one-shot timer so VFS I/O
  runs outside the event-dispatch stack.
  ============================================================ }
procedure fp_refresh_timer_cb(tmr: Plv_timer); cdecl;
var
    p: PPicker;
begin
    io.syslog.logln('FPCIK', 'fp_refresh_timer_cb: fired');
    p := PPicker(lv_timer_get_user_data(tmr));
    lv_timer_delete(tmr);
    if p = nil then begin
        io.syslog.logln('FPCIK', 'fp_refresh_timer_cb: p nil');
        exit;
    end;
    p^.pending_refresh := false;
    do_refresh(p);
end;

procedure schedule_refresh(p: PPicker);
var
    tmr: Plv_timer;
begin
    if p^.pending_refresh then exit;
    p^.pending_refresh := true;
    tmr := lv_timer_create(@fp_refresh_timer_cb, 1, p);
    lv_timer_set_repeat_count(tmr, 1);
end;

{ ============================================================
  Navigation event callbacks
  ============================================================ }

procedure fp_dir_cb(e: Plv_event); cdecl;
var
    p      : PPicker;
    target : Plv_obj;
    name   : pchar;
    sep, np: pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p      := PPicker(lv_event_get_user_data(e));
    target := lv_event_get_current_target_obj(e);
    name   := pchar(lv_obj_get_user_data(target));
    if (p = nil) or (name = nil) then exit;
    if p^.pending_refresh then exit;

    if stringEquals(p^.cur_dir, '/') then
        np := stringConcat('/', name)
    else begin
        sep := stringConcat(p^.cur_dir, '/');
        np  := stringConcat(sep, name);
        kfree(void(sep));
    end;
    navigate_to(p, np);
    kfree(void(np));
end;

procedure fp_file_cb(e: Plv_event); cdecl;
var
    p      : PPicker;
    target : Plv_obj;
    name   : pchar;
    sep, fp: pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p      := PPicker(lv_event_get_user_data(e));
    target := lv_event_get_current_target_obj(e);
    name   := pchar(lv_obj_get_user_data(target));
    if (p = nil) or (name = nil) then exit;
    if p^.pending_refresh then exit;

    if stringEquals(p^.cur_dir, '/') then
        fp := stringConcat('/', name)
    else begin
        sep := stringConcat(p^.cur_dir, '/');
        fp  := stringConcat(sep, name);
        kfree(void(sep));
    end;

    if p^.is_save then begin
        { Save mode: populate fname_bar for review; reset overwrite guard }
        if p^.fname_bar <> nil then
            lv_textarea_set_text(p^.fname_bar, name);
        p^.confirm_pending := false;
        if p^.status_label <> nil then begin
            lv_label_set_text(p^.status_label, '');
        end;
        kfree(void(fp));
    end else begin
        { Open mode: auto-confirm }
        picker_close(p, fp);
        { fp now owned by callback — do NOT kfree }
    end;
end;

procedure fp_up_cb(e: Plv_event); cdecl;
var
    p       : PPicker;
    dir     : pchar;
    len, i  : uint32;
    lastSep : sint32;
    newDir  : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    if p^.pending_refresh then exit;
    if stringEquals(p^.cur_dir, '/') then exit;

    dir     := p^.cur_dir;
    len     := stringSize(dir);
    lastSep := -1;
    for i := 0 to len - 1 do
        if dir[i] = '/' then lastSep := sint32(i);
    if lastSep <= 0 then
        newDir := stringCopy('/')
    else
        newDir := stringSub(dir, 0, uint32(lastSep));
    navigate_to(p, newDir);
    kfree(void(newDir));
end;

procedure fp_back_cb(e: Plv_event); cdecl;
var
    p      : PPicker;
    newDir : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    if p^.pending_refresh then exit;
    if p^.hist_pos <= 0 then exit;

    p^.hist_pos := p^.hist_pos - 1;
    newDir := p^.history[p^.hist_pos];
    if p^.cur_dir <> nil then kfree(void(p^.cur_dir));
    p^.cur_dir         := stringCopy(newDir);
    p^.confirm_pending := false;
    update_nav_btns(p);
    schedule_refresh(p);
end;

procedure fp_fwd_cb(e: Plv_event); cdecl;
var
    p      : PPicker;
    newDir : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    if p^.pending_refresh then exit;
    if p^.hist_pos >= p^.hist_len - 1 then exit;

    p^.hist_pos := p^.hist_pos + 1;
    newDir := p^.history[p^.hist_pos];
    if p^.cur_dir <> nil then kfree(void(p^.cur_dir));
    p^.cur_dir         := stringCopy(newDir);
    p^.confirm_pending := false;
    update_nav_btns(p);
    schedule_refresh(p);
end;

procedure fp_bkmk_cb(e: Plv_event); cdecl;
var
    p      : PPicker;
    target : Plv_obj;
    path   : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p      := PPicker(lv_event_get_user_data(e));
    target := lv_event_get_current_target_obj(e);
    path   := pchar(lv_obj_get_user_data(target));
    if (p = nil) or (path = nil) then exit;
    if p^.pending_refresh then exit;
    navigate_to(p, path);
end;

{ ============================================================
  Confirm / Cancel callbacks
  ============================================================ }

procedure fp_confirm_cb(e: Plv_event); cdecl;
var
    p    : PPicker;
    path : pchar;
    name : pchar;
    sep  : pchar;
    s1   : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    if p^.pending_refresh then exit;

    if p^.is_save then begin
        if p^.fname_bar <> nil then
            name := lv_textarea_get_text(p^.fname_bar)
        else
            name := lv_textarea_get_text(p^.path_bar);
        if (name = nil) or (stringSize(name) = 0) then exit;

        if name[0] = '/' then
            path := stringCopy(name)
        else if stringEquals(p^.cur_dir, '/') then
            path := stringConcat('/', name)
        else begin
            sep  := stringConcat(p^.cur_dir, '/');
            path := stringConcat(sep, name);
            kfree(void(sep));
        end;

        { Overwrite guard: warn on first click, confirm on second }
        if (not p^.confirm_pending) and
           (driver.storage.vfs.PathValid(path) = pvFile) then begin
            p^.confirm_pending := true;
            if p^.status_label <> nil then begin
                s1 := stringConcat(name, ' exists — click Save again to overwrite');
                lv_label_set_text(p^.status_label, s1);
                lv_obj_set_style_text_color(p^.status_label,
                                            lv_color_make(220, 160, 50), 0);
                kfree(void(s1));
            end;
            kfree(void(path));
            exit;
        end;

        picker_close(p, path);
        { path now owned by callback }
    end else begin
        { Open mode: accept whatever is in the path_bar }
        name := lv_textarea_get_text(p^.path_bar);
        if (name = nil) or (stringSize(name) = 0) then exit;
        path := stringCopy(name);
        picker_close(p, path);
    end;
end;

procedure fp_cancel_cb(e: Plv_event); cdecl;
var
    p: PPicker;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    if p^.pending_refresh then exit;
    picker_close(p, nil);
end;

{ ============================================================
  New Folder callbacks
  ============================================================ }

procedure fp_newfolder_btn_cb(e: Plv_event); cdecl;
var
    p: PPicker;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    lv_textarea_set_text(p^.newfolder_bar, '');
    lv_obj_add_flag(p^.action_row,    LV_OBJ_FLAG_HIDDEN);
    lv_obj_remove_flag(p^.newfolder_row, LV_OBJ_FLAG_HIDDEN);
end;

procedure fp_newfolder_create_cb(e: Plv_event); cdecl;
var
    p        : PPicker;
    fname    : pchar;
    sep, fp  : pchar;
    err      : TError;
    s1       : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;

    fname := lv_textarea_get_text(p^.newfolder_bar);
    if (fname = nil) or (stringSize(fname) = 0) then exit;

    if stringEquals(p^.cur_dir, '/') then
        fp := stringConcat('/', fname)
    else begin
        sep := stringConcat(p^.cur_dir, '/');
        fp  := stringConcat(sep, fname);
        kfree(void(sep));
    end;

    err := driver.storage.vfs.newVirtualDirectory(fp);
    kfree(void(fp));

    { Restore action row regardless of outcome }
    lv_obj_remove_flag(p^.action_row,  LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(p^.newfolder_row,  LV_OBJ_FLAG_HIDDEN);

    if err = eNone then begin
        { Refresh to show the new folder }
        schedule_refresh(p);
    end else begin
        if p^.status_label <> nil then begin
            s1 := stringConcat('Could not create folder: ', fname);
            lv_label_set_text(p^.status_label, s1);
            lv_obj_set_style_text_color(p^.status_label,
                                        lv_color_make(200, 80, 80), 0);
            kfree(void(s1));
        end;
    end;
end;

procedure fp_newfolder_cancel_cb(e: Plv_event); cdecl;
var
    p: PPicker;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    lv_obj_remove_flag(p^.action_row,  LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(p^.newfolder_row,  LV_OBJ_FLAG_HIDDEN);
end;

{ ============================================================
  make_btn — small helper for action-row buttons
  Returns the created button object.
  ============================================================ }
function make_btn(parent: Plv_obj; text: pchar; w: sint32;
                  br, bg, bb: uint8;
                  cb: lv_event_cb_t; ud: pointer): Plv_obj;
var
    btn, lbl: Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, w, 30);
    lv_obj_set_style_bg_color(btn, lv_color_make(br, bg, bb), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, 4, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, lv_color_make(220, 225, 240), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_add_event_cb(btn, cb, LV_EVENT_CLICKED, ud);
    make_btn := btn;
end;

{ ============================================================
  add_bookmark — helper to add one entry to the bookmarks panel
  ============================================================ }
procedure add_bookmark(parent: Plv_obj; name: pchar; path: pchar; p: PPicker);
var
    btn, lbl : Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, lv_pct(100), 30);
    lv_obj_set_style_bg_color(btn, lv_color_make(38, 42, 56), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(btn, lv_color_make(50, 55, 72), LV_STATE_PRESSED);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_STATE_PRESSED);
    lv_obj_set_style_pad_left(btn, 10, 0);
    lv_obj_set_style_radius(btn, 0, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, name);
    lv_obj_set_style_text_color(lbl, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_user_data(btn, stringCopy(path));
    lv_obj_add_event_cb(btn, @fp_bkmk_cb, LV_EVENT_CLICKED, p);
end;

{ ============================================================
  make_picker — allocate state, build full picker UI
  ============================================================ }
procedure make_picker(title        : pchar;
                      start_dir    : pchar;
                      is_save      : boolean;
                      initial_name : pchar;
                      filter       : pchar;
                      cb           : TPickerCallback;
                      userdata     : pointer);
var
    p             : PPicker;
    scr           : Plv_obj;
    backdrop      : Plv_obj;
    panel         : Plv_obj;
    title_lbl     : Plv_obj;
    nav_row       : Plv_obj;
    body_row      : Plv_obj;
    bkmk_sep      : Plv_obj;
    bkmk_hdr      : Plv_obj;
    bkmk_panel    : Plv_obj;
    file_list     : Plv_obj;
    status_row    : Plv_obj;
    fname_bar     : Plv_obj;
    action_row    : Plv_obj;
    newfolder_row : Plv_obj;
    newfolder_bar : Plv_obj;
    spacer        : Plv_obj;
    conf_text     : pchar;
    back_btn      : Plv_obj;
    fwd_btn       : Plv_obj;
begin
    debug.tracer.push_trace('filepicker.make_picker');
    io.syslog.logln('FPCIK', 'make_picker: enter');

    p := PPicker(kalloc(sizeof(TPicker)));
    memset(uint32(p), 0, sizeof(TPicker));
    p^.cb         := cb;
    p^.userdata   := userdata;
    p^.is_save    := is_save;
    p^.filter     := filter;
    p^.hist_pos   := -1;
    p^.hist_len   := 0;
    if (start_dir <> nil) and (stringSize(start_dir) > 0) then
        p^.cur_dir := stringCopy(start_dir)
    else
        p^.cur_dir := stringCopy('/disk');

    { Seed history with start_dir so Back is immediately available
      after the first navigation }
    push_history(p, p^.cur_dir);

    scr := lv_screen_active;

    { ====== Full-screen backdrop ====== }
    backdrop := lv_obj_create(scr);
    lv_obj_remove_style_all(backdrop);
    lv_obj_set_size(backdrop, lv_pct(100), lv_pct(100));
    lv_obj_set_pos(backdrop, 0, 0);
    lv_obj_set_style_bg_color(backdrop, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_bg_opa(backdrop, 140, 0);
    lv_obj_set_style_pad_all(backdrop, 0, 0);
    lv_obj_remove_flag(backdrop, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_move_foreground(backdrop);
    p^.backdrop := backdrop;

    { ====== Centered panel ====== }
    panel := lv_obj_create(backdrop);
    lv_obj_remove_style_all(panel);
    lv_obj_set_size(panel, PANEL_W, PANEL_H);
    lv_obj_align(panel, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_bg_color(panel, lv_color_make(22, 25, 36), 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(panel, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_width(panel, 1, 0);
    lv_obj_set_style_radius(panel, 6, 0);
    lv_obj_set_style_pad_all(panel, 10, 0);
    lv_obj_set_style_pad_row(panel, 6, 0);
    lv_obj_set_style_layout(panel, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);

    { ---- Title ---- }
    title_lbl := lv_label_create(panel);
    lv_label_set_text(title_lbl, title);
    lv_obj_set_style_text_color(title_lbl, lv_color_make(100, 160, 255), 0);
    lv_obj_set_style_text_font(title_lbl, @lv_font_montserrat_14, 0);

    { ---- Navigation row: [<] [^] [>]  [path_bar...............] ---- }
    nav_row := lv_obj_create(panel);
    lv_obj_remove_style_all(nav_row);
    lv_obj_set_size(nav_row, lv_pct(100), 36);
    lv_obj_set_style_layout(nav_row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(nav_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(nav_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(nav_row, 4, 0);
    lv_obj_remove_flag(nav_row, LV_OBJ_FLAG_SCROLLABLE);

    back_btn := make_btn(nav_row, '<', 30, 45, 50, 68, @fp_back_cb, p);
    make_btn(nav_row,             '^', 30, 45, 50, 68, @fp_up_cb,   p);
    fwd_btn  := make_btn(nav_row, '>', 30, 45, 50, 68, @fp_fwd_cb,  p);

    p^.back_btn := back_btn;
    p^.fwd_btn  := fwd_btn;
    { Both start disabled — no back/fwd history yet }
    lv_obj_remove_flag(back_btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_opa(back_btn, 80, 0);
    lv_obj_remove_flag(fwd_btn,  LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_opa(fwd_btn, 80, 0);

    { Path bar — 4th flex child of nav_row, takes remaining width }
    p^.path_bar := lv_textarea_create(nav_row);
    lv_obj_set_size(p^.path_bar, 0, 30);
    lv_obj_set_flex_grow(p^.path_bar, 1);
    lv_textarea_set_one_line(p^.path_bar, true);
    lv_textarea_set_text(p^.path_bar, p^.cur_dir);
    lv_textarea_set_placeholder_text(p^.path_bar, '/disk');
    lv_obj_set_style_bg_color(p^.path_bar, lv_color_make(35, 38, 55), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(p^.path_bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_text_color(p^.path_bar, lv_color_make(200, 210, 240), LV_PART_MAIN);
    lv_obj_set_style_text_font(p^.path_bar, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_border_color(p^.path_bar, lv_color_make(55, 70, 110), LV_PART_MAIN);
    lv_obj_set_style_border_width(p^.path_bar, 1, LV_PART_MAIN);
    lv_obj_set_style_radius(p^.path_bar, 4, LV_PART_MAIN);
    lv_group_add_obj(lvgl_get_kb_group, p^.path_bar);

    { ---- Body row: [bookmarks 120px] | [file list, flex_grow] ---- }
    body_row := lv_obj_create(panel);
    lv_obj_remove_style_all(body_row);
    lv_obj_set_size(body_row, lv_pct(100), 0);
    lv_obj_set_flex_grow(body_row, 1);
    lv_obj_set_style_layout(body_row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(body_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(body_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_START);
    lv_obj_set_style_pad_column(body_row, 0, 0);
    lv_obj_remove_flag(body_row, LV_OBJ_FLAG_SCROLLABLE);

    { Bookmarks sidebar }
    bkmk_panel := lv_obj_create(body_row);
    lv_obj_remove_style_all(bkmk_panel);
    lv_obj_set_size(bkmk_panel, BKMK_W, lv_pct(100));
    lv_obj_set_style_bg_color(bkmk_panel, lv_color_make(28, 31, 40), 0);
    lv_obj_set_style_bg_opa(bkmk_panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(bkmk_panel, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_side(bkmk_panel, LV_BORDER_SIDE_RIGHT, 0);
    lv_obj_set_style_border_width(bkmk_panel, 1, 0);
    lv_obj_set_style_layout(bkmk_panel, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(bkmk_panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(bkmk_panel, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_START);
    lv_obj_set_style_pad_all(bkmk_panel, 0, 0);
    lv_obj_set_style_pad_row(bkmk_panel, 0, 0);
    lv_obj_remove_flag(bkmk_panel, LV_OBJ_FLAG_SCROLLABLE);
    p^.bkmk_panel := bkmk_panel;

    { Bookmarks header label }
    bkmk_hdr := lv_label_create(bkmk_panel);
    lv_label_set_text(bkmk_hdr, 'Locations');
    lv_obj_set_style_text_color(bkmk_hdr, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(bkmk_hdr, @lv_font_montserrat_14, 0);
    lv_obj_set_style_pad_top(bkmk_hdr, 6, 0);
    lv_obj_set_style_pad_left(bkmk_hdr, 10, 0);
    lv_obj_set_style_pad_bottom(bkmk_hdr, 4, 0);

    bkmk_sep := lv_obj_create(bkmk_panel);
    lv_obj_remove_style_all(bkmk_sep);
    lv_obj_set_size(bkmk_sep, lv_pct(100), 1);
    lv_obj_set_style_bg_color(bkmk_sep, lv_color_make(55, 60, 78), 0);
    lv_obj_set_style_bg_opa(bkmk_sep, LV_OPA_COVER, 0);

    add_bookmark(bkmk_panel, 'Root', '/',     p);
    add_bookmark(bkmk_panel, 'Disk', '/disk', p);
    add_bookmark(bkmk_panel, 'Boot', '/boot', p);

    { File list — takes remaining width, scrollable }
    file_list := lv_obj_create(body_row);
    lv_obj_remove_style_all(file_list);
    lv_obj_set_size(file_list, 0, lv_pct(100));
    lv_obj_set_flex_grow(file_list, 1);
    lv_obj_set_style_bg_color(file_list, lv_color_make(28, 31, 44), 0);
    lv_obj_set_style_bg_opa(file_list, LV_OPA_COVER, 0);
    lv_obj_set_style_layout(file_list, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(file_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(file_list, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_START);
    lv_obj_set_style_pad_all(file_list, 0, 0);
    lv_obj_set_style_pad_row(file_list, 1, 0);
    lv_obj_set_scroll_dir(file_list, LV_DIR_VER);
    p^.file_list := file_list;

    { ---- Status strip ---- }
    status_row := lv_obj_create(panel);
    lv_obj_remove_style_all(status_row);
    lv_obj_set_size(status_row, lv_pct(100), 20);
    lv_obj_set_style_pad_left(status_row, 4, 0);
    lv_obj_remove_flag(status_row, LV_OBJ_FLAG_SCROLLABLE);
    p^.status_label := lv_label_create(status_row);
    lv_label_set_text(p^.status_label, '');
    lv_obj_set_style_text_color(p^.status_label, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(p^.status_label, @lv_font_montserrat_14, 0);

    { ---- Filename bar (save mode only) ---- }
    fname_bar := nil;
    if is_save then begin
        fname_bar := lv_textarea_create(panel);
        lv_obj_set_size(fname_bar, lv_pct(100), 34);
        lv_textarea_set_one_line(fname_bar, true);
        if (initial_name <> nil) and (stringSize(initial_name) > 0) then
            lv_textarea_set_text(fname_bar, initial_name)
        else
            lv_textarea_set_text(fname_bar, '');
        lv_textarea_set_placeholder_text(fname_bar, 'filename.txt');
        lv_obj_set_style_bg_color(fname_bar, lv_color_make(28, 35, 28), LV_PART_MAIN);
        lv_obj_set_style_bg_opa(fname_bar, LV_OPA_COVER, LV_PART_MAIN);
        lv_obj_set_style_text_color(fname_bar, lv_color_make(190, 235, 190), LV_PART_MAIN);
        lv_obj_set_style_text_font(fname_bar, @lv_font_montserrat_14, LV_PART_MAIN);
        lv_obj_set_style_border_color(fname_bar, lv_color_make(55, 130, 55), LV_PART_MAIN);
        lv_obj_set_style_border_width(fname_bar, 1, LV_PART_MAIN);
        lv_obj_set_style_radius(fname_bar, 4, LV_PART_MAIN);
        lv_group_add_obj(lvgl_get_kb_group, fname_bar);
        lv_group_focus_obj(fname_bar);
    end;
    p^.fname_bar := fname_bar;

    { ---- Action row: [New Folder] <spacer> [Cancel] [Open/Save] ---- }
    action_row := lv_obj_create(panel);
    lv_obj_remove_style_all(action_row);
    lv_obj_set_size(action_row, lv_pct(100), 36);
    lv_obj_set_style_layout(action_row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(action_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(action_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(action_row, 6, 0);
    lv_obj_remove_flag(action_row, LV_OBJ_FLAG_SCROLLABLE);
    p^.action_row := action_row;

    make_btn(action_row, '+ Folder', 80, 45, 50, 68, @fp_newfolder_btn_cb, p);

    spacer := lv_obj_create(action_row);
    lv_obj_remove_style_all(spacer);
    lv_obj_set_flex_grow(spacer, 1);
    lv_obj_set_size(spacer, 0, 30);

    make_btn(action_row, 'Cancel', 72, 60, 40, 40, @fp_cancel_cb, p);

    if is_save then conf_text := 'Save'
    else            conf_text := 'Open';
    make_btn(action_row, conf_text, 72, 55, 90, 190, @fp_confirm_cb, p);

    { ---- New Folder row (hidden until '+ Folder' clicked) ---- }
    newfolder_row := lv_obj_create(panel);
    lv_obj_remove_style_all(newfolder_row);
    lv_obj_set_size(newfolder_row, lv_pct(100), 36);
    lv_obj_set_style_layout(newfolder_row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(newfolder_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(newfolder_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(newfolder_row, 6, 0);
    lv_obj_remove_flag(newfolder_row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(newfolder_row, LV_OBJ_FLAG_HIDDEN);
    p^.newfolder_row := newfolder_row;

    newfolder_bar := lv_textarea_create(newfolder_row);
    lv_obj_set_size(newfolder_bar, 0, 30);
    lv_obj_set_flex_grow(newfolder_bar, 1);
    lv_textarea_set_one_line(newfolder_bar, true);
    lv_textarea_set_text(newfolder_bar, '');
    lv_textarea_set_placeholder_text(newfolder_bar, 'New folder name');
    lv_obj_set_style_bg_color(newfolder_bar, lv_color_make(35, 38, 55), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(newfolder_bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_text_color(newfolder_bar, lv_color_make(200, 210, 240), LV_PART_MAIN);
    lv_obj_set_style_text_font(newfolder_bar, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_border_color(newfolder_bar, lv_color_make(55, 70, 110), LV_PART_MAIN);
    lv_obj_set_style_border_width(newfolder_bar, 1, LV_PART_MAIN);
    lv_obj_set_style_radius(newfolder_bar, 4, LV_PART_MAIN);
    lv_group_add_obj(lvgl_get_kb_group, newfolder_bar);
    p^.newfolder_bar := newfolder_bar;

    make_btn(newfolder_row, 'Create', 72, 55, 90, 190, @fp_newfolder_create_cb, p);
    make_btn(newfolder_row, 'x',      30, 60, 40, 40,  @fp_newfolder_cancel_cb, p);

    { Kick off first directory listing }
    io.syslog.logln('FPCIK', 'make_picker: scheduling initial refresh');
    schedule_refresh(p);

    io.syslog.logln('FPCIK', 'make_picker: exit');
    debug.tracer.pop_trace;
end;

{ ============================================================
  Public API
  ============================================================ }

procedure show_open(title     : pchar;
                    start_dir : pchar;
                    filter    : pchar;
                    cb        : TPickerCallback;
                    userdata  : pointer);
begin
    io.syslog.logln('FPCIK', 'show_open: enter');
    make_picker(title, start_dir, false, nil, filter, cb, userdata);
end;

procedure show_save(title        : pchar;
                    start_dir    : pchar;
                    initial_name : pchar;
                    filter       : pchar;
                    cb           : TPickerCallback;
                    userdata     : pointer);
begin
    io.syslog.logln('FPCIK', 'show_save: enter');
    make_picker(title, start_dir, true, initial_name, filter, cb, userdata);
end;

end.
