{
    Prog->FilePicker - OS-level reusable file picker dialog

    Usage:
        filepicker.show_open(title, start_dir, callback, userdata)
        filepicker.show_save(title, start_dir, initial_name, callback, userdata)

    The callback receives a kalloc'd path string the caller must kfree,
    or nil when the user cancels.

    Design:
      - A full-screen semi-transparent backdrop (child of lv_screen_active)
        absorbs clicks, preventing interaction with the app behind.
      - A centered panel is a child of the backdrop so a single
        lv_obj_delete(backdrop) tears down everything.
      - lv_list button user_data holds stringCopy'd entry names; these are
        freed via free_list_items before any list repopulation or close.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit filepicker;

interface

type
    TPickerCallback = procedure(path: pchar; userdata: pointer); cdecl;

procedure show_open(title     : pchar;
                    start_dir : pchar;
                    cb        : TPickerCallback;
                    userdata  : pointer);

procedure show_save(title        : pchar;
                    start_dir    : pchar;
                    initial_name : pchar;
                    cb           : TPickerCallback;
                    userdata     : pointer);

implementation

uses
    hashmap,
    lmemorymanager,
    lvgl,
    strings,
    tracer,
    util,
    vfs;

const
    PANEL_W = 520;
    PANEL_H = 430;

type
    PPicker = ^TPicker;
    TPicker = record
        backdrop        : Plv_obj;
        path_bar        : Plv_obj;
        file_list       : Plv_obj;
        fname_bar       : Plv_obj;   { save mode only; nil in open mode }
        cur_dir         : pchar;
        cb              : TPickerCallback;
        userdata        : pointer;
        is_save         : boolean;
        pending_refresh : boolean;   { true while a refresh timer is queued }
    end;

{ ============================================================
  Forward declarations
  ============================================================ }
procedure picker_close(p: PPicker; sel_path: pchar); forward;
procedure do_refresh(p: PPicker); forward;
procedure schedule_refresh(p: PPicker); forward;
procedure fp_refresh_timer_cb(tmr: Plv_timer); cdecl; forward;
procedure fp_dir_cb(e: Plv_event); cdecl; forward;
procedure fp_file_cb(e: Plv_event); cdecl; forward;
procedure fp_confirm_cb(e: Plv_event); cdecl; forward;
procedure fp_cancel_cb(e: Plv_event); cdecl; forward;
procedure fp_up_cb(e: Plv_event); cdecl; forward;

{ ============================================================
  free_list_items
  kfree the stringCopy'd name stored in each list button's
  user_data before the list is cleared or the picker is closed.
  ============================================================ }
procedure free_list_items(list: Plv_obj);
var
    n   : uint32;
    i   : uint32;
    btn : Plv_obj;
    ud  : pchar;
begin
    if list = nil then exit;
    n := lv_obj_get_child_count(list);
    if n = 0 then exit;
    for i := 0 to n - 1 do begin
        btn := lv_obj_get_child(list, sint32(i));
        if btn = nil then continue;
        ud := pchar(lv_obj_get_user_data(btn));
        if ud <> nil then kfree(void(ud));
    end;
end;

{ ============================================================
  picker_close
  Free user_data copies, destroy UI, call callback, free state.
  ============================================================ }
procedure picker_close(p: PPicker; sel_path: pchar);
var
    cb       : TPickerCallback;
    userdata : pointer;
    backdrop : Plv_obj;
begin
    cb       := p^.cb;
    userdata := p^.userdata;
    backdrop := p^.backdrop;
    { Free stringCopy'd names in the list before LVGL deletes the buttons }
    free_list_items(p^.file_list);
    if p^.cur_dir <> nil then kfree(void(p^.cur_dir));
    kfree(void(p));
    { Delete backdrop — also deletes panel and all children (list, buttons) }
    lv_obj_delete(backdrop);
    { Fire callback; sel_path is nil on cancel, caller must kfree on success }
    if cb <> nil then cb(sel_path, userdata);
end;

{ ============================================================
  do_refresh
  Repopulate file_list for p^.cur_dir.
  Pass 1: directories/mounts  Pass 2: files
  ============================================================ }
procedure do_refresh(p: PPicker);
var
    Map  : PHashMap;
    Item : PHashItem;
    i    : uint32;
    obj  : PVFSObject;
    btn  : Plv_obj;
    disp : pchar;
    copy : pchar;
begin
    tracer.push_trace('filepicker.do_refresh');
    if p^.file_list = nil then begin tracer.pop_trace; exit; end;

    { Sync path bar with current directory }
    if p^.path_bar <> nil then
        lv_textarea_set_text(p^.path_bar, p^.cur_dir);

    { Free user_data copies before clearing }
    free_list_items(p^.file_list);
    lv_obj_clean(p^.file_list);

    Map := vfs.GetDirectoryListingFrom(p^.cur_dir, '/');
    if Map = nil then begin tracer.pop_trace; exit; end;

    { Pass 1: directories, drives and mounts }
    for i := 0 to Map^.Size - 1 do begin
        Item := Map^.Table[i];
        while Item <> nil do begin
            obj := PVFSObject(Item^.Data);
            if obj <> nil then begin
                case obj^.ObjectType of
                    otVDIRECTORY, otDRIVE, otDIRECTORY, otMOUNT: begin
                        disp := stringConcat('[/] ', Item^.Key);
                        btn  := lv_list_add_button(p^.file_list, nil, disp);
                        kfree(void(disp));
                        copy := stringCopy(Item^.Key);
                        lv_obj_set_user_data(btn, copy);
                        lv_obj_add_event_cb(btn, @fp_dir_cb, LV_EVENT_CLICKED, p);
                    end;
                end;
            end;
            Item := Item^.Next;
        end;
    end;

    { Pass 2: regular and virtual files }
    for i := 0 to Map^.Size - 1 do begin
        Item := Map^.Table[i];
        while Item <> nil do begin
            obj := PVFSObject(Item^.Data);
            if (obj <> nil) and
               ((obj^.ObjectType = otFILE) or (obj^.ObjectType = otVFILE)) then begin
                btn  := lv_list_add_button(p^.file_list, nil, Item^.Key);
                copy := stringCopy(Item^.Key);
                lv_obj_set_user_data(btn, copy);
                lv_obj_add_event_cb(btn, @fp_file_cb, LV_EVENT_CLICKED, p);
            end;
            Item := Item^.Next;
        end;
    end;

    vfs.FreeDirectoryListing(Map);
    tracer.pop_trace;
end;

{ ============================================================
  fp_refresh_timer_cb / schedule_refresh
  Defer do_refresh to an LVGL one-shot timer (fires 1 ms after
  the click callback returns).  This keeps ATA/VFS I/O outside
  the LVGL event-dispatch stack while reusing the existing
  process context — no extra process needed.
  ============================================================ }
procedure fp_refresh_timer_cb(tmr: Plv_timer); cdecl;
var
    p: PPicker;
begin
    p := PPicker(lv_timer_get_user_data(tmr));
    lv_timer_delete(tmr);
    if p = nil then exit;
    p^.pending_refresh := false;
    do_refresh(p);
end;

procedure schedule_refresh(p: PPicker);
var
    tmr: Plv_timer;
begin
    if p^.pending_refresh then exit;   { timer already queued }
    p^.pending_refresh := true;
    tmr := lv_timer_create(@fp_refresh_timer_cb, 1, p);
    lv_timer_set_repeat_count(tmr, 1);
end;

{ ---- fp_dir_cb: navigate into a subdirectory ---- }
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

    if stringEquals(p^.cur_dir, '/') then
        np := stringConcat('/', name)
    else begin
        sep := stringConcat(p^.cur_dir, '/');
        np  := stringConcat(sep, name);
        kfree(void(sep));
    end;
    kfree(void(p^.cur_dir));
    p^.cur_dir := np;
    schedule_refresh(p);
end;

{ ---- fp_file_cb: a file entry was clicked ---- }
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

    if stringEquals(p^.cur_dir, '/') then
        fp := stringConcat('/', name)
    else begin
        sep := stringConcat(p^.cur_dir, '/');
        fp  := stringConcat(sep, name);
        kfree(void(sep));
    end;

    { Ignore clicks while a directory listing is loading }
    if p^.pending_refresh then begin kfree(void(fp)); exit; end;

    if p^.is_save then begin
        { Save mode: fill the filename bar so user can review / confirm }
        if p^.fname_bar <> nil then
            lv_textarea_set_text(p^.fname_bar, name);
        kfree(void(fp));
    end else begin
        { Open mode: auto-confirm with full path }
        picker_close(p, fp);
        { fp is now owned by the callback — do NOT kfree here }
    end;
end;

{ ---- fp_confirm_cb: "Open" or "Save" button clicked ---- }
procedure fp_confirm_cb(e: Plv_event); cdecl;
var
    p    : PPicker;
    path : pchar;
    name : pchar;
    sep  : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
    if p^.pending_refresh then exit;

    if p^.is_save then begin
        { Build: cur_dir / fname_bar }
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
    end else begin
        { Open mode: use whatever is in path_bar }
        name := lv_textarea_get_text(p^.path_bar);
        if (name = nil) or (stringSize(name) = 0) then exit;
        path := stringCopy(name);
    end;

    picker_close(p, path);
    { path is now owned by the callback }
end;

{ ---- fp_cancel_cb: "Cancel" button clicked ---- }
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

{ ---- fp_up_cb: navigate to parent directory ---- }
procedure fp_up_cb(e: Plv_event); cdecl;
var
    p       : PPicker;
    dir     : pchar;
    len     : uint32;
    i       : uint32;
    lastSep : sint32;
    newDir  : pchar;
begin
    if lv_event_get_code(e) <> LV_EVENT_CLICKED then exit;
    p := PPicker(lv_event_get_user_data(e));
    if p = nil then exit;
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
    kfree(void(p^.cur_dir));
    p^.cur_dir := newDir;
    schedule_refresh(p);
end;

{ ============================================================
  make_btn — small helper for action-row buttons
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
  make_picker — internal: build and show the picker UI
  ============================================================ }
procedure make_picker(title        : pchar;
                      start_dir    : pchar;
                      is_save      : boolean;
                      initial_name : pchar;
                      cb           : TPickerCallback;
                      userdata     : pointer);
var
    p         : PPicker;
    scr       : Plv_obj;
    backdrop  : Plv_obj;
    panel     : Plv_obj;
    title_lbl : Plv_obj;
    path_bar  : Plv_obj;
    list      : Plv_obj;
    fname_bar : Plv_obj;
    actions   : Plv_obj;
    spacer    : Plv_obj;
    conf_text : pchar;
begin
    tracer.push_trace('filepicker.make_picker');

    p := PPicker(kalloc(sizeof(TPicker)));
    memset(uint32(p), 0, sizeof(TPicker));
    p^.cb       := cb;
    p^.userdata := userdata;
    p^.is_save  := is_save;
    if (start_dir <> nil) and (stringSize(start_dir) > 0) then
        p^.cur_dir := stringCopy(start_dir)
    else
        p^.cur_dir := stringCopy('/disk');

    scr := lv_screen_active;

    { ==== Full-screen backdrop — absorbs clicks, dims background ==== }
    backdrop := lv_obj_create(scr);
    lv_obj_remove_style_all(backdrop);
    lv_obj_set_size(backdrop, lv_pct(100), lv_pct(100));
    lv_obj_set_pos(backdrop, 0, 0);
    lv_obj_set_style_bg_color(backdrop, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_bg_opa(backdrop, 130, 0);   { ~51% black overlay }
    lv_obj_set_style_pad_all(backdrop, 0, 0);
    lv_obj_remove_flag(backdrop, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_move_foreground(backdrop);
    p^.backdrop := backdrop;

    { ==== Centered panel (child of backdrop so delete backdrop = delete all) ==== }
    panel := lv_obj_create(backdrop);
    lv_obj_remove_style_all(panel);
    lv_obj_set_size(panel, PANEL_W, PANEL_H);
    lv_obj_align(panel, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_bg_color(panel, lv_color_make(22, 25, 36), 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(panel, lv_color_make(55, 70, 130), 0);
    lv_obj_set_style_border_width(panel, 1, 0);
    lv_obj_set_style_radius(panel, 6, 0);
    lv_obj_set_style_pad_all(panel, 10, 0);
    lv_obj_set_style_pad_row(panel, 6, 0);
    lv_obj_set_style_layout(panel, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);

    { Title label }
    title_lbl := lv_label_create(panel);
    lv_label_set_text(title_lbl, title);
    lv_obj_set_style_text_color(title_lbl, lv_color_make(180, 200, 245), 0);
    lv_obj_set_style_text_font(title_lbl, @lv_font_montserrat_14, 0);

    { Path bar — shows and edits the current directory being browsed }
    path_bar := lv_textarea_create(panel);
    lv_obj_set_size(path_bar, lv_pct(100), 34);
    lv_textarea_set_one_line(path_bar, true);
    lv_textarea_set_text(path_bar, p^.cur_dir);
    lv_textarea_set_placeholder_text(path_bar, '/disk');
    lv_obj_set_style_bg_color(path_bar, lv_color_make(35, 38, 55), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(path_bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_text_color(path_bar, lv_color_make(200, 210, 240), LV_PART_MAIN);
    lv_obj_set_style_text_font(path_bar, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_border_color(path_bar, lv_color_make(55, 80, 160), LV_PART_MAIN);
    lv_obj_set_style_border_width(path_bar, 1, LV_PART_MAIN);
    lv_obj_set_style_radius(path_bar, 4, LV_PART_MAIN);
    lv_group_add_obj(lvgl_get_kb_group, path_bar);
    p^.path_bar := path_bar;

    { File / directory list }
    list := lv_list_create(panel);
    lv_obj_set_size(list, lv_pct(100), 0);
    lv_obj_set_flex_grow(list, 1);
    lv_obj_set_style_bg_color(list, lv_color_make(28, 31, 44), 0);
    lv_obj_set_style_bg_opa(list, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(list, lv_color_make(45, 55, 90), 0);
    lv_obj_set_style_border_width(list, 1, 0);
    lv_obj_set_style_radius(list, 4, 0);
    p^.file_list := list;

    { Filename input — save mode only }
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
        lv_obj_set_style_bg_color(fname_bar, lv_color_make(28, 38, 28), LV_PART_MAIN);
        lv_obj_set_style_bg_opa(fname_bar, LV_OPA_COVER, LV_PART_MAIN);
        lv_obj_set_style_text_color(fname_bar, lv_color_make(200, 240, 200), LV_PART_MAIN);
        lv_obj_set_style_text_font(fname_bar, @lv_font_montserrat_14, LV_PART_MAIN);
        lv_obj_set_style_border_color(fname_bar, lv_color_make(55, 130, 55), LV_PART_MAIN);
        lv_obj_set_style_border_width(fname_bar, 1, LV_PART_MAIN);
        lv_obj_set_style_radius(fname_bar, 4, LV_PART_MAIN);
        lv_group_add_obj(lvgl_get_kb_group, fname_bar);
        lv_group_focus_obj(fname_bar);
    end;
    p^.fname_bar := fname_bar;

    { Action row: [^ Up] <spacer> [Cancel] [Open / Save] }
    actions := lv_obj_create(panel);
    lv_obj_remove_style_all(actions);
    lv_obj_set_size(actions, lv_pct(100), 36);
    lv_obj_set_style_layout(actions, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(actions, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(actions, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(actions, 6, 0);
    lv_obj_remove_flag(actions, LV_OBJ_FLAG_SCROLLABLE);

    make_btn(actions, '^ Up',   62, 50,  55,  80, @fp_up_cb,     p);

    spacer := lv_obj_create(actions);
    lv_obj_remove_style_all(spacer);
    lv_obj_set_flex_grow(spacer, 1);
    lv_obj_set_size(spacer, 0, 30);

    make_btn(actions, 'Cancel', 72, 60,  40,  40, @fp_cancel_cb, p);

    if is_save then conf_text := 'Save'
    else            conf_text := 'Open';
    make_btn(actions, conf_text, 72, 55, 90, 190, @fp_confirm_cb, p);

    { Populate list for the start directory — deferred via lv_timer so
      the UI is visible before the first directory I/O runs. }
    schedule_refresh(p);

    tracer.pop_trace;
end;

{ ============================================================
  Public API
  ============================================================ }

procedure show_open(title     : pchar;
                    start_dir : pchar;
                    cb        : TPickerCallback;
                    userdata  : pointer);
begin
    make_picker(title, start_dir, false, nil, cb, userdata);
end;

procedure show_save(title        : pchar;
                    start_dir    : pchar;
                    initial_name : pchar;
                    cb           : TPickerCallback;
                    userdata     : pointer);
begin
    make_picker(title, start_dir, true, initial_name, cb, userdata);
end;

end.
