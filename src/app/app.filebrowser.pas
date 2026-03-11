{
    App->FileBrowser - GUI file browser / manager

    Phases 2-7: window, VFS loading, navigation, detail list with
    type column, breadcrumb bar, file operations (delete, rename,
    create folder/file), right-click context menu.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.filebrowser;

interface

procedure init();

implementation

uses
    driver.video.desktop,
    driver.video.windows,
    driver.video.lvgl,
    driver.video,
    driver.storage.vfs,
    driver.storage.types,
    driver.storage.filedispatch,
    core.ds.hashmap,
    memory.heap,
    proc.mgr,
    proc.types,
    core.strings,
    core.strings.helpers,
    core.gfx.fileicons,
    debug.tracer,
    core.util,
    arch.x86.util;

const
    WIN_W          = 800;
    WIN_H          = 600;
    TOOLBAR_H      = 36;
    STATUSBAR_H    = 24;
    ENTRY_MAX      = 256;
    HIST_MAX       = 32;
    MAX_TABS       = 8;
    MAX_BOOKMARKS  = 16;
    PATH_MAX       = 256;

    { LVGL FontAwesome symbol UTF-8 strings (from lv_symbol_def.h) }
    SYM_LEFT       = #$EF#$81#$93;  { U+F053 }
    SYM_RIGHT      = #$EF#$81#$94;  { U+F054 }
    SYM_UP         = #$EF#$81#$B7;  { U+F077 }
    SYM_REFRESH    = #$EF#$80#$A1;  { U+F021 }
    SYM_PLUS       = #$EF#$81#$A7;  { U+F067 }
    SYM_DIRECTORY  = #$EF#$81#$BB;  { U+F07B }
    SYM_FILE       = #$EF#$85#$9B;  { U+F158 }
    SYM_EDIT       = #$EF#$8C#$84;  { U+F304 }
    SYM_TRASH      = #$EF#$8B#$AD;  { U+F2ED }
    SYM_CLOSE      = #$EF#$80#$8D;  { U+F00D }
    SYM_EYE_OPEN   = #$EF#$81#$AE;  { U+F06E }
    SYM_IMAGE      = #$EF#$80#$BE;  { U+F03E }
    SYM_LIST       = #$EF#$80#$8B;  { U+F00B }
    SYM_HOME       = #$EF#$80#$95;  { U+F015 }
    SYM_DRIVE      = #$EF#$80#$9C;  { U+F01C }

type
    TViewMode = (vmDetail, vmCompact);

    { Heap-allocated name/size buffers (Lesson #11: no large stack arrays) }
    TNameBuf = array[0..ENTRY_MAX - 1] of pchar;
    PNameBuf = ^TNameBuf;
    TSizeBuf = array[0..ENTRY_MAX - 1] of uint32;
    PSizeBuf = ^TSizeBuf;

    { Collect context for hashmap forEach callback }
    PFBCollectCtx = ^TFBCollectCtx;
    TFBCollectCtx = record
        dir_names  : PNameBuf;
        file_names : PNameBuf;
        file_sizes : PSizeBuf;
        dir_count  : uint32;
        file_count : uint32;
    end;

    { Per-tab state snapshot }
    PTabSnapshot = ^TTabSnapshot;
    TTabSnapshot = record
        cur_path   : pchar;
        history    : array[0..HIST_MAX - 1] of pchar;
        hist_len   : uint32;
        hist_pos   : uint32;
        sel_path   : pchar;
        sel_is_dir : boolean;
        item_count : uint32;
        filter_text: pchar;
    end;

    PFileBrowserState = ^TFileBrowserState;
    TFileBrowserState = record
        win_id       : uint32;
        pid          : uint32;
        { Main widget pointers }
        toolbar      : Plv_obj;
        tab_bar      : Plv_obj;
        content_area : Plv_obj;
        status_bar   : Plv_obj;
        status_label : Plv_obj;
        { Navigation }
        cur_path     : pchar;
        history      : array[0..HIST_MAX - 1] of pchar;
        hist_len     : uint32;
        hist_pos     : uint32;
        { Nav buttons }
        back_btn     : Plv_obj;
        fwd_btn      : Plv_obj;
        up_btn       : Plv_obj;
        { Breadcrumb / path edit }
        breadcrumb   : Plv_obj;
        path_ta      : Plv_obj;
        path_editing : boolean;
        { Selection }
        sel_path     : pchar;   { full path of selected item (heap-alloc'd) }
        sel_is_dir   : boolean; { true if selected item is a directory }
        sel_row      : Plv_obj; { the highlighted row object }
        { File ops state }
        op_err       : TError;  { result from async ops }
        { Context menu }
        ctx_menu     : Plv_obj; { popup panel, nil when hidden }
        { Tabs }
        tabs         : array[0..MAX_TABS - 1] of PTabSnapshot;
        tab_btns     : array[0..MAX_TABS - 1] of Plv_obj;
        tab_count    : uint32;
        active_tab   : uint32;
        { View state }
        view_mode    : TViewMode;
        item_count   : uint32;
        { Bookmarks }
        body_row     : Plv_obj;
        sidebar      : Plv_obj;
        bookmarks    : array[0..MAX_BOOKMARKS - 1] of pchar;
        bm_count     : uint32;
        { Filter }
        filter_ta    : Plv_obj;
        filter_text  : pchar;
        { Type-ahead }
        ta_buf       : array[0..31] of char;
        ta_len       : uint32;
        ta_timer     : Plv_timer;
        { Preview panel }
        preview_panel  : Plv_obj;
        preview_visible: boolean;
        { Sorting }
        sort_col       : uint32;  { 0=name, 1=size, 2=type }
        sort_asc       : boolean;
        { Hidden files }
        show_hidden    : boolean;
        { Directory watch }
        watch_id       : uint32;
        watch_dirty    : boolean;
        watch_timer    : Plv_timer;
        { Async refresh pipeline }
        refresh_pending : uint32;  { 1 = fb_entry should load data }
        rd_dir_names    : PNameBuf;
        rd_file_names   : PNameBuf;
        rd_file_sizes   : PSizeBuf;
        rd_dir_count    : uint32;
        rd_file_count   : uint32;
        rd_ready        : uint32;  { 1 = data ready for UI build }
        rd_failed       : boolean; { true = VFS returned nil }
        refresh_poll    : Plv_timer; { 50ms poll timer }
        { Worker VFS operations (mkdir, rename) }
        wop_pending     : uint32;  { 0=none, 1=mkdir, 2=rename }
        wop_path1       : pchar;   { path arg 1 }
        wop_path2       : pchar;   { path arg 2 (rename new-name) }
        wop_done        : uint32;  { 1 = op finished }
        wop_result      : TError;  { result from op }
        wop_kind        : uint32;  { copy of pending kind for UI callback }
        { File dispatch (open file via handler) }
        dispatch_pending : uint32; { 1 = fb_entry should dispatch }
        dispatch_path    : pchar;  { abs path to dispatch }
        dispatch_done    : uint32; { 1 = dispatch finished }
        dispatch_result  : uint32; { PID returned by dispatch, 0 = no handler }
    end;

var
    g_win_id : uint32;
    g_state  : PFileBrowserState;

{ Forward declarations }
procedure fb_entry(ctx: PProcessContext); forward;
procedure launch; forward;
procedure onClose(wid: uint32); forward;
procedure onResize(wid: uint32; new_w, new_h: sint32); forward;
procedure freeState(state: PFileBrowserState); forward;
procedure do_refresh_load(state: PFileBrowserState); forward;
procedure do_refresh_build(state: PFileBrowserState); forward;
procedure schedule_refresh(state: PFileBrowserState); forward;
procedure fb_refresh_poll_cb(tmr: Plv_timer); cdecl; forward;
procedure fb_collect_cb(key: pchar; data: void; ud: void); forward;
procedure do_refresh(state: PFileBrowserState); forward;
procedure navigate_to(state: PFileBrowserState; newDir: pchar); forward;
procedure push_history(state: PFileBrowserState; path: pchar); forward;
procedure update_nav_btns(state: PFileBrowserState); forward;
procedure update_status_bar(state: PFileBrowserState); forward;
procedure free_children_userdata(container: Plv_obj); forward;
procedure fb_dir_cb(e: Plv_event); cdecl; forward;
procedure fb_file_cb(e: Plv_event); cdecl; forward;
procedure fb_back_cb(e: Plv_event); cdecl; forward;
procedure fb_fwd_cb(e: Plv_event); cdecl; forward;
procedure fb_up_cb(e: Plv_event); cdecl; forward;
procedure fb_refresh_cb(e: Plv_event); cdecl; forward;
procedure build_breadcrumbs(state: PFileBrowserState); forward;
procedure fb_crumb_cb(e: Plv_event); cdecl; forward;
procedure fb_crumb_area_cb(e: Plv_event); cdecl; forward;
procedure fb_path_ta_cb(e: Plv_event); cdecl; forward;
{ Phase 6 — file operations }
procedure fb_mbox_close_cb(e: Plv_event); cdecl; forward;
procedure select_item(state: PFileBrowserState; row: Plv_obj;
                      path: pchar; isDir: boolean); forward;
procedure clear_selection(state: PFileBrowserState); forward;
procedure fb_delete_cb(e: Plv_event); cdecl; forward;
procedure fb_delete_confirm_cb(e: Plv_event); cdecl; forward;
procedure fb_delete_done(error: TError; userdata: pointer); forward;
procedure fb_delete_done_timer(tmr: Plv_timer); cdecl; forward;
procedure fb_newfolder_cb(e: Plv_event); cdecl; forward;
procedure fb_newfolder_ok_cb(e: Plv_event); cdecl; forward;
procedure fb_rename_cb(e: Plv_event); cdecl; forward;
procedure fb_rename_ok_cb(e: Plv_event); cdecl; forward;
procedure fb_newfile_cb(e: Plv_event); cdecl; forward;
procedure fb_newfile_ok_cb(e: Plv_event); cdecl; forward;
procedure fb_newfile_opened(error: TError; userdata: pointer); forward;
procedure fb_newfile_written(error: TError; userdata: pointer); forward;
procedure fb_newfile_done_timer(tmr: Plv_timer); cdecl; forward;
{ Phase 7 — context menu }
procedure fb_row_long_press_cb(e: Plv_event); cdecl; forward;
procedure show_context_menu(state: PFileBrowserState; mx, my: sint32); forward;
procedure destroy_context_menu(state: PFileBrowserState); forward;
procedure fb_ctx_item_cb(e: Plv_event); cdecl; forward;
procedure fb_ctx_dismiss_timer(tmr: Plv_timer); cdecl; forward;
{ Phase 8 — tabs }
procedure save_tab(state: PFileBrowserState; idx: uint32); forward;
procedure restore_tab(state: PFileBrowserState; idx: uint32); forward;
procedure switch_tab(state: PFileBrowserState; idx: uint32); forward;
procedure add_tab(state: PFileBrowserState; path: pchar); forward;
procedure close_tab(state: PFileBrowserState; idx: uint32); forward;
procedure rebuild_tab_bar(state: PFileBrowserState); forward;
procedure fb_tab_cb(e: Plv_event); cdecl; forward;
procedure fb_tab_close_cb(e: Plv_event); cdecl; forward;
procedure fb_tab_new_cb(e: Plv_event); cdecl; forward;
procedure free_tab_snapshot(snap: PTabSnapshot); forward;
{ Phase 9 — bookmarks }
procedure rebuild_bookmarks(state: PFileBrowserState); forward;
procedure add_bookmark_entry(state: PFileBrowserState; path: pchar); forward;
procedure remove_bookmark_entry(state: PFileBrowserState; idx: uint32); forward;
procedure fb_bookmark_click_cb(e: Plv_event); cdecl; forward;
procedure fb_bookmark_add_cb(e: Plv_event); cdecl; forward;
procedure fb_bookmark_ctx_cb(e: Plv_event); cdecl; forward;
{ Phase 10 — quick filter }
procedure fb_filter_changed_cb(e: Plv_event); cdecl; forward;
procedure fb_filter_clear_cb(e: Plv_event); cdecl; forward;
{ Phase 11 — type-ahead jump }
procedure fb_typeahead_key_cb(e: Plv_event); cdecl; forward;
procedure fb_typeahead_reset_timer(tmr: Plv_timer); cdecl; forward;
{ Phase 12 — file preview panel }
procedure fb_preview_toggle_cb(e: Plv_event); cdecl; forward;
procedure update_preview(state: PFileBrowserState); forward;
{ Phase 13 — compact view }
procedure fb_viewmode_toggle_cb(e: Plv_event); cdecl; forward;
{ Phase 14 — column header sorting }
procedure fb_header_name_cb(e: Plv_event); cdecl; forward;
procedure fb_header_size_cb(e: Plv_event); cdecl; forward;
procedure fb_header_type_cb(e: Plv_event); cdecl; forward;
{ Phase 15 — hidden files toggle }
procedure fb_hidden_toggle_cb(e: Plv_event); cdecl; forward;
{ Phase 17 — directory watch live refresh }
procedure fb_watch_cb(event: TVFSWatchEvent; path: pchar; userdata: pointer); forward;
procedure fb_watch_poll_timer(tmr: Plv_timer); cdecl; forward;
{ ============================================================
  free_tab_snapshot — release a TTabSnapshot and its contents
  ============================================================ }
procedure free_tab_snapshot(snap: PTabSnapshot);
var
    i: uint32;
begin
    if snap = nil then exit;
    if snap^.cur_path <> nil then kfree(void(snap^.cur_path));
    if snap^.sel_path <> nil then kfree(void(snap^.sel_path));
    if snap^.hist_len > 0 then
        for i := 0 to snap^.hist_len - 1 do
            if snap^.history[i] <> nil then begin
                kfree(void(snap^.history[i]));
                snap^.history[i] := nil;
            end;
    if snap^.filter_text <> nil then kfree(void(snap^.filter_text));
    kfree(void(snap));
end;

{ ============================================================
  freeState — release all heap-allocated fields and the record
  ============================================================ }
procedure freeState(state: PFileBrowserState);
var
    i: uint32;
begin
    if state = nil then exit;
    if state^.cur_path <> nil then kfree(void(state^.cur_path));
    if state^.sel_path <> nil then kfree(void(state^.sel_path));
    { Free history entries }
    if state^.hist_len > 0 then
        for i := 0 to state^.hist_len - 1 do
            if state^.history[i] <> nil then begin
                kfree(void(state^.history[i]));
                state^.history[i] := nil;
            end;
    { Free tab snapshots }
    if state^.tab_count > 0 then
        for i := 0 to state^.tab_count - 1 do
            if state^.tabs[i] <> nil then begin
                free_tab_snapshot(state^.tabs[i]);
                state^.tabs[i] := nil;
            end;
    { Free bookmarks }
    if state^.bm_count > 0 then
        for i := 0 to state^.bm_count - 1 do
            if state^.bookmarks[i] <> nil then begin
                kfree(void(state^.bookmarks[i]));
                state^.bookmarks[i] := nil;
            end;
    if state^.filter_text <> nil then kfree(void(state^.filter_text));
    if state^.ta_timer <> nil then begin
        lv_timer_delete(state^.ta_timer);
        state^.ta_timer := nil;
    end;
    { Unwatch directory }
    if state^.watch_id <> 0 then begin
        driver.storage.vfs.UnwatchDirectory(state^.watch_id);
        state^.watch_id := 0;
    end;
    if state^.watch_timer <> nil then begin
        lv_timer_delete(state^.watch_timer);
        state^.watch_timer := nil;
    end;
    if state^.refresh_poll <> nil then begin
        lv_timer_delete(state^.refresh_poll);
        state^.refresh_poll := nil;
    end;
    { Free rd_* buffers }
    if state^.rd_dir_names <> nil then begin
        if state^.rd_dir_count > 0 then
            for i := 0 to state^.rd_dir_count - 1 do
                if state^.rd_dir_names^[i] <> nil then
                    kfree(void(state^.rd_dir_names^[i]));
        kfree(void(state^.rd_dir_names));
    end;
    if state^.rd_file_names <> nil then begin
        if state^.rd_file_count > 0 then
            for i := 0 to state^.rd_file_count - 1 do
                if state^.rd_file_names^[i] <> nil then
                    kfree(void(state^.rd_file_names^[i]));
        kfree(void(state^.rd_file_names));
    end;
    if state^.rd_file_sizes <> nil then
        kfree(void(state^.rd_file_sizes));
    { Free worker-op paths }
    if state^.wop_path1 <> nil then kfree(void(state^.wop_path1));
    if state^.wop_path2 <> nil then kfree(void(state^.wop_path2));
    { Free dispatch path }
    if state^.dispatch_path <> nil then kfree(void(state^.dispatch_path));
    kfree(void(state));
end;

{ ============================================================
  free_children_userdata — kfree stringCopy'd pchar in user_data
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
  fb_entry — process entry point (keeps PS listing alive)
  ============================================================ }
procedure fb_entry(ctx: PProcessContext);
var
    state  : PFileBrowserState;
    opKind : uint32;
    err    : TError;
    dpath  : pchar;
    dpid   : uint32;
begin
    state := PFileBrowserState(ctx^.Local);
    while (ctx^.State <> psFinished) and
          (ctx^.PendingMsg <> smKill) and
          (ctx^.PendingMsg <> smTerminate) do begin
        { Check if a refresh was requested (volatile read per Lesson #6) }
        if puint32(@state^.refresh_pending)^ = 1 then begin
            puint32(@state^.refresh_pending)^ := 0;
            do_refresh_load(state);
            puint32(@state^.rd_ready)^ := 1;
        end;
        { Check for worker VFS operations (mkdir, rename) }
        opKind := puint32(@state^.wop_pending)^;
        if opKind <> 0 then begin
            puint32(@state^.wop_pending)^ := 0;
            state^.wop_kind := opKind;
            err := eNone;
            case opKind of
                1: err := driver.storage.vfs.CreateDirectory(
                              state^.wop_path1, @err);
                2: err := driver.storage.vfs.RenameFile(
                              state^.wop_path1, state^.wop_path2, @err);
            end;
            state^.wop_result := err;
            puint32(@state^.wop_done)^ := 1;
        end;
        { Check for file dispatch request }
        if puint32(@state^.dispatch_pending)^ = 1 then begin
            puint32(@state^.dispatch_pending)^ := 0;
            dpath := state^.dispatch_path;
            state^.dispatch_path := nil;
            if dpath <> nil then begin
                dpid := driver.storage.filedispatch.dispatch(
                            dpath, nil, nil, nil, nil);
                state^.dispatch_result := dpid;
                kfree(void(dpath));
            end else
                state^.dispatch_result := 0;
            puint32(@state^.dispatch_done)^ := 1;
        end;
        proc.mgr.proc_yield;
    end;
end;

{ ============================================================
  onClose — called by the window manager when X is pressed
  ============================================================ }
procedure onClose(wid: uint32);
begin
    debug.tracer.push_trace('filebrowser.onClose');
    if g_state <> nil then begin
        { 1. Kill worker process so it stops touching state }
        if g_state^.pid <> 0 then begin
            proc.mgr.kill(g_state^.pid);
            g_state^.pid := 0;
        end;
        { 2. Delete LVGL timers early to prevent callbacks during teardown }
        if g_state^.ta_timer <> nil then begin
            lv_timer_delete(g_state^.ta_timer);
            g_state^.ta_timer := nil;
        end;
        if g_state^.watch_timer <> nil then begin
            lv_timer_delete(g_state^.watch_timer);
            g_state^.watch_timer := nil;
        end;
        if g_state^.refresh_poll <> nil then begin
            lv_timer_delete(g_state^.refresh_poll);
            g_state^.refresh_poll := nil;
        end;
        { 3. Clear selection — nil sel_row before deletion (Lesson #16) }
        clear_selection(g_state);
        { 4. Destroy context menu (lives on lv_layer_top, not in frame) }
        destroy_context_menu(g_state);
        { 5. Free user_data strings from LVGL children }
        free_children_userdata(g_state^.breadcrumb);
        free_children_userdata(g_state^.content_area);
        if g_state^.sidebar <> nil then
            free_children_userdata(g_state^.sidebar);
        { 6. Destroy window — deletes all LVGL widget objects }
        driver.video.windows.destroyWindow(g_win_id);
        g_win_id := 0;
        { 7. Now free remaining heap data and the state record }
        freeState(g_state);
        g_state := nil;
    end else begin
        driver.video.windows.destroyWindow(g_win_id);
        g_win_id := 0;
    end;
    debug.tracer.pop_trace;
end;

{ ============================================================
  onResize — called when the user resizes the window
  ============================================================ }
procedure onResize(wid: uint32; new_w, new_h: sint32);
begin
    { LVGL flex layout handles child resizing automatically. }
end;

{ ============================================================
  History helpers
  ============================================================ }
procedure push_history(state: PFileBrowserState; path: pchar);
var
    i: sint32;
begin
    { Trim forward entries }
    if state^.hist_pos + 1 < state^.hist_len then
        for i := sint32(state^.hist_pos) + 1 to sint32(state^.hist_len) - 1 do
            if state^.history[i] <> nil then begin
                kfree(void(state^.history[i]));
                state^.history[i] := nil;
            end;
    state^.hist_len := state^.hist_pos + 1;

    { Drop oldest when full }
    if state^.hist_len = HIST_MAX then begin
        if state^.history[0] <> nil then kfree(void(state^.history[0]));
        for i := 0 to HIST_MAX - 2 do
            state^.history[i] := state^.history[i + 1];
        state^.history[HIST_MAX - 1] := nil;
        state^.hist_len := HIST_MAX - 1;
        state^.hist_pos := HIST_MAX - 2;
    end;

    state^.history[state^.hist_len] := stringCopy(path);
    state^.hist_len := state^.hist_len + 1;
    state^.hist_pos := state^.hist_len - 1;
end;

procedure update_nav_btns(state: PFileBrowserState);
begin
    if state^.back_btn <> nil then begin
        if state^.hist_pos > 0 then begin
            lv_obj_add_flag(state^.back_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(state^.back_btn, LV_OPA_COVER, 0);
        end else begin
            lv_obj_remove_flag(state^.back_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(state^.back_btn, 80, 0);
        end;
    end;
    if state^.fwd_btn <> nil then begin
        if state^.hist_pos + 1 < state^.hist_len then begin
            lv_obj_add_flag(state^.fwd_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(state^.fwd_btn, LV_OPA_COVER, 0);
        end else begin
            lv_obj_remove_flag(state^.fwd_btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_opa(state^.fwd_btn, 80, 0);
        end;
    end;
end;

{ ============================================================
  navigate_to — central navigation point
  ============================================================ }
procedure navigate_to(state: PFileBrowserState; newDir: pchar);
begin
    { Unwatch old directory }
    if state^.watch_id <> 0 then begin
        driver.storage.vfs.UnwatchDirectory(state^.watch_id);
        state^.watch_id := 0;
    end;
    push_history(state, newDir);
    if state^.cur_path <> nil then kfree(void(state^.cur_path));
    state^.cur_path := stringCopy(newDir);
    update_nav_btns(state);
    build_breadcrumbs(state);
    if state^.tab_bar <> nil then rebuild_tab_bar(state);
    { Watch new directory }
    state^.watch_dirty := false;
    state^.watch_id := driver.storage.vfs.WatchDirectory(newDir, @fb_watch_cb, state);
    schedule_refresh(state);
end;

{ ============================================================
  schedule_refresh — signal the fb_entry process to do VFS I/O
  ============================================================ }
procedure schedule_refresh(state: PFileBrowserState);
begin
    { Signal the worker process to load data (volatile write) }
    puint32(@state^.refresh_pending)^ := 1;
end;

{ fb_refresh_poll_cb — 50ms LVGL poll timer; when rd_ready=1, build UI }
procedure fb_refresh_poll_cb(tmr: Plv_timer); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    ok_b  : Plv_obj;
begin
    state := PFileBrowserState(lv_timer_get_user_data(tmr));
    if state = nil then exit;
    if puint32(@state^.rd_ready)^ = 1 then begin
        puint32(@state^.rd_ready)^ := 0;
        do_refresh_build(state);
    end;
    { Check for completed worker VFS operation }
    if puint32(@state^.wop_done)^ = 1 then begin
        puint32(@state^.wop_done)^ := 0;
        if state^.wop_result <> eNone then begin
            mbox := lv_msgbox_create(lv_layer_top);
            lv_msgbox_add_title(mbox, 'Error');
            case state^.wop_kind of
                1: lv_msgbox_add_text(mbox, 'Could not create folder.');
                2: lv_msgbox_add_text(mbox, 'Could not rename item.');
            else
                lv_msgbox_add_text(mbox, 'Operation failed.');
            end;
            ok_b := lv_msgbox_add_footer_button(mbox, 'OK');
            lv_obj_add_event_cb(ok_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
        end;
        { Free op paths }
        if state^.wop_path1 <> nil then begin
            kfree(void(state^.wop_path1));
            state^.wop_path1 := nil;
        end;
        if state^.wop_path2 <> nil then begin
            kfree(void(state^.wop_path2));
            state^.wop_path2 := nil;
        end;
        { For rename, clear selection }
        if state^.wop_kind = 2 then
            clear_selection(state);
        schedule_refresh(state);
    end;
end;

{ ============================================================
  fb_collect_cb — hashmap forEach: classify dirs/files
  ============================================================ }
procedure fb_collect_cb(key: pchar; data: void; ud: void);
var
    ctx : PFBCollectCtx;
    obj : PVFSObject;
begin
    ctx := PFBCollectCtx(ud);
    obj := PVFSObject(data);
    if (ctx = nil) or (obj = nil) then exit;
    case obj^.ObjectType of
        otVDIRECTORY, otDRIVE, otDIRECTORY, otMOUNT, otSYMLINK:
            if ctx^.dir_count < ENTRY_MAX then begin
                ctx^.dir_names^[ctx^.dir_count] := key;
                ctx^.dir_count := ctx^.dir_count + 1;
            end;
        otFILE, otVFILE:
            if ctx^.file_count < ENTRY_MAX then begin
                ctx^.file_names^[ctx^.file_count] := key;
                ctx^.file_sizes^[ctx^.file_count] := obj^.FileSize;
                ctx^.file_count := ctx^.file_count + 1;
            end;
    end;
end;

{ ============================================================
  update_status_bar — show item count and current path
  ============================================================ }
procedure update_status_bar(state: PFileBrowserState);
var
    s1, s2, s3, s4, s5 : pchar;
begin
    if state^.status_label = nil then exit;
    s1 := intToString(state^.item_count);
    s2 := stringConcat(s1, ' items');
    kfree(void(s1));

    { If something is selected, show its name }
    if state^.sel_path <> nil then begin
        s3 := stringConcat(s2, '  |  Sel: ');
        kfree(void(s2));
        s4 := stringConcat(s3, state^.sel_path);
        kfree(void(s3));
        s5 := stringConcat(s4, '  |  ');
        kfree(void(s4));
    end else begin
        s5 := stringConcat(s2, '  |  ');
        kfree(void(s2));
    end;

    s3 := stringConcat(s5, state^.cur_path);
    kfree(void(s5));
    lv_label_set_text(state^.status_label, s3);
    kfree(void(s3));
end;

{ ============================================================
  do_refresh_load — VFS I/O + sort (runs in fb_entry process)
  Stores results in state^.rd_* fields.
  ============================================================ }
procedure do_refresh_load(state: PFileBrowserState);
var
    Map        : PHashMap;
    ctx        : TFBCollectCtx;
    dir_names  : PNameBuf;
    file_names : PNameBuf;
    file_sizes : PSizeBuf;
    dir_count  : uint32;
    file_count : uint32;
    shown      : uint32;
    i          : uint32;
    extStr     : pchar;
    sep        : pchar;
    s1         : pchar;
begin
    debug.tracer.push_trace('filebrowser.do_refresh_load');

    { Free any previous rd_* buffers }
    if state^.rd_dir_names <> nil then begin
        { Free stringCopy'd entries }
        if state^.rd_dir_count > 0 then
            for i := 0 to state^.rd_dir_count - 1 do
                if state^.rd_dir_names^[i] <> nil then
                    kfree(void(state^.rd_dir_names^[i]));
        kfree(void(state^.rd_dir_names));
        state^.rd_dir_names := nil;
    end;
    if state^.rd_file_names <> nil then begin
        if state^.rd_file_count > 0 then
            for i := 0 to state^.rd_file_count - 1 do
                if state^.rd_file_names^[i] <> nil then
                    kfree(void(state^.rd_file_names^[i]));
        kfree(void(state^.rd_file_names));
        state^.rd_file_names := nil;
    end;
    if state^.rd_file_sizes <> nil then begin
        kfree(void(state^.rd_file_sizes));
        state^.rd_file_sizes := nil;
    end;
    state^.rd_dir_count  := 0;
    state^.rd_file_count := 0;
    state^.rd_failed     := false;

    { Heap-alloc name/size buffers (Lesson #11) }
    dir_names  := PNameBuf(kalloc(sizeof(TNameBuf)));
    file_names := PNameBuf(kalloc(sizeof(TNameBuf)));
    file_sizes := PSizeBuf(kalloc(sizeof(TSizeBuf)));
    memset(uint32(dir_names),  0, sizeof(TNameBuf));
    memset(uint32(file_names), 0, sizeof(TNameBuf));
    memset(uint32(file_sizes), 0, sizeof(TSizeBuf));

    { Load directory from VFS — this may do disk I/O }
    Map := driver.storage.vfs.GetDirectoryListingFrom(state^.cur_path, '/');
    if Map = nil then begin
        state^.rd_failed := true;
        kfree(void(dir_names));
        kfree(void(file_names));
        kfree(void(file_sizes));
        debug.tracer.pop_trace; exit;
    end;

    if Map^.Table = nil then begin
        driver.storage.vfs.FreeDirectoryListing(Map);
        state^.rd_failed := true;
        kfree(void(dir_names));
        kfree(void(file_names));
        kfree(void(file_sizes));
        debug.tracer.pop_trace; exit;
    end;

    { Collect entries }
    ctx.dir_names  := dir_names;
    ctx.file_names := file_names;
    ctx.file_sizes := file_sizes;
    ctx.dir_count  := 0;
    ctx.file_count := 0;
    core.ds.hashmap.forEach(Map, @fb_collect_cb, void(@ctx));
    dir_count  := ctx.dir_count;
    file_count := ctx.file_count;

    { Sort }
    if dir_count  > 0 then sortStringArray(@dir_names^[0], dir_count);
    if file_count > 0 then begin
        case state^.sort_col of
            1: begin { Sort by size — bubble sort on sizes, move names along }
                if file_count > 1 then
                for i := 0 to file_count - 2 do
                    for shown := 0 to file_count - i - 2 do
                        if file_sizes^[shown] > file_sizes^[shown + 1] then begin
                            { swap sizes }
                            dir_count := file_sizes^[shown];
                            file_sizes^[shown] := file_sizes^[shown + 1];
                            file_sizes^[shown + 1] := dir_count;
                            { swap names }
                            s1 := file_names^[shown];
                            file_names^[shown] := file_names^[shown + 1];
                            file_names^[shown + 1] := s1;
                        end;
                dir_count := ctx.dir_count; { restore dir_count }
            end;
            2: begin { Sort by extension — sort by extension string }
                sortStringArrayWithData(@file_names^[0], @file_sizes^[0], file_count);
                { Re-sort by extension: bubble sort }
                if file_count > 1 then
                for i := 0 to file_count - 2 do
                    for shown := 0 to file_count - i - 2 do begin
                        extStr := getFileExtension(file_names^[shown]);
                        sep    := getFileExtension(file_names^[shown + 1]);
                        if extStr = nil then extStr := '';
                        if sep    = nil then sep    := '';
                        if stringCompare(extStr, sep) > 0 then begin
                            { swap names }
                            s1 := file_names^[shown];
                            file_names^[shown] := file_names^[shown + 1];
                            file_names^[shown + 1] := s1;
                            { swap sizes }
                            dir_count := file_sizes^[shown];
                            file_sizes^[shown] := file_sizes^[shown + 1];
                            file_sizes^[shown + 1] := dir_count;
                        end;
                    end;
                dir_count := ctx.dir_count;
            end;
        else { sort_col=0: default name sort }
            sortStringArrayWithData(@file_names^[0], @file_sizes^[0], file_count);
        end;
    end;

    { Reverse if descending (dirs and files separately) }
    if not state^.sort_asc then begin
        if dir_count > 1 then
            for i := 0 to (dir_count div 2) - 1 do begin
                s1 := dir_names^[i];
                dir_names^[i] := dir_names^[dir_count - 1 - i];
                dir_names^[dir_count - 1 - i] := s1;
            end;
        if file_count > 1 then
            for i := 0 to (file_count div 2) - 1 do begin
                s1 := file_names^[i];
                file_names^[i] := file_names^[file_count - 1 - i];
                file_names^[file_count - 1 - i] := s1;
                shown := file_sizes^[i];
                file_sizes^[i] := file_sizes^[file_count - 1 - i];
                file_sizes^[file_count - 1 - i] := shown;
            end;
    end;

    { Free the VFS snapshot — we only need name copies now }
    { But the names in dir_names/file_names point INTO the snapshot!
      We must stringCopy them before freeing. }
    if dir_count > 0 then
        for i := 0 to dir_count - 1 do
            dir_names^[i] := stringCopy(dir_names^[i]);
    if file_count > 0 then
        for i := 0 to file_count - 1 do
            file_names^[i] := stringCopy(file_names^[i]);

    driver.storage.vfs.FreeDirectoryListing(Map);

    { Store sorted results for UI build }
    state^.rd_dir_names  := dir_names;
    state^.rd_file_names := file_names;
    state^.rd_file_sizes := file_sizes;
    state^.rd_dir_count  := dir_count;
    state^.rd_file_count := file_count;

    debug.tracer.pop_trace;
end;

{ ============================================================
  do_refresh_build — create LVGL widgets from rd_* data
  (runs in LVGL poll timer — NO disk I/O!)
  ============================================================ }
procedure do_refresh_build(state: PFileBrowserState);
var
    dir_names  : PNameBuf;
    file_names : PNameBuf;
    file_sizes : PSizeBuf;
    dir_count  : uint32;
    file_count : uint32;
    shown      : uint32;
    has_filter : boolean;
    i          : uint32;
    row        : Plv_obj;
    icon_lbl   : Plv_obj;
    name_lbl   : Plv_obj;
    size_lbl   : Plv_obj;
    type_lbl   : Plv_obj;
    szStr      : pchar;
    extStr     : pchar;
    s1, s2     : pchar;
    ico_color  : uint32;
begin
    debug.tracer.push_trace('filebrowser.do_refresh_build');
    if state^.content_area = nil then begin
        debug.tracer.pop_trace; exit;
    end;

    { Release old UI entries — clear_selection BEFORE lv_obj_clean,
      otherwise we write styles to a freed LVGL object (sel_row) }
    clear_selection(state);
    free_children_userdata(state^.content_area);
    lv_obj_clean(state^.content_area);

    { Handle failure case }
    if state^.rd_failed then begin
        name_lbl := lv_label_create(state^.content_area);
        lv_label_set_text(name_lbl, 'Could not read directory');
        lv_obj_set_style_text_color(name_lbl, lv_color_make(220, 60, 60), 0);
        lv_obj_set_style_text_font(name_lbl, @lv_font_montserrat_14, 0);
        state^.item_count := 0;
        update_status_bar(state);
        debug.tracer.pop_trace; exit;
    end;

    dir_names  := state^.rd_dir_names;
    file_names := state^.rd_file_names;
    file_sizes := state^.rd_file_sizes;
    dir_count  := state^.rd_dir_count;
    file_count := state^.rd_file_count;

    if (dir_names = nil) and (file_names = nil) then begin
        state^.item_count := 0;
        update_status_bar(state);
        debug.tracer.pop_trace; exit;
    end;

    has_filter := (state^.filter_text <> nil) and (stringSize(state^.filter_text) > 0);
    shown := 0;

    { Set layout based on view mode }
    if state^.view_mode = vmCompact then begin
        lv_obj_set_flex_flow(state^.content_area, LV_FLEX_FLOW_ROW_WRAP);
        lv_obj_set_style_pad_row(state^.content_area, 4, 0);
        lv_obj_set_style_pad_column(state^.content_area, 4, 0);
    end else begin
        lv_obj_set_flex_flow(state^.content_area, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_style_pad_row(state^.content_area, 2, 0);
    end;

    { --- Detail header row --- }
    if state^.view_mode = vmDetail then begin
        row := lv_obj_create(state^.content_area);
        lv_obj_remove_style_all(row);
        lv_obj_set_size(row, lv_pct(100), 26);
        lv_obj_set_style_bg_color(row, lv_color_make(28, 31, 42), 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_pad_left(row, 8, 0);
        lv_obj_set_style_pad_right(row, 8, 0);
        lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_style_border_color(row, lv_color_make(48, 52, 68), 0);
        lv_obj_set_style_border_side(row, LV_BORDER_SIDE_BOTTOM, 0);
        lv_obj_set_style_border_width(row, 1, 0);

        { Icon column spacer }
        icon_lbl := lv_label_create(row);
        lv_label_set_text(icon_lbl, '');
        lv_obj_set_size(icon_lbl, 36, LV_SIZE_CONTENT);

        { Name header }
        name_lbl := lv_label_create(row);
        if (state^.sort_col = 0) and state^.sort_asc then
            lv_label_set_text(name_lbl, 'Name ^')
        else if (state^.sort_col = 0) and (not state^.sort_asc) then
            lv_label_set_text(name_lbl, 'Name v')
        else
            lv_label_set_text(name_lbl, 'Name');
        lv_obj_set_style_text_color(name_lbl, lv_color_make(170, 178, 200), 0);
        lv_obj_set_style_text_font(name_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_flex_grow(name_lbl, 1);
        lv_obj_add_flag(name_lbl, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_event_cb(name_lbl, @fb_header_name_cb, LV_EVENT_CLICKED, state);

        { Size header }
        size_lbl := lv_label_create(row);
        if (state^.sort_col = 1) and state^.sort_asc then
            lv_label_set_text(size_lbl, 'Size ^')
        else if (state^.sort_col = 1) and (not state^.sort_asc) then
            lv_label_set_text(size_lbl, 'Size v')
        else
            lv_label_set_text(size_lbl, 'Size');
        lv_obj_set_style_text_color(size_lbl, lv_color_make(170, 178, 200), 0);
        lv_obj_set_style_text_font(size_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_size(size_lbl, 70, LV_SIZE_CONTENT);
        lv_obj_add_flag(size_lbl, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_event_cb(size_lbl, @fb_header_size_cb, LV_EVENT_CLICKED, state);

        { Type header }
        type_lbl := lv_label_create(row);
        if (state^.sort_col = 2) and state^.sort_asc then
            lv_label_set_text(type_lbl, 'Type ^')
        else if (state^.sort_col = 2) and (not state^.sort_asc) then
            lv_label_set_text(type_lbl, 'Type v')
        else
            lv_label_set_text(type_lbl, 'Type');
        lv_obj_set_style_text_color(type_lbl, lv_color_make(170, 178, 200), 0);
        lv_obj_set_style_text_font(type_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_size(type_lbl, 60, LV_SIZE_CONTENT);
        lv_obj_add_flag(type_lbl, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_event_cb(type_lbl, @fb_header_type_cb, LV_EVENT_CLICKED, state);
    end;

    { --- Build directory rows --- }
    if (dir_names <> nil) and (dir_count > 0) then
    for i := 0 to dir_count - 1 do begin
        if dir_names^[i] = nil then continue;
        if (not state^.show_hidden) and (dir_names^[i][0] = '.') then continue;
        if has_filter then
            if not stringContainsCI(dir_names^[i], state^.filter_text) then continue;
        row := lv_obj_create(state^.content_area);
        lv_obj_remove_style_all(row);
        if state^.view_mode = vmCompact then begin
            lv_obj_set_size(row, 120, 34);
        end else begin
            lv_obj_set_size(row, lv_pct(100), 34);
        end;
        lv_obj_set_style_bg_color(row, lv_color_make(38, 42, 56), 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(row, lv_color_make(50, 55, 72), LV_STATE_PRESSED);
        lv_obj_set_style_radius(row, 4, 0);
        lv_obj_set_style_pad_left(row, 8, 0);
        lv_obj_set_style_pad_right(row, 8, 0);
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);

        { Folder icon — 32px PUA glyph }
        icon_lbl := lv_label_create(row);
        lv_label_set_text(icon_lbl, ICO_FOLDER);
        lv_obj_set_style_text_color(icon_lbl, lv_color_make(255, 210, 60), 0);
        lv_obj_set_style_text_font(icon_lbl, @asuro_icons_32, 0);
        lv_obj_set_size(icon_lbl, 36, 32);

        { Folder name }
        name_lbl := lv_label_create(row);
        lv_label_set_text(name_lbl, dir_names^[i]);
        lv_obj_set_style_text_color(name_lbl, lv_color_make(255, 210, 60), 0);
        lv_obj_set_style_text_font(name_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_flex_grow(name_lbl, 1);
        if state^.view_mode = vmCompact then
            lv_label_set_long_mode(name_lbl, LV_LABEL_LONG_CLIP);

        if state^.view_mode = vmDetail then begin
            { Size column — show DIR }
            size_lbl := lv_label_create(row);
            lv_label_set_text(size_lbl, 'DIR');
            lv_obj_set_style_text_color(size_lbl, lv_color_make(140, 150, 170), 0);
            lv_obj_set_style_text_font(size_lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_size(size_lbl, 70, LV_SIZE_CONTENT);
        end;

        { Build full path in user_data for navigation }
        if stringEquals(state^.cur_path, '/') then begin
            s1 := stringConcat('/', dir_names^[i]);
        end else begin
            s1 := stringConcat(state^.cur_path, '/');
            s2 := stringConcat(s1, dir_names^[i]);
            kfree(void(s1));
            s1 := s2;
        end;
        lv_obj_set_user_data(row, s1);
        lv_obj_add_flag(row, LV_OBJ_FLAG_USER_1);  { mark as directory row }
        lv_obj_add_event_cb(row, @fb_dir_cb, LV_EVENT_CLICKED, g_state);
        lv_obj_add_event_cb(row, @fb_row_long_press_cb, LV_EVENT_LONG_PRESSED, g_state);
        shown := shown + 1;
    end;

    { --- Build file rows --- }
    if (file_names <> nil) and (file_count > 0) then
    for i := 0 to file_count - 1 do begin
        if file_names^[i] = nil then continue;
        if (not state^.show_hidden) and (file_names^[i][0] = '.') then continue;
        if has_filter then
            if not stringContainsCI(file_names^[i], state^.filter_text) then continue;
        row := lv_obj_create(state^.content_area);
        lv_obj_remove_style_all(row);
        if state^.view_mode = vmCompact then
            lv_obj_set_size(row, 120, 34)
        else
            lv_obj_set_size(row, lv_pct(100), 34);
        lv_obj_set_style_bg_color(row, lv_color_make(32, 35, 48), 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(row, lv_color_make(50, 55, 72), LV_STATE_PRESSED);
        lv_obj_set_style_radius(row, 4, 0);
        lv_obj_set_style_pad_left(row, 8, 0);
        lv_obj_set_style_pad_right(row, 8, 0);
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);

        { File icon — 32px PUA glyph, color by type }
        ico_color := getFileTypeColor(file_names^[i]);
        icon_lbl := lv_label_create(row);
        lv_label_set_text(icon_lbl, getFileTypeIcon(file_names^[i]));
        lv_obj_set_style_text_color(icon_lbl, lv_color_make(
            (ico_color shr 16) and $FF,
            (ico_color shr 8) and $FF,
            ico_color and $FF), 0);
        lv_obj_set_style_text_font(icon_lbl, @asuro_icons_32, 0);
        lv_obj_set_size(icon_lbl, 36, 32);

        { File name }
        name_lbl := lv_label_create(row);
        lv_label_set_text(name_lbl, file_names^[i]);
        lv_obj_set_style_text_color(name_lbl, lv_color_make(210, 218, 240), 0);
        lv_obj_set_style_text_font(name_lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_flex_grow(name_lbl, 1);
        if state^.view_mode = vmCompact then
            lv_label_set_long_mode(name_lbl, LV_LABEL_LONG_CLIP);

        if state^.view_mode = vmDetail then begin
            { Size label }
            szStr := fmtFileSize(file_sizes^[i]);
            size_lbl := lv_label_create(row);
            lv_label_set_text(size_lbl, szStr);
            kfree(void(szStr));
            lv_obj_set_style_text_color(size_lbl, lv_color_make(140, 150, 170), 0);
            lv_obj_set_style_text_font(size_lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_size(size_lbl, 70, LV_SIZE_CONTENT);

            { Type/extension label }
            extStr := getFileExtension(file_names^[i]);
            type_lbl := lv_label_create(row);
            if extStr <> nil then
                lv_label_set_text(type_lbl, extStr)
            else
                lv_label_set_text(type_lbl, '');
            lv_obj_set_style_text_color(type_lbl, lv_color_make(120, 130, 150), 0);
            lv_obj_set_style_text_font(type_lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_size(type_lbl, 60, LV_SIZE_CONTENT);
        end;

        { Full path in user_data }
        if stringEquals(state^.cur_path, '/') then begin
            s1 := stringConcat('/', file_names^[i]);
        end else begin
            s1 := stringConcat(state^.cur_path, '/');
            s2 := stringConcat(s1, file_names^[i]);
            kfree(void(s1));
            s1 := s2;
        end;
        lv_obj_set_user_data(row, s1);
        lv_obj_add_event_cb(row, @fb_file_cb, LV_EVENT_CLICKED, g_state);
        lv_obj_add_event_cb(row, @fb_row_long_press_cb, LV_EVENT_LONG_PRESSED, g_state);
        shown := shown + 1;
    end;

    state^.item_count := shown;
    update_status_bar(state);
    debug.tracer.pop_trace;
end;

{ ============================================================
  do_refresh — convenience: trigger load+build for callers that
  run in the fb_entry process context (not used from LVGL)
  ============================================================ }
procedure do_refresh(state: PFileBrowserState);
begin
    do_refresh_load(state);
    do_refresh_build(state);
end;

{ ============================================================
  Row click callbacks
  ============================================================ }
procedure fb_dir_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
    row   : Plv_obj;
    path  : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    row  := lv_event_get_target_obj(e);
    path := pchar(lv_obj_get_user_data(row));
    if path = nil then exit;
    { If already selected, navigate into it (double-click effect) }
    if (state^.sel_path <> nil) and stringEquals(state^.sel_path, path) then begin
        navigate_to(state, path);
        exit;
    end;
    { Otherwise select }
    select_item(state, row, path, true);
end;

procedure fb_file_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
    row   : Plv_obj;
    path  : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    row  := lv_event_get_target_obj(e);
    path := pchar(lv_obj_get_user_data(row));
    if path = nil then exit;

    { If clicking the already-selected file, treat as "open" via dispatch.
      Schedule dispatch in the worker process (Lesson #10: no sync disk I/O
      from LVGL callbacks). }
    if (state^.sel_path <> nil) and stringEquals(path, state^.sel_path)
       and (not state^.sel_is_dir) then begin
        if puint32(@state^.dispatch_pending)^ = 0 then begin
            state^.dispatch_path := stringCopy(path);
            puint32(@state^.dispatch_done)^ := 0;
            puint32(@state^.dispatch_pending)^ := 1;
        end;
        exit;
    end;

    select_item(state, row, path, false);
end;

{ ============================================================
  Navigation button callbacks
  ============================================================ }
procedure fb_back_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if (state = nil) or (state^.hist_pos = 0) then exit;
    state^.hist_pos := state^.hist_pos - 1;
    if state^.cur_path <> nil then kfree(void(state^.cur_path));
    state^.cur_path := stringCopy(state^.history[state^.hist_pos]);
    update_nav_btns(state);
    build_breadcrumbs(state);
    schedule_refresh(state);
end;

procedure fb_fwd_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if (state = nil) or (state^.hist_pos + 1 >= state^.hist_len) then exit;
    state^.hist_pos := state^.hist_pos + 1;
    if state^.cur_path <> nil then kfree(void(state^.cur_path));
    state^.cur_path := stringCopy(state^.history[state^.hist_pos]);
    update_nav_btns(state);
    build_breadcrumbs(state);
    schedule_refresh(state);
end;

procedure fb_up_cb(e: Plv_event); cdecl;
var
    code     : lv_event_code_t;
    state    : PFileBrowserState;
    cur      : pchar;
    len      : uint32;
    i        : sint32;
    parent   : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    cur := state^.cur_path;
    if cur = nil then exit;
    len := stringSize(cur);
    if (len <= 1) then exit;  { already at root }
    { Find last '/' before end }
    i := sint32(len) - 1;
    { Skip trailing slash }
    if cur[i] = '/' then dec(i);
    while (i > 0) and (cur[i] <> '/') do dec(i);
    if i = 0 then
        parent := stringCopy('/')
    else begin
        parent := pchar(kalloc(uint32(i) + 1));
        memcpy(uint32(cur), uint32(parent), uint32(i));
        parent[i] := char(0);
    end;
    navigate_to(state, parent);
    kfree(void(parent));
end;

procedure fb_refresh_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state <> nil then
        schedule_refresh(state);
end;

{ ============================================================
  build_breadcrumbs — parse cur_path into clickable segments
  ============================================================ }
procedure build_breadcrumbs(state: PFileBrowserState);
var
    bar    : Plv_obj;
    btn    : Plv_obj;
    lbl    : Plv_obj;
    sep    : Plv_obj;
    path   : pchar;
    len    : uint32;
    segStart : uint32;
    segEnd   : uint32;
    prefix   : pchar;
    segBuf   : pchar;
    n      : uint32;
begin
    bar := state^.breadcrumb;
    if bar = nil then exit;

    { Free old crumb user_data (path prefixes) }
    n := lv_obj_get_child_count(bar);
    if n > 0 then begin
        free_children_userdata(bar);
    end;
    lv_obj_clean(bar);

    { Hide textarea if visible }
    if state^.path_ta <> nil then begin
        lv_obj_add_flag(state^.path_ta, LV_OBJ_FLAG_HIDDEN);
    end;
    lv_obj_remove_flag(bar, LV_OBJ_FLAG_HIDDEN);
    state^.path_editing := false;

    path := state^.cur_path;
    if path = nil then exit;
    len := stringSize(path);

    { Root "/" button }
    btn := lv_button_create(bar);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, LV_SIZE_CONTENT, 22);
    lv_obj_set_style_bg_color(btn, lv_color_make(50, 55, 72), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(btn, lv_color_make(70, 78, 100), LV_STATE_PRESSED);
    lv_obj_set_style_radius(btn, 3, 0);
    lv_obj_set_style_pad_left(btn, 6, 0);
    lv_obj_set_style_pad_right(btn, 6, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, '/');
    lv_obj_set_style_text_color(lbl, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_center(lbl);
    lv_obj_set_user_data(btn, stringCopy('/'));
    lv_obj_add_event_cb(btn, @fb_crumb_cb, LV_EVENT_CLICKED, g_state);

    { Parse remaining segments }
    if len <= 1 then exit;  { root only }
    segStart := 1;  { skip leading '/' }
    while segStart < len do begin
        { Find end of segment }
        segEnd := segStart;
        while (segEnd < len) and (path[segEnd] <> '/') do
            segEnd := segEnd + 1;
        if segEnd = segStart then begin
            segStart := segEnd + 1;
            continue;
        end;

        { Separator label }
        sep := lv_label_create(bar);
        lv_label_set_text(sep, '>');
        lv_obj_set_style_text_color(sep, lv_color_make(100, 108, 130), 0);
        lv_obj_set_style_text_font(sep, @lv_font_montserrat_14, 0);
        lv_obj_set_user_data(sep, nil);

        { Segment button }
        btn := lv_button_create(bar);
        lv_obj_remove_style_all(btn);
        lv_obj_set_size(btn, LV_SIZE_CONTENT, 22);
        lv_obj_set_style_bg_color(btn, lv_color_make(50, 55, 72), 0);
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(btn, lv_color_make(70, 78, 100), LV_STATE_PRESSED);
        lv_obj_set_style_radius(btn, 3, 0);
        lv_obj_set_style_pad_left(btn, 6, 0);
        lv_obj_set_style_pad_right(btn, 6, 0);
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);

        { Segment name label }
        segBuf := pchar(kalloc(segEnd - segStart + 1));
        memcpy(uint32(@path[segStart]), uint32(segBuf), segEnd - segStart);
        segBuf[segEnd - segStart] := char(0);
        lbl := lv_label_create(btn);
        lv_label_set_text(lbl, segBuf);
        lv_obj_set_style_text_color(lbl, lv_color_make(210, 215, 230), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lv_obj_center(lbl);
        kfree(void(segBuf));

        { Build prefix path for this segment }
        prefix := pchar(kalloc(segEnd + 1));
        memcpy(uint32(path), uint32(prefix), segEnd);
        prefix[segEnd] := char(0);
        lv_obj_set_user_data(btn, prefix);
        lv_obj_add_event_cb(btn, @fb_crumb_cb, LV_EVENT_CLICKED, g_state);

        segStart := segEnd + 1;
    end;
end;

{ ============================================================
  fb_crumb_cb — breadcrumb segment clicked → navigate
  ============================================================ }
procedure fb_crumb_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
    btn   : Plv_obj;
    path  : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    btn  := lv_event_get_target_obj(e);
    path := pchar(lv_obj_get_user_data(btn));
    if path = nil then exit;
    navigate_to(state, path);
end;

{ ============================================================
  fb_crumb_area_cb — click the breadcrumb area background
                     to switch to path text editing mode
  ============================================================ }
procedure fb_crumb_area_cb(e: Plv_event); cdecl;
var
    code   : lv_event_code_t;
    state  : PFileBrowserState;
    target : Plv_obj;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    { Only activate on direct click on the breadcrumb bar itself }
    target := lv_event_get_target_obj(e);
    if target <> state^.breadcrumb then exit;
    if state^.path_editing then exit;

    state^.path_editing := true;
    { Hide breadcrumb buttons, show textarea }
    lv_obj_add_flag(state^.breadcrumb, LV_OBJ_FLAG_HIDDEN);
    if state^.path_ta <> nil then begin
        lv_textarea_set_text(state^.path_ta, state^.cur_path);
        lv_obj_remove_flag(state^.path_ta, LV_OBJ_FLAG_HIDDEN);
    end;
end;

{ ============================================================
  fb_path_ta_cb — Enter navigates, Escape reverts to breadcrumbs
  ============================================================ }
procedure fb_path_ta_cb(e: Plv_event); cdecl;
var
    code  : lv_event_code_t;
    state : PFileBrowserState;
    key   : uint32;
    txt   : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_KEY then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    key := lv_event_get_key(e);
    if key = LV_KEY_ENTER then begin
        txt := lv_textarea_get_text(state^.path_ta);
        if txt <> nil then
            navigate_to(state, txt);
    end
    else if key = LV_KEY_ESC then begin
        { Revert to breadcrumbs }
        build_breadcrumbs(state);
    end;
end;

{ ============================================================
  Selection helpers
  ============================================================ }
procedure clear_selection(state: PFileBrowserState);
begin
    if state^.sel_row <> nil then begin
        { Reset row background to its default colour }
        if state^.sel_is_dir then
            lv_obj_set_style_bg_color(state^.sel_row,
                                      lv_color_make(38, 42, 56), 0)
        else
            lv_obj_set_style_bg_color(state^.sel_row,
                                      lv_color_make(32, 35, 48), 0);
        state^.sel_row := nil;
    end;
    if state^.sel_path <> nil then begin
        kfree(void(state^.sel_path));
        state^.sel_path := nil;
    end;
end;

procedure select_item(state: PFileBrowserState; row: Plv_obj;
                      path: pchar; isDir: boolean);
begin
    clear_selection(state);
    state^.sel_row    := row;
    state^.sel_path   := stringCopy(path);
    state^.sel_is_dir := isDir;
    { Highlight with selection colour }
    lv_obj_set_style_bg_color(row, lv_color_make(55, 75, 120), 0);
    { Update preview panel if visible }
    if state^.preview_visible then
        update_preview(state);
end;

{ ============================================================
  fb_mbox_close_cb — generic: close the parent msgbox
  ============================================================ }
procedure fb_mbox_close_cb(e: Plv_event); cdecl;
var
    mbox : Plv_obj;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    mbox := Plv_obj(lv_event_get_user_data(e));
    if mbox <> nil then lv_msgbox_close_async(mbox);
end;

{ ============================================================
  Phase 6a — Delete
  ============================================================ }

{ Callback from toolbar Delete button }
procedure fb_delete_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    yes_b : Plv_obj;
    no_b  : Plv_obj;
    s1    : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if (state = nil) or (state^.sel_path = nil) then exit;

    { Confirmation msgbox }
    mbox := lv_msgbox_create(lv_layer_top);
    lv_msgbox_add_title(mbox, 'Delete');
    s1 := stringConcat('Delete "', state^.sel_path);
    lv_msgbox_add_text(mbox, s1);
    kfree(void(s1));
    lv_msgbox_add_text(mbox, '"?');
    yes_b := lv_msgbox_add_footer_button(mbox, 'Delete');
    no_b  := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(yes_b, @fb_delete_confirm_cb, LV_EVENT_CLICKED, state);
    lv_obj_add_event_cb(no_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
end;

{ User confirmed deletion }
procedure fb_delete_confirm_cb(e: Plv_event); cdecl;
var
    state  : PFileBrowserState;
    mbox   : Plv_obj;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if (state = nil) or (state^.sel_path = nil) then exit;

    { Close the confirmation dialog }
    mbox := lv_obj_get_parent(lv_event_get_target_obj(e));
    if mbox <> nil then begin
        mbox := lv_obj_get_parent(mbox); { footer → msgbox }
        lv_msgbox_close_async(mbox);
    end;

    { Start async delete }
    state^.op_err := eNone;
    if state^.sel_is_dir then
        driver.storage.vfs.DeleteDirectoryAsync(
            state^.sel_path, @state^.op_err,
            @fb_delete_done, state)
    else
        driver.storage.vfs.DeleteFileAsync(
            state^.sel_path, @state^.op_err,
            @fb_delete_done, state);
end;

{ Async completion callback — runs in ISR/worker context, defer to LVGL }
procedure fb_delete_done(error: TError; userdata: pointer);
var
    state: PFileBrowserState;
begin
    state := PFileBrowserState(userdata);
    if state = nil then exit;
    state^.op_err := error;
    lv_timer_create(@fb_delete_done_timer, 1, state);
end;

{ Deferred UI update after delete }
procedure fb_delete_done_timer(tmr: Plv_timer); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    ok_b  : Plv_obj;
begin
    state := PFileBrowserState(lv_timer_get_user_data(tmr));
    lv_timer_delete(tmr);
    if state = nil then exit;
    if state^.op_err <> eNone then begin
        { Show error }
        mbox := lv_msgbox_create(lv_layer_top);
        lv_msgbox_add_title(mbox, 'Error');
        lv_msgbox_add_text(mbox, 'Could not delete item.');
        ok_b := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(ok_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
    end;
    clear_selection(state);
    schedule_refresh(state);
end;

{ ============================================================
  Phase 6b — Create Folder
  ============================================================ }



procedure fb_newfolder_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    cont  : Plv_obj;
    ta    : Plv_obj;
    ok_b  : Plv_obj;
    cancel_b : Plv_obj;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;

    mbox := lv_msgbox_create(lv_layer_top);
    lv_msgbox_add_title(mbox, 'New Folder');
    cont := lv_msgbox_get_content(mbox);
    ta := lv_textarea_create(cont);
    lv_textarea_set_one_line(ta, true);
    lv_textarea_set_text(ta, '');
    lv_obj_set_width(ta, lv_pct(100));
    lv_obj_set_user_data(mbox, ta);  { stash textarea ptr in msgbox }
    ok_b := lv_msgbox_add_footer_button(mbox, 'Create');
    cancel_b := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(ok_b, @fb_newfolder_ok_cb, LV_EVENT_CLICKED, state);
    lv_obj_set_user_data(ok_b, mbox); { stash msgbox in OK button }
    lv_obj_add_event_cb(cancel_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
end;

procedure fb_newfolder_ok_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    ta    : Plv_obj;
    name  : pchar;
    fp    : pchar;
    sep   : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    mbox := Plv_obj(lv_obj_get_user_data(lv_event_get_target_obj(e)));
    if mbox = nil then exit;
    ta := Plv_obj(lv_obj_get_user_data(mbox));
    if ta = nil then exit;
    name := lv_textarea_get_text(ta);
    if (name = nil) or (stringSize(name) = 0) then exit;

    { Build full path }
    if stringEquals(state^.cur_path, '/') then
        fp := stringConcat('/', name)
    else begin
        sep := stringConcat(state^.cur_path, '/');
        fp  := stringConcat(sep, name);
        kfree(void(sep));
    end;

    { Close dialog }
    lv_msgbox_close_async(mbox);

    { Signal worker process to create the directory (no disk I/O in LVGL) }
    if state^.wop_path1 <> nil then kfree(void(state^.wop_path1));
    state^.wop_path1  := fp;
    state^.wop_path2  := nil;
    state^.wop_result := eNone;
    puint32(@state^.wop_pending)^ := 1;  { 1 = mkdir }
end;

{ ============================================================
  Phase 6c — Rename
  ============================================================ }



procedure fb_rename_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    cont  : Plv_obj;
    ta    : Plv_obj;
    ok_b  : Plv_obj;
    cancel_b : Plv_obj;
    basename : pchar;
    len   : uint32;
    i     : sint32;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if (state = nil) or (state^.sel_path = nil) then exit;

    { Extract basename from sel_path }
    len := stringSize(state^.sel_path);
    i := sint32(len) - 1;
    while (i > 0) and (state^.sel_path[i] <> '/') do dec(i);
    basename := @state^.sel_path[i + 1];

    mbox := lv_msgbox_create(lv_layer_top);
    lv_msgbox_add_title(mbox, 'Rename');
    cont := lv_msgbox_get_content(mbox);
    ta := lv_textarea_create(cont);
    lv_textarea_set_one_line(ta, true);
    lv_textarea_set_text(ta, basename);
    lv_obj_set_width(ta, lv_pct(100));
    lv_obj_set_user_data(mbox, ta);
    ok_b := lv_msgbox_add_footer_button(mbox, 'Rename');
    cancel_b := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(ok_b, @fb_rename_ok_cb, LV_EVENT_CLICKED, state);
    lv_obj_set_user_data(ok_b, mbox);
    lv_obj_add_event_cb(cancel_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
end;

procedure fb_rename_ok_cb(e: Plv_event); cdecl;
var
    state  : PFileBrowserState;
    mbox   : Plv_obj;
    ta     : Plv_obj;
    name   : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if (state = nil) or (state^.sel_path = nil) then exit;
    mbox := Plv_obj(lv_obj_get_user_data(lv_event_get_target_obj(e)));
    if mbox = nil then exit;
    ta := Plv_obj(lv_obj_get_user_data(mbox));
    if ta = nil then exit;
    name := lv_textarea_get_text(ta);
    if (name = nil) or (stringSize(name) = 0) then exit;

    lv_msgbox_close_async(mbox);

    { Signal worker process to rename (no disk I/O in LVGL) }
    if state^.wop_path1 <> nil then kfree(void(state^.wop_path1));
    if state^.wop_path2 <> nil then kfree(void(state^.wop_path2));
    state^.wop_path1  := stringCopy(state^.sel_path);
    state^.wop_path2  := stringCopy(name);
    state^.wop_result := eNone;
    puint32(@state^.wop_pending)^ := 2;  { 2 = rename }
end;

{ ============================================================
  Phase 6d — Create File
  ============================================================ }

type
    PNewFileCtx = ^TNewFileCtx;
    TNewFileCtx = record
        state  : PFileBrowserState;
        handle : TFileHandle;
        err    : TError;
    end;

procedure fb_newfile_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    cont  : Plv_obj;
    ta    : Plv_obj;
    ok_b  : Plv_obj;
    cancel_b : Plv_obj;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;

    mbox := lv_msgbox_create(lv_layer_top);
    lv_msgbox_add_title(mbox, 'New File');
    cont := lv_msgbox_get_content(mbox);
    ta := lv_textarea_create(cont);
    lv_textarea_set_one_line(ta, true);
    lv_textarea_set_text(ta, '');
    lv_obj_set_width(ta, lv_pct(100));
    lv_obj_set_user_data(mbox, ta);
    ok_b := lv_msgbox_add_footer_button(mbox, 'Create');
    cancel_b := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(ok_b, @fb_newfile_ok_cb, LV_EVENT_CLICKED, state);
    lv_obj_set_user_data(ok_b, mbox);
    lv_obj_add_event_cb(cancel_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
end;

procedure fb_newfile_ok_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    mbox  : Plv_obj;
    ta    : Plv_obj;
    name  : pchar;
    fp    : pchar;
    sep   : pchar;
    nfctx : PNewFileCtx;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    mbox := Plv_obj(lv_obj_get_user_data(lv_event_get_target_obj(e)));
    if mbox = nil then exit;
    ta := Plv_obj(lv_obj_get_user_data(mbox));
    if ta = nil then exit;
    name := lv_textarea_get_text(ta);
    if (name = nil) or (stringSize(name) = 0) then exit;

    { Build full path }
    if stringEquals(state^.cur_path, '/') then
        fp := stringConcat('/', name)
    else begin
        sep := stringConcat(state^.cur_path, '/');
        fp  := stringConcat(sep, name);
        kfree(void(sep));
    end;

    lv_msgbox_close_async(mbox);

    { Use async open to create the file }
    nfctx := PNewFileCtx(kalloc(sizeof(TNewFileCtx)));
    nfctx^.state  := state;
    nfctx^.err    := eNone;
    nfctx^.handle := 0;
    driver.storage.vfs.OpenFileAsync(fp, omCreate, nfctx^.handle,
                                     @nfctx^.err, @fb_newfile_opened, nfctx);
    kfree(void(fp));
end;

{ Async step 1: file descriptor opened — now write 0 bytes to create dir entry }
procedure fb_newfile_opened(error: TError; userdata: pointer);
var
    nfctx : PNewFileCtx;
begin
    nfctx := PNewFileCtx(userdata);
    if nfctx = nil then exit;
    nfctx^.err := error;
    if (error = eNone) and (nfctx^.handle <> 0) then begin
        { WriteFileAsync needs a non-nil buffer; Length=0 so it is never read }
        driver.storage.vfs.WriteFileAsync(nfctx^.handle, 0,
            puint8(@nfctx^.err), 0, @fb_newfile_written, nfctx);
    end else begin
        if nfctx^.handle <> 0 then
            driver.storage.vfs.CloseFile(nfctx^.handle);
        lv_timer_create(@fb_newfile_done_timer, 1, nfctx);
    end;
end;

{ Async step 2: write complete — close handle and schedule UI refresh }
procedure fb_newfile_written(error: TError; userdata: pointer);
var
    nfctx : PNewFileCtx;
begin
    nfctx := PNewFileCtx(userdata);
    if nfctx = nil then exit;
    if error <> eNone then nfctx^.err := error;
    if nfctx^.handle <> 0 then
        driver.storage.vfs.CloseFile(nfctx^.handle);
    lv_timer_create(@fb_newfile_done_timer, 1, nfctx);
end;

procedure fb_newfile_done_timer(tmr: Plv_timer); cdecl;
var
    nfctx : PNewFileCtx;
    mbox  : Plv_obj;
    ok_b  : Plv_obj;
begin
    nfctx := PNewFileCtx(lv_timer_get_user_data(tmr));
    lv_timer_delete(tmr);
    if nfctx = nil then exit;

    if nfctx^.err <> eNone then begin
        mbox := lv_msgbox_create(lv_layer_top);
        lv_msgbox_add_title(mbox, 'Error');
        lv_msgbox_add_text(mbox, 'Could not create file.');
        ok_b := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(ok_b, @fb_mbox_close_cb, LV_EVENT_CLICKED, mbox);
    end;

    if nfctx^.state <> nil then
        schedule_refresh(nfctx^.state);
    kfree(void(nfctx));
end;

{ ============================================================
  Phase 8 — Tabs
  ============================================================ }

{ save_tab — snapshot current live state into tabs[idx] }
procedure save_tab(state: PFileBrowserState; idx: uint32);
var
    snap : PTabSnapshot;
    i    : uint32;
begin
    if idx >= MAX_TABS then exit;
    { Free old snapshot if any }
    if state^.tabs[idx] <> nil then
        free_tab_snapshot(state^.tabs[idx]);
    snap := PTabSnapshot(kalloc(sizeof(TTabSnapshot)));
    memset(uint32(snap), 0, sizeof(TTabSnapshot));
    if state^.cur_path <> nil then
        snap^.cur_path := stringCopy(state^.cur_path)
    else
        snap^.cur_path := stringCopy('/');
    snap^.hist_len := state^.hist_len;
    snap^.hist_pos := state^.hist_pos;
    snap^.item_count := state^.item_count;
    if snap^.hist_len > 0 then
        for i := 0 to snap^.hist_len - 1 do
            if state^.history[i] <> nil then
                snap^.history[i] := stringCopy(state^.history[i])
            else
                snap^.history[i] := nil;
    if state^.sel_path <> nil then
        snap^.sel_path := stringCopy(state^.sel_path)
    else
        snap^.sel_path := nil;
    snap^.sel_is_dir := state^.sel_is_dir;
    if state^.filter_text <> nil then
        snap^.filter_text := stringCopy(state^.filter_text)
    else
        snap^.filter_text := nil;
    state^.tabs[idx] := snap;
end;

{ restore_tab — load tabs[idx] into the live state (clears old live state) }
procedure restore_tab(state: PFileBrowserState; idx: uint32);
var
    snap : PTabSnapshot;
    i    : uint32;
begin
    if idx >= MAX_TABS then exit;
    snap := state^.tabs[idx];
    if snap = nil then exit;

    { Free current live history }
    if state^.hist_len > 0 then
        for i := 0 to state^.hist_len - 1 do
            if state^.history[i] <> nil then begin
                kfree(void(state^.history[i]));
                state^.history[i] := nil;
            end;
    if state^.cur_path <> nil then kfree(void(state^.cur_path));
    if state^.sel_path <> nil then begin
        kfree(void(state^.sel_path));
        state^.sel_path := nil;
    end;
    state^.sel_row := nil;

    { Restore from snapshot }
    if snap^.cur_path <> nil then
        state^.cur_path := stringCopy(snap^.cur_path)
    else
        state^.cur_path := stringCopy('/');
    state^.hist_len := snap^.hist_len;
    state^.hist_pos := snap^.hist_pos;
    state^.item_count := snap^.item_count;
    if snap^.hist_len > 0 then
        for i := 0 to snap^.hist_len - 1 do
            if snap^.history[i] <> nil then
                state^.history[i] := stringCopy(snap^.history[i])
            else
                state^.history[i] := nil;
    if snap^.sel_path <> nil then
        state^.sel_path := stringCopy(snap^.sel_path)
    else
        state^.sel_path := nil;
    state^.sel_is_dir := snap^.sel_is_dir;
    { Restore filter text }
    if state^.filter_text <> nil then begin
        kfree(void(state^.filter_text));
        state^.filter_text := nil;
    end;
    if snap^.filter_text <> nil then
        state^.filter_text := stringCopy(snap^.filter_text);
    { Update filter textarea if present }
    if state^.filter_ta <> nil then begin
        if state^.filter_text <> nil then
            lv_textarea_set_text(state^.filter_ta, state^.filter_text)
        else
            lv_textarea_set_text(state^.filter_ta, '');
    end;
end;

{ switch_tab — save current, restore target, refresh UI }
procedure switch_tab(state: PFileBrowserState; idx: uint32);
begin
    if idx >= state^.tab_count then exit;
    if idx = state^.active_tab then exit;
    { Save current tab state }
    save_tab(state, state^.active_tab);
    { Restore target tab }
    restore_tab(state, idx);
    state^.active_tab := idx;
    update_nav_btns(state);
    build_breadcrumbs(state);
    rebuild_tab_bar(state);
    schedule_refresh(state);
end;

{ add_tab — create a new tab with given path }
procedure add_tab(state: PFileBrowserState; path: pchar);
var
    snap : PTabSnapshot;
begin
    if state^.tab_count >= MAX_TABS then exit;
    { Save current tab first }
    save_tab(state, state^.active_tab);
    { Create snapshot for new tab }
    snap := PTabSnapshot(kalloc(sizeof(TTabSnapshot)));
    memset(uint32(snap), 0, sizeof(TTabSnapshot));
    snap^.cur_path := stringCopy(path);
    snap^.hist_len := 0;
    snap^.hist_pos := 0;
    state^.tabs[state^.tab_count] := snap;
    state^.active_tab := state^.tab_count;
    state^.tab_count  := state^.tab_count + 1;
    { Restore it into live state }
    restore_tab(state, state^.active_tab);
    { Navigate (pushes history) }
    navigate_to(state, path);
    rebuild_tab_bar(state);
end;

{ close_tab — close tab at idx, switch to neighbour }
procedure close_tab(state: PFileBrowserState; idx: uint32);
var
    i     : uint32;
    newIdx: uint32;
begin
    if state^.tab_count <= 1 then exit; { must keep >=1 tab }
    if idx >= state^.tab_count then exit;

    { If closing the active tab, save first so we don't lose data }
    if idx = state^.active_tab then begin
        { Don't save — we're discarding it }
    end else begin
        save_tab(state, state^.active_tab);
    end;

    { Free the snapshot }
    if state^.tabs[idx] <> nil then begin
        free_tab_snapshot(state^.tabs[idx]);
        state^.tabs[idx] := nil;
    end;

    { Shift tabs down }
    if idx < state^.tab_count - 1 then
        for i := idx to state^.tab_count - 2 do begin
            state^.tabs[i]     := state^.tabs[i + 1];
            state^.tab_btns[i] := state^.tab_btns[i + 1];
        end;
    state^.tabs[state^.tab_count - 1]     := nil;
    state^.tab_btns[state^.tab_count - 1] := nil;
    state^.tab_count := state^.tab_count - 1;

    { Determine new active index }
    if idx = state^.active_tab then begin
        if idx >= state^.tab_count then
            newIdx := state^.tab_count - 1
        else
            newIdx := idx;
        state^.active_tab := newIdx;
        restore_tab(state, newIdx);
        update_nav_btns(state);
        build_breadcrumbs(state);
        schedule_refresh(state);
    end else begin
        { Active tab index may have shifted }
        if state^.active_tab > idx then
            state^.active_tab := state^.active_tab - 1;
        restore_tab(state, state^.active_tab);
    end;
    rebuild_tab_bar(state);
end;

{ rebuild_tab_bar — recreate tab buttons to reflect current state }
procedure rebuild_tab_bar(state: PFileBrowserState);
var
    bar     : Plv_obj;
    btn     : Plv_obj;
    lbl     : Plv_obj;
    close_b : Plv_obj;
    plus_b  : Plv_obj;
    i       : uint32;
    snap    : PTabSnapshot;
    name    : pchar;
    len     : uint32;
    j       : sint32;
begin
    bar := state^.tab_bar;
    if bar = nil then exit;
    lv_obj_clean(bar);

    if state^.tab_count > 0 then
    for i := 0 to state^.tab_count - 1 do begin
        { For active tab, use live state; for others, snapshot }
        if i = state^.active_tab then
            name := state^.cur_path
        else begin
            snap := state^.tabs[i];
            if (snap <> nil) and (snap^.cur_path <> nil) then
                name := snap^.cur_path
            else
                name := '/';
        end;

        { Extract last segment for display }
        len := stringSize(name);
        if len > 1 then begin
            j := sint32(len) - 1;
            if name[j] = '/' then dec(j);
            while (j > 0) and (name[j] <> '/') do dec(j);
            name := @name[j + 1];
        end;

        btn := lv_button_create(bar);
        lv_obj_remove_style_all(btn);
        lv_obj_set_size(btn, LV_SIZE_CONTENT, 22);
        lv_obj_set_style_pad_left(btn, 8, 0);
        lv_obj_set_style_pad_right(btn, 4, 0);
        lv_obj_set_style_radius(btn, 4, 0);
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(btn, 4, 0);

        if i = state^.active_tab then begin
            lv_obj_set_style_bg_color(btn, lv_color_make(50, 55, 72), 0);
            lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
        end else begin
            lv_obj_set_style_bg_color(btn, lv_color_make(35, 38, 50), 0);
            lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
        end;

        lbl := lv_label_create(btn);
        lv_label_set_text(lbl, name);
        lv_obj_set_style_text_color(lbl, lv_color_make(190, 198, 220), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

        lv_obj_set_user_data(btn, pointer(i));
        lv_obj_add_event_cb(btn, @fb_tab_cb, LV_EVENT_CLICKED, state);
        state^.tab_btns[i] := btn;

        { Close button (x) on each tab }
        if state^.tab_count > 1 then begin
            close_b := lv_label_create(btn);
            lv_label_set_text(close_b, 'x');
            lv_obj_set_style_text_color(close_b, lv_color_make(140, 140, 160), 0);
            lv_obj_set_style_text_font(close_b, @lv_font_montserrat_14, 0);
            lv_obj_add_flag(close_b, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_user_data(close_b, pointer(i));
            lv_obj_add_event_cb(close_b, @fb_tab_close_cb, LV_EVENT_CLICKED, state);
        end;
    end;

    { "+" button to add new tab }
    if state^.tab_count < MAX_TABS then begin
        plus_b := lv_button_create(bar);
        lv_obj_remove_style_all(plus_b);
        lv_obj_set_size(plus_b, 24, 22);
        lv_obj_set_style_bg_color(plus_b, lv_color_make(35, 38, 50), 0);
        lv_obj_set_style_bg_opa(plus_b, LV_OPA_COVER, 0);
        lv_obj_set_style_radius(plus_b, 4, 0);
        lv_obj_add_flag(plus_b, LV_OBJ_FLAG_CLICKABLE);
        lbl := lv_label_create(plus_b);
        lv_label_set_text(lbl, '+');
        lv_obj_set_style_text_color(lbl, lv_color_make(140, 150, 170), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lv_obj_center(lbl);
        lv_obj_add_event_cb(plus_b, @fb_tab_new_cb, LV_EVENT_CLICKED, state);
    end;
end;

{ Tab click — switch to this tab }
procedure fb_tab_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    btn   : Plv_obj;
    idx   : uint32;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    btn := lv_event_get_target_obj(e);
    idx := uint32(lv_obj_get_user_data(btn));
    switch_tab(state, idx);
end;

{ Tab close (x) click }
procedure fb_tab_close_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    lbl   : Plv_obj;
    idx   : uint32;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    lbl := lv_event_get_target_obj(e);
    idx := uint32(lv_obj_get_user_data(lbl));
    close_tab(state, idx);
end;

{ "+" button — new tab at current path }
procedure fb_tab_new_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    add_tab(state, state^.cur_path);
end;

{ ============================================================
  Phase 10 — Quick filter
  ============================================================ }

{ fb_filter_changed_cb — re-render rows with current filter text }
procedure fb_filter_changed_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    txt   : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_VALUE_CHANGED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    { Update filter_text from textarea }
    if state^.filter_text <> nil then begin
        kfree(void(state^.filter_text));
        state^.filter_text := nil;
    end;
    txt := lv_textarea_get_text(state^.filter_ta);
    if (txt <> nil) and (stringSize(txt) > 0) then
        state^.filter_text := stringCopy(txt);
    schedule_refresh(state);
end;

{ fb_filter_clear_cb — clear filter text and refresh }
procedure fb_filter_clear_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.filter_text <> nil then begin
        kfree(void(state^.filter_text));
        state^.filter_text := nil;
    end;
    if state^.filter_ta <> nil then
        lv_textarea_set_text(state^.filter_ta, '');
    schedule_refresh(state);
end;

{ ============================================================
  Phase 11 — Type-ahead jump-to
  ============================================================ }

{ fb_typeahead_reset_timer — clear type-ahead buffer after 1s inactivity }
procedure fb_typeahead_reset_timer(tmr: Plv_timer); cdecl;
var
    state: PFileBrowserState;
begin
    state := PFileBrowserState(lv_timer_get_user_data(tmr));
    lv_timer_delete(tmr);
    if state <> nil then begin
        state^.ta_len   := 0;
        state^.ta_buf[0]:= #0;
        state^.ta_timer := nil;
    end;
end;

{ fb_typeahead_key_cb — handle key presses on content area for jump-to }
procedure fb_typeahead_key_cb(e: Plv_event); cdecl;
var
    state   : PFileBrowserState;
    key     : uint32;
    ch      : char;
    n, i    : uint32;
    child   : Plv_obj;
    firstLbl: Plv_obj;
    lblText : pchar;
    isDir   : boolean;
    ud      : pchar;
    baseName: pchar;
    bLen    : uint32;
    j       : sint32;
begin
    if lv_event_get_code(e) <> LV_EVENT_KEY then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    key := lv_event_get_key(e);

    { Only handle printable ASCII }
    if (key < 32) or (key > 126) then exit;
    ch := char(key);

    { Append to buf (guard overflow) }
    if state^.ta_len >= 31 then exit;
    state^.ta_buf[state^.ta_len] := ch;
    state^.ta_len := state^.ta_len + 1;
    state^.ta_buf[state^.ta_len] := #0;

    { Reset/restart the 1-second timer }
    if state^.ta_timer <> nil then
        lv_timer_delete(state^.ta_timer);
    state^.ta_timer := lv_timer_create(@fb_typeahead_reset_timer, 1000, state);

    { Search children of content_area for first match }
    n := lv_obj_get_child_count(state^.content_area);
    if n = 0 then exit;
    for i := 0 to n - 1 do begin
        child := lv_obj_get_child(state^.content_area, sint32(i));
        if child = nil then continue;
        ud := pchar(lv_obj_get_user_data(child));
        if ud = nil then continue;
        { Extract basename from full path in user_data }
        bLen := stringSize(ud);
        if bLen = 0 then continue;
        j := sint32(bLen) - 1;
        if ud[j] = '/' then dec(j);
        while (j > 0) and (ud[j] <> '/') do dec(j);
        if ud[j] = '/' then inc(j);
        baseName := @ud[j];
        if stringStartsWithCI(baseName, @state^.ta_buf[0]) then begin
            lv_obj_scroll_to_view(child, LV_ANIM_ON);
            { Dir rows have first label text starting with '[' }
            isDir := false;
            if lv_obj_get_child_count(child) > 0 then begin
                firstLbl := lv_obj_get_child(child, 0);
                if firstLbl <> nil then begin
                    lblText := lv_label_get_text(firstLbl);
                    if (lblText <> nil) and (lblText[0] = '[') then
                        isDir := true;
                end;
            end;
            select_item(state, child, ud, isDir);
            exit;
        end;
    end;
end;

{ ============================================================
  Phase 13 — Compact view toggle
  ============================================================ }
procedure fb_viewmode_toggle_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.view_mode = vmDetail then
        state^.view_mode := vmCompact
    else
        state^.view_mode := vmDetail;
    schedule_refresh(state);
end;

{ ============================================================
  Phase 14 — Column header sorting
  ============================================================ }

procedure fb_header_name_cb(e: Plv_event); cdecl;
var state: PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.sort_col = 0 then
        state^.sort_asc := not state^.sort_asc
    else begin
        state^.sort_col := 0;
        state^.sort_asc := true;
    end;
    schedule_refresh(state);
end;

procedure fb_header_size_cb(e: Plv_event); cdecl;
var state: PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.sort_col = 1 then
        state^.sort_asc := not state^.sort_asc
    else begin
        state^.sort_col := 1;
        state^.sort_asc := true;
    end;
    schedule_refresh(state);
end;

procedure fb_header_type_cb(e: Plv_event); cdecl;
var state: PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    if state^.sort_col = 2 then
        state^.sort_asc := not state^.sort_asc
    else begin
        state^.sort_col := 2;
        state^.sort_asc := true;
    end;
    schedule_refresh(state);
end;

{ ============================================================
  Phase 15 — Hidden files toggle
  ============================================================ }
procedure fb_hidden_toggle_cb(e: Plv_event); cdecl;
var state: PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    state^.show_hidden := not state^.show_hidden;
    schedule_refresh(state);
end;

{ ============================================================
  Phase 17 — WatchDirectory live refresh
  ============================================================ }

{ fb_watch_cb — called from VFS context when directory changes.
  MUST NOT call LVGL or disk I/O; just sets a flag. }
procedure fb_watch_cb(event: TVFSWatchEvent; path: pchar; userdata: pointer);
var state: PFileBrowserState;
begin
    state := PFileBrowserState(userdata);
    if state <> nil then
        state^.watch_dirty := true;
end;

{ fb_watch_poll_timer — 500ms LVGL timer; checks dirty flag and refreshes }
procedure fb_watch_poll_timer(tmr: Plv_timer); cdecl;
var state: PFileBrowserState;
begin
    state := PFileBrowserState(lv_timer_get_user_data(tmr));
    if state = nil then exit;
    if state^.watch_dirty then begin
        state^.watch_dirty := false;
        schedule_refresh(state);
    end;
end;

{ ============================================================
  Phase 12 — File preview panel
  ============================================================ }

{ update_preview — refresh the preview panel content }
procedure update_preview(state: PFileBrowserState);
var
    panel    : Plv_obj;
    lbl      : Plv_obj;
    sep      : Plv_obj;
    baseName : pchar;
    szStr    : pchar;
    extStr   : pchar;
    len      : uint32;
    j        : sint32;
begin
    panel := state^.preview_panel;
    if panel = nil then exit;
    lv_obj_clean(panel);

    if not state^.preview_visible then exit;

    if (state^.sel_path = nil) or (stringSize(state^.sel_path) = 0) then begin
        lbl := lv_label_create(panel);
        lv_label_set_text(lbl, 'No selection');
        lv_obj_set_style_text_color(lbl, lv_color_make(100, 110, 130), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        exit;
    end;

    { Header }
    lbl := lv_label_create(panel);
    lv_label_set_text(lbl, 'Preview');
    lv_obj_set_style_text_color(lbl, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

    sep := lv_obj_create(panel);
    lv_obj_remove_style_all(sep);
    lv_obj_set_size(sep, lv_pct(100), 1);
    lv_obj_set_style_bg_color(sep, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_bg_opa(sep, LV_OPA_COVER, 0);

    { Extract basename }
    len := stringSize(state^.sel_path);
    j := sint32(len) - 1;
    if (j > 0) and (state^.sel_path[j] = '/') then dec(j);
    while (j > 0) and (state^.sel_path[j] <> '/') do dec(j);
    if state^.sel_path[j] = '/' then inc(j);
    baseName := @state^.sel_path[j];

    { Name }
    lbl := lv_label_create(panel);
    lv_label_set_text(lbl, baseName);
    lv_obj_set_style_text_color(lbl, lv_color_make(220, 225, 240), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl, lv_pct(100));

    { Type }
    lbl := lv_label_create(panel);
    if state^.sel_is_dir then
        lv_label_set_text(lbl, 'Type: Directory')
    else begin
        extStr := getFileExtension(baseName);
        if extStr <> nil then begin
            szStr := stringConcat('Type: ', extStr);
            lv_label_set_text(lbl, szStr);
            kfree(void(szStr));
        end else
            lv_label_set_text(lbl, 'Type: File');
    end;
    lv_obj_set_style_text_color(lbl, lv_color_make(160, 168, 190), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

    { Full path }
    lbl := lv_label_create(panel);
    lv_label_set_text(lbl, state^.sel_path);
    lv_obj_set_style_text_color(lbl, lv_color_make(120, 128, 150), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl, lv_pct(100));

    { For directories: show type indicator (no disk I/O per Lesson #10) }
    if state^.sel_is_dir then begin
        lbl := lv_label_create(panel);
        lv_label_set_text(lbl, SYM_DIRECTORY + ' Folder');
        lv_obj_set_style_text_color(lbl, lv_color_make(160, 168, 190), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    end;
end;

{ fb_preview_toggle_cb — toggle preview panel visibility }
procedure fb_preview_toggle_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    state^.preview_visible := not state^.preview_visible;
    if state^.preview_panel <> nil then begin
        if state^.preview_visible then begin
            lv_obj_remove_flag(state^.preview_panel, LV_OBJ_FLAG_HIDDEN);
            update_preview(state);
        end else
            lv_obj_add_flag(state^.preview_panel, LV_OBJ_FLAG_HIDDEN);
    end;
end;

{ ============================================================
  Phase 9 — Bookmarks sidebar
  ============================================================ }

{ add_bookmark_entry — add a path to the bookmarks list }
procedure add_bookmark_entry(state: PFileBrowserState; path: pchar);
var
    i : uint32;
begin
    if state^.bm_count >= MAX_BOOKMARKS then exit;
    { Check for duplicates }
    if state^.bm_count > 0 then
        for i := 0 to state^.bm_count - 1 do
            if stringEquals(state^.bookmarks[i], path) then exit;
    state^.bookmarks[state^.bm_count] := stringCopy(path);
    state^.bm_count := state^.bm_count + 1;
    rebuild_bookmarks(state);
end;

{ remove_bookmark_entry — remove bookmark at idx }
procedure remove_bookmark_entry(state: PFileBrowserState; idx: uint32);
var
    i : uint32;
begin
    if idx >= state^.bm_count then exit;
    if state^.bookmarks[idx] <> nil then
        kfree(void(state^.bookmarks[idx]));
    { Shift remainder down }
    if idx < state^.bm_count - 1 then
        for i := idx to state^.bm_count - 2 do
            state^.bookmarks[i] := state^.bookmarks[i + 1];
    state^.bookmarks[state^.bm_count - 1] := nil;
    state^.bm_count := state^.bm_count - 1;
    rebuild_bookmarks(state);
end;

{ fb_bookmark_click_cb — navigate to bookmarked path }
procedure fb_bookmark_click_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    btn   : Plv_obj;
    path  : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    btn := lv_event_get_target_obj(e);
    path := pchar(lv_obj_get_user_data(btn));
    if path <> nil then
        navigate_to(state, path);
end;

{ fb_bookmark_ctx_cb — right-click (long press) to remove bookmark }
procedure fb_bookmark_ctx_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
    btn   : Plv_obj;
    path  : pchar;
    i     : uint32;
begin
    if lv_event_get_code(e) <> LV_EVENT_LONG_PRESSED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    btn := lv_event_get_target_obj(e);
    path := pchar(lv_obj_get_user_data(btn));
    if path = nil then exit;
    { Find matching bookmark index }
    if state^.bm_count > 0 then
        for i := 0 to state^.bm_count - 1 do
            if stringEquals(state^.bookmarks[i], path) then begin
                remove_bookmark_entry(state, i);
                exit;
            end;
end;

{ fb_bookmark_add_cb — "+" button adds current directory }
procedure fb_bookmark_add_cb(e: Plv_event); cdecl;
var
    state : PFileBrowserState;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    add_bookmark_entry(state, state^.cur_path);
end;

{ rebuild_bookmarks — recreate sidebar bookmark list }
procedure rebuild_bookmarks(state: PFileBrowserState);
var
    bar     : Plv_obj;
    btn     : Plv_obj;
    lbl     : Plv_obj;
    plus_b  : Plv_obj;
    sep     : Plv_obj;
    i       : uint32;
    name    : pchar;
    len     : uint32;
    j       : sint32;
begin
    bar := state^.sidebar;
    if bar = nil then exit;
    { Free user_data (stringCopy'd paths) from old buttons }
    free_children_userdata(bar);
    lv_obj_clean(bar);

    { Header label }
    lbl := lv_label_create(bar);
    lv_label_set_text(lbl, 'Bookmarks');
    lv_obj_set_style_text_color(lbl, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_style_pad_bottom(lbl, 4, 0);

    { Separator line }
    sep := lv_obj_create(bar);
    lv_obj_remove_style_all(sep);
    lv_obj_set_size(sep, lv_pct(100), 1);
    lv_obj_set_style_bg_color(sep, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_bg_opa(sep, LV_OPA_COVER, 0);

    if state^.bm_count > 0 then
    for i := 0 to state^.bm_count - 1 do begin
        name := state^.bookmarks[i];
        if name = nil then continue;

        btn := lv_obj_create(bar);
        lv_obj_remove_style_all(btn);
        lv_obj_set_size(btn, lv_pct(100), 24);
        lv_obj_set_style_bg_color(btn, lv_color_make(35, 38, 50), 0);
        lv_obj_set_style_bg_opa(btn, LV_OPA_80, 0);
        lv_obj_set_style_radius(btn, 4, 0);
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_bg_color(btn, lv_color_make(50, 55, 72), uint32(LV_STATE_PRESSED));
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, uint32(LV_STATE_PRESSED));
        lv_obj_set_style_pad_left(btn, 6, 0);

        { Extract last path segment for display }
        len := stringSize(name);
        if len <= 1 then
            name := '/'
        else begin
            j := sint32(len) - 1;
            if name[j] = '/' then dec(j);
            while (j > 0) and (name[j] <> '/') do dec(j);
            name := @state^.bookmarks[i][j + 1];
        end;

        lbl := lv_label_create(btn);
        lv_label_set_text(lbl, name);
        lv_obj_set_style_text_color(lbl, lv_color_make(190, 198, 220), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lv_obj_align(lbl, LV_ALIGN_LEFT_MID, 0, 0);

        lv_obj_set_user_data(btn, void(stringCopy(state^.bookmarks[i])));
        lv_obj_add_event_cb(btn, @fb_bookmark_click_cb, LV_EVENT_CLICKED, state);
        lv_obj_add_event_cb(btn, @fb_bookmark_ctx_cb, LV_EVENT_LONG_PRESSED, state);
    end;

    { "+" Add Bookmark button }
    plus_b := lv_obj_create(bar);
    lv_obj_remove_style_all(plus_b);
    lv_obj_set_size(plus_b, lv_pct(100), 24);
    lv_obj_set_style_bg_color(plus_b, lv_color_make(30, 33, 44), 0);
    lv_obj_set_style_bg_opa(plus_b, LV_OPA_80, 0);
    lv_obj_set_style_radius(plus_b, 4, 0);
    lv_obj_add_flag(plus_b, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_bg_color(plus_b, lv_color_make(50, 55, 72), uint32(LV_STATE_PRESSED));
    lv_obj_set_style_bg_opa(plus_b, LV_OPA_COVER, uint32(LV_STATE_PRESSED));
    lv_obj_set_style_pad_left(plus_b, 6, 0);
    lbl := lv_label_create(plus_b);
    lv_label_set_text(lbl, '+ Add');
    lv_obj_set_style_text_color(lbl, lv_color_make(100, 110, 140), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_align(lbl, LV_ALIGN_LEFT_MID, 0, 0);
    lv_obj_add_event_cb(plus_b, @fb_bookmark_add_cb, LV_EVENT_CLICKED, state);
end;

{ ============================================================
  Phase 7 — Context menu
  ============================================================ }

const
    CTX_ACT_OPEN    = 1;
    CTX_ACT_RENAME  = 2;
    CTX_ACT_DELETE  = 3;
    CTX_ACT_NEWFOLD = 4;
    CTX_ACT_NEWFILE = 5;
    CTX_ACT_REFRESH = 6;

procedure destroy_context_menu(state: PFileBrowserState);
begin
    if state^.ctx_menu <> nil then begin
        lv_obj_delete(state^.ctx_menu);
        state^.ctx_menu := nil;
    end;
end;

{ Helper: add one menu row }
function ctx_add_item(parent: Plv_obj; text: pchar;
                      action: uint32; state: PFileBrowserState): Plv_obj;
var
    btn : Plv_obj;
    lbl : Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, lv_pct(100), 26);
    lv_obj_set_style_bg_color(btn, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_TRANSP, 0);
    lv_obj_set_style_bg_color(btn, lv_color_make(60, 68, 90), LV_STATE_PRESSED);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_STATE_PRESSED);
    lv_obj_set_style_pad_left(btn, 10, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_user_data(btn, pointer(action));
    lv_obj_add_event_cb(btn, @fb_ctx_item_cb, LV_EVENT_CLICKED, state);
    ctx_add_item := btn;
end;

procedure show_context_menu(state: PFileBrowserState; mx, my: sint32);
var
    menu : Plv_obj;
begin
    destroy_context_menu(state);

    menu := lv_obj_create(lv_layer_top);
    lv_obj_remove_style_all(menu);
    lv_obj_set_pos(menu, mx, my);
    lv_obj_set_size(menu, 140, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(menu, lv_color_make(38, 42, 56), 0);
    lv_obj_set_style_bg_opa(menu, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(menu, lv_color_make(70, 78, 100), 0);
    lv_obj_set_style_border_width(menu, 1, 0);
    lv_obj_set_style_radius(menu, 6, 0);
    lv_obj_set_style_pad_all(menu, 4, 0);
    lv_obj_set_style_pad_row(menu, 1, 0);
    lv_obj_set_style_layout(menu, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(menu, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(menu, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_shadow_width(menu, 8, 0);
    lv_obj_set_style_shadow_opa(menu, 120, 0);
    lv_obj_set_style_shadow_color(menu, lv_color_make(0, 0, 0), 0);

    { Contextual items when an item is selected }
    if state^.sel_path <> nil then begin
        if state^.sel_is_dir then
            ctx_add_item(menu, 'Open', CTX_ACT_OPEN, state);
        ctx_add_item(menu, 'Rename', CTX_ACT_RENAME, state);
        ctx_add_item(menu, 'Delete', CTX_ACT_DELETE, state);
    end;

    { Always-visible items }
    ctx_add_item(menu, 'New Folder', CTX_ACT_NEWFOLD, state);
    ctx_add_item(menu, 'New File', CTX_ACT_NEWFILE, state);
    ctx_add_item(menu, 'Refresh', CTX_ACT_REFRESH, state);

    state^.ctx_menu := menu;
end;

procedure fb_ctx_item_cb(e: Plv_event); cdecl;
var
    code   : lv_event_code_t;
    state  : PFileBrowserState;
    btn    : Plv_obj;
    action : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    btn := lv_event_get_target_obj(e);
    action := uint32(lv_obj_get_user_data(btn));

    { Close context menu first }
    destroy_context_menu(state);

    case action of
        CTX_ACT_OPEN: begin
            if (state^.sel_path <> nil) and state^.sel_is_dir then
                navigate_to(state, state^.sel_path);
        end;
        CTX_ACT_RENAME: begin
            if state^.sel_path <> nil then begin
                { Synthesize a fake LVGL event to reuse fb_rename_cb
                  — simpler to just inline the rename dialog creation }
                fb_rename_cb(e);
            end;
        end;
        CTX_ACT_DELETE: begin
            if state^.sel_path <> nil then
                fb_delete_cb(e);
        end;
        CTX_ACT_NEWFOLD: fb_newfolder_cb(e);
        CTX_ACT_NEWFILE: fb_newfile_cb(e);
        CTX_ACT_REFRESH: schedule_refresh(state);
    end;
end;

{ LVGL long-press callback: select row and show context menu }
procedure fb_row_long_press_cb(e: Plv_event); cdecl;
var
    state  : PFileBrowserState;
    row    : Plv_obj;
    path   : pchar;
    isDir  : boolean;
    coords : lv_area_t;
begin
    if lv_event_get_code(e) <> LV_EVENT_LONG_PRESSED then exit;
    state := PFileBrowserState(lv_event_get_user_data(e));
    if state = nil then exit;
    row := lv_event_get_target_obj(e);
    if row = nil then exit;

    path := pchar(lv_obj_get_user_data(row));
    if path <> nil then begin
        isDir := lv_obj_has_flag(row, LV_OBJ_FLAG_USER_1);
        select_item(state, row, path, isDir);
    end;

    { Position context menu at the row's screen coordinates }
    lv_obj_get_coords(row, @coords);
    show_context_menu(state, coords.x2, coords.y1);
end;

{ Timer to dismiss context menu when clicking elsewhere }
procedure fb_ctx_dismiss_timer(tmr: Plv_timer); cdecl;
var
    state: PFileBrowserState;
begin
    state := PFileBrowserState(lv_timer_get_user_data(tmr));
    lv_timer_delete(tmr);
    if state <> nil then
        destroy_context_menu(state);
end;

{ ============================================================
  makeToolBtn — compact toolbar button helper
  ============================================================ }
function makeToolBtn(parent: Plv_obj; text: pchar; w: sint32;
                     ud: pointer; cb: lv_event_cb_t): Plv_obj;
var
    btn, lbl_obj : Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, w, 28);
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
    if cb <> nil then
        lv_obj_add_event_cb(btn, cb, LV_EVENT_CLICKED, ud);
    makeToolBtn := btn;
end;

{ ============================================================
  launch — create the window and populate the initial UI
  ============================================================ }
procedure launch;
var
    scr_w, scr_h : sint32;
    wx, wy       : sint32;
    content      : Plv_obj;
    toolbar      : Plv_obj;
    statusbar    : Plv_obj;
    main_area    : Plv_obj;
    body_row     : Plv_obj;
    sidebar      : Plv_obj;
    sl           : Plv_obj;
    state        : PFileBrowserState;
    ctx          : PProcessContext;
begin
    debug.tracer.push_trace('filebrowser.launch');

    { Single instance guard }
    if driver.video.windows.isWindowOpen(g_win_id) then begin
        debug.tracer.pop_trace; exit;
    end;

    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);
    wx    := (scr_w - WIN_W) div 2;
    wy    := (scr_h - WIN_H) div 2 - 30;

    g_win_id := driver.video.windows.createWindow('Files', wx, wy, WIN_W, WIN_H,
                                                  @onClose, nil);
    if g_win_id = 0 then begin
        debug.tracer.pop_trace; exit;
    end;

    content := driver.video.windows.getWindowContent(g_win_id);
    if content = nil then begin
        driver.video.windows.destroyWindow(g_win_id);
        g_win_id := 0;
        debug.tracer.pop_trace; exit;
    end;

    { Allocate and zero-initialise state }
    state := PFileBrowserState(kalloc(sizeof(TFileBrowserState)));
    memset(uint32(state), 0, sizeof(TFileBrowserState));
    state^.win_id   := g_win_id;
    state^.cur_path := stringCopy('/');
    state^.view_mode := vmDetail;
    state^.sort_col  := 0;   { name }
    state^.sort_asc  := true;
    state^.show_hidden := false;
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
    lv_obj_set_style_pad_all(toolbar, 4, 0);
    lv_obj_set_style_pad_column(toolbar, 3, 0);
    lv_obj_set_style_layout(toolbar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(toolbar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(toolbar, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                         LV_FLEX_ALIGN_CENTER);
    lv_obj_remove_flag(toolbar, LV_OBJ_FLAG_SCROLLABLE);
    state^.toolbar := toolbar;

    { Navigation buttons }
    state^.back_btn := makeToolBtn(toolbar, SYM_LEFT,  28, state, @fb_back_cb);
    state^.fwd_btn  := makeToolBtn(toolbar, SYM_RIGHT, 28, state, @fb_fwd_cb);
    state^.up_btn   := makeToolBtn(toolbar, SYM_UP,    28, state, @fb_up_cb);

    { ---- Breadcrumb bar (fills remaining toolbar space) ---- }
    state^.breadcrumb := lv_obj_create(toolbar);
    lv_obj_remove_style_all(state^.breadcrumb);
    lv_obj_set_height(state^.breadcrumb, 26);
    lv_obj_set_flex_grow(state^.breadcrumb, 1);
    lv_obj_set_style_bg_color(state^.breadcrumb, lv_color_make(38, 42, 56), 0);
    lv_obj_set_style_bg_opa(state^.breadcrumb, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(state^.breadcrumb, 4, 0);
    lv_obj_set_style_pad_left(state^.breadcrumb, 4, 0);
    lv_obj_set_style_pad_right(state^.breadcrumb, 4, 0);
    lv_obj_set_style_pad_column(state^.breadcrumb, 2, 0);
    lv_obj_set_style_layout(state^.breadcrumb, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(state^.breadcrumb, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(state^.breadcrumb, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_remove_flag(state^.breadcrumb, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(state^.breadcrumb, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(state^.breadcrumb, @fb_crumb_area_cb,
                        LV_EVENT_CLICKED, state);

    { ---- Path text area (hidden by default, shown on breadcrumb click) ---- }
    state^.path_ta := lv_textarea_create(toolbar);
    lv_obj_set_height(state^.path_ta, 26);
    lv_obj_set_flex_grow(state^.path_ta, 1);
    lv_textarea_set_one_line(state^.path_ta, true);
    lv_textarea_set_text(state^.path_ta, '/');
    lv_obj_set_style_bg_color(state^.path_ta, lv_color_make(38, 42, 56), 0);
    lv_obj_set_style_bg_opa(state^.path_ta, LV_OPA_COVER, 0);
    lv_obj_set_style_text_color(state^.path_ta, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(state^.path_ta, @lv_font_montserrat_14, 0);
    lv_obj_set_style_border_color(state^.path_ta, lv_color_make(80, 120, 200), 0);
    lv_obj_set_style_border_width(state^.path_ta, 1, 0);
    lv_obj_set_style_radius(state^.path_ta, 4, 0);
    lv_obj_set_style_pad_all(state^.path_ta, 4, 0);
    lv_obj_add_flag(state^.path_ta, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(state^.path_ta, @fb_path_ta_cb, LV_EVENT_KEY, state);
    state^.path_editing := false;

    makeToolBtn(toolbar, SYM_REFRESH, 28, state, @fb_refresh_cb);
    { File operation buttons }
    makeToolBtn(toolbar, SYM_DIRECTORY, 32, state, @fb_newfolder_cb);
    makeToolBtn(toolbar, SYM_FILE,      32, state, @fb_newfile_cb);
    makeToolBtn(toolbar, SYM_EDIT,      32, state, @fb_rename_cb);

    { Filter input }
    state^.filter_ta := lv_textarea_create(toolbar);
    lv_textarea_set_one_line(state^.filter_ta, true);
    lv_textarea_set_placeholder_text(state^.filter_ta, 'Filter...');
    lv_obj_set_size(state^.filter_ta, 120, 26);
    lv_obj_set_style_bg_color(state^.filter_ta, lv_color_make(38, 42, 56), 0);
    lv_obj_set_style_bg_opa(state^.filter_ta, LV_OPA_COVER, 0);
    lv_obj_set_style_text_color(state^.filter_ta, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(state^.filter_ta, @lv_font_montserrat_14, 0);
    lv_obj_set_style_border_color(state^.filter_ta, lv_color_make(60, 65, 80), 0);
    lv_obj_set_style_border_width(state^.filter_ta, 1, 0);
    lv_obj_set_style_radius(state^.filter_ta, 4, 0);
    lv_obj_set_style_pad_all(state^.filter_ta, 4, 0);
    lv_obj_add_event_cb(state^.filter_ta, @fb_filter_changed_cb,
                        LV_EVENT_VALUE_CHANGED, state);
    makeToolBtn(toolbar, SYM_CLOSE,    24, state, @fb_filter_clear_cb);
    makeToolBtn(toolbar, SYM_IMAGE,    24, state, @fb_preview_toggle_cb);
    makeToolBtn(toolbar, SYM_LIST,     24, state, @fb_viewmode_toggle_cb);
    makeToolBtn(toolbar, SYM_EYE_OPEN, 28, state, @fb_hidden_toggle_cb);

    { Dim disabled nav buttons initially }
    lv_obj_remove_flag(state^.back_btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_opa(state^.back_btn, 80, 0);
    lv_obj_remove_flag(state^.fwd_btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_opa(state^.fwd_btn, 80, 0);

    { ---- Tab bar ---- }
    state^.tab_bar := lv_obj_create(content);
    lv_obj_remove_style_all(state^.tab_bar);
    lv_obj_set_size(state^.tab_bar, lv_pct(100), 26);
    lv_obj_set_style_bg_color(state^.tab_bar, lv_color_make(28, 31, 40), 0);
    lv_obj_set_style_bg_opa(state^.tab_bar, LV_OPA_COVER, 0);
    lv_obj_set_style_layout(state^.tab_bar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(state^.tab_bar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(state^.tab_bar, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_left(state^.tab_bar, 4, 0);
    lv_obj_set_style_pad_column(state^.tab_bar, 2, 0);
    lv_obj_remove_flag(state^.tab_bar, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_border_color(state^.tab_bar, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_side(state^.tab_bar, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_width(state^.tab_bar, 1, 0);
    state^.tab_count  := 1;
    state^.active_tab := 0;

    { ---- Body row — sidebar + main content ---- }
    body_row := lv_obj_create(content);
    lv_obj_remove_style_all(body_row);
    lv_obj_set_size(body_row, lv_pct(100), 0);
    lv_obj_set_flex_grow(body_row, 1);
    lv_obj_set_style_layout(body_row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(body_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(body_row, 0, 0);
    lv_obj_remove_flag(body_row, LV_OBJ_FLAG_SCROLLABLE);
    state^.body_row := body_row;

    { ---- Bookmark sidebar (150px) ---- }
    sidebar := lv_obj_create(body_row);
    lv_obj_remove_style_all(sidebar);
    lv_obj_set_size(sidebar, 150, lv_pct(100));
    lv_obj_set_style_bg_color(sidebar, lv_color_make(25, 27, 36), 0);
    lv_obj_set_style_bg_opa(sidebar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(sidebar, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_side(sidebar, LV_BORDER_SIDE_RIGHT, 0);
    lv_obj_set_style_border_width(sidebar, 1, 0);
    lv_obj_set_style_pad_all(sidebar, 6, 0);
    lv_obj_set_style_pad_row(sidebar, 2, 0);
    lv_obj_set_style_layout(sidebar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(sidebar, LV_FLEX_FLOW_COLUMN);
    lv_obj_add_flag(sidebar, LV_OBJ_FLAG_SCROLLABLE);
    state^.sidebar := sidebar;

    { ---- Main content area — hosts directory listing rows ---- }
    main_area := lv_obj_create(body_row);
    lv_obj_remove_style_all(main_area);
    lv_obj_set_size(main_area, 0, lv_pct(100));
    lv_obj_set_flex_grow(main_area, 1);
    lv_obj_set_style_bg_color(main_area, lv_color_make(20, 22, 32), 0);
    lv_obj_set_style_bg_opa(main_area, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_all(main_area, 4, 0);
    lv_obj_set_style_layout(main_area, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(main_area, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(main_area, 2, 0);
    lv_obj_add_flag(main_area, LV_OBJ_FLAG_SCROLLABLE);
    state^.content_area := main_area;

    { Type-ahead keyboard handler on content area }
    lv_obj_add_event_cb(main_area, @fb_typeahead_key_cb, LV_EVENT_KEY, state);

    { ---- Preview panel (right side, hidden by default) ---- }
    state^.preview_panel := lv_obj_create(body_row);
    lv_obj_remove_style_all(state^.preview_panel);
    lv_obj_set_size(state^.preview_panel, 200, lv_pct(100));
    lv_obj_set_style_bg_color(state^.preview_panel, lv_color_make(25, 27, 36), 0);
    lv_obj_set_style_bg_opa(state^.preview_panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(state^.preview_panel, lv_color_make(48, 52, 68), 0);
    lv_obj_set_style_border_side(state^.preview_panel, LV_BORDER_SIDE_LEFT, 0);
    lv_obj_set_style_border_width(state^.preview_panel, 1, 0);
    lv_obj_set_style_pad_all(state^.preview_panel, 8, 0);
    lv_obj_set_style_pad_row(state^.preview_panel, 4, 0);
    lv_obj_set_style_layout(state^.preview_panel, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(state^.preview_panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_add_flag(state^.preview_panel, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(state^.preview_panel, LV_OBJ_FLAG_HIDDEN);
    state^.preview_visible := false;

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
    state^.status_bar := statusbar;

    sl := lv_label_create(statusbar);
    lv_label_set_text(sl, '/');
    lv_obj_set_style_text_color(sl, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(sl, @lv_font_montserrat_14, 0);
    state^.status_label := sl;

    { Register resize callback }
    driver.video.windows.setWindowResizeCallback(g_win_id, @onResize);

    { Create process so filebrowser appears in PS }
    ctx := proc.mgr.create('Files', @fb_entry, void(state), 1);
    if ctx <> nil then begin
        state^.pid := ctx^.ProcessID;
        driver.video.windows.setWindowOwner(g_win_id, ctx^.ProcessID);
    end;

    { Create 50ms poll timer so LVGL can pick up async refresh data }
    state^.refresh_poll := lv_timer_create(@fb_refresh_poll_cb, 50, state);

    { Load initial directory }
    navigate_to(state, '/');
    rebuild_tab_bar(state);

    { Create 500ms poll timer for directory watch notifications }
    state^.watch_timer := lv_timer_create(@fb_watch_poll_timer, 500, state);

    { Default bookmarks }
    add_bookmark_entry(state, '/');
    add_bookmark_entry(state, '/sys');
    add_bookmark_entry(state, '/boot');



    debug.tracer.pop_trace;
end;

{ ============================================================
  init — register with the desktop program launcher
  ============================================================ }
procedure init();
begin
    debug.tracer.push_trace('filebrowser.init');
    g_win_id := 0;
    g_state  := nil;
    driver.video.desktop.registerProgram('Files', @launch);
    debug.tracer.pop_trace;
end;

end.
