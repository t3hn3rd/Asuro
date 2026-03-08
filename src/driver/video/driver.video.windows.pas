{
    Driver->Video->driver.video.windows - LVGL-based windowing system.

    Provides managed, draggable, resizable, collapsible driver.video.windows
    with title bars, close buttons, and z-ordering.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.video.windows;

interface

uses
    driver.video.lvgl, driver.hid.mouse, driver.intf.serial, debug.tracer, proc.mgr, proc.types;

const
    MAX_WINDOWS      = 16;
    WIN_TITLEBAR_H   = 32;
    WIN_MIN_W        = 160;
    WIN_MIN_H        = 80;
    WIN_RESIZE_GRIP  = 16;    { size of the resize grip triangle }
    WIN_BORDER_RAD   = 10;

type
    TWinCloseCallback = procedure(win_id: uint32);
    TWinResizeCallback = procedure(win_id: uint32; new_w, new_h: sint32);

    TWinState = (
        wsNone,
        wsOpen,
        wsCollapsed
    );

    PWinRecord = ^TWinRecord;
    TWinRecord = record
        state        : TWinState;
        frame        : Plv_obj;   { outer container - positioned on screen }
        titlebar     : Plv_obj;   { title bar row }
        title_lbl    : Plv_obj;   { title text }
        close_btn    : Plv_obj;   { red close circle }
        collapse_btn : Plv_obj;   { yellow collapse circle }
        content      : Plv_obj;   { content area - caller populates this }
        resize_grip  : Plv_obj;   { floating grip at bottom-right for resize }
        grip_line1   : Plv_obj;   { first diagonal line in grip }
        grip_line2   : Plv_obj;   { second diagonal line in grip }
        grip_line3   : Plv_obj;   { third diagonal line in grip }
        win_w        : sint32;    { current width }
        win_h        : sint32;    { current height (full, before collapse) }
        min_w        : sint32;
        min_h        : sint32;
        dragging     : boolean;
        resizing     : boolean;
        drag_ox      : sint32;    { driver.hid.mouse offset from frame origin when drag started }
        drag_oy      : sint32;
        on_close     : TWinCloseCallback;
        on_resize    : TWinResizeCallback;
        cursor_obj   : Plv_obj;   { cursor to keep on top }
        owner_pid    : uint32;    { owning process PID; 0 = unowned }
    end;

{ Create a new window. Returns window ID (0 = failure). }
function  createWindow(title: pchar; x, y, w, h: sint32; closeCB: TWinCloseCallback; cursor: Plv_obj): uint32;

{ Get the content area of a window (to add widgets into). }
function  getWindowContent(win_id: uint32): Plv_obj;

{ Get the frame object of a window. }
function  getWindowFrame(win_id: uint32): Plv_obj;

{ Destroy a window and free its slot. }
procedure destroyWindow(win_id: uint32);

{ Bring a window to front. }
procedure focusWindow(win_id: uint32);

{ Check if a window is open. }
function  isWindowOpen(win_id: uint32): boolean;

{ Get number of open windows. }
function  getWindowCount: uint32;

{ Set a callback to be notified when a window is resized. }
procedure setWindowResizeCallback(win_id: uint32; cb: TWinResizeCallback);

{ Assign an owning process to a window.
  When reapOrphanedWindows detects the process has died, the window
  is automatically closed via its on_close callback. }
procedure setWindowOwner(win_id: uint32; pid: uint32);

{ Check all driver.video.windows for dead owner processes and close them.
  Called once per frame from graphicsrefresh. }
procedure reapOrphanedWindows;

implementation

var
    wins : array[1..MAX_WINDOWS] of TWinRecord;

    { Persistent point arrays for grip lines (2 points per line, 3 lines).
      These draw diagonal lines from top-right towards bottom-left
      within the grip area to indicate resizability. }
    grip_pts : array[0..2, 0..1] of lv_point_t;
    grip_pts_init : boolean = false;

{ ============================================================
  Internal: find a free slot (returns 0 if none)
  ============================================================ }
function allocSlot: uint32;
var
    i: uint32;
begin
    allocSlot := 0;
    for i := 1 to MAX_WINDOWS do begin
        if wins[i].state = wsNone then begin
            allocSlot := i;
            exit;
        end;
    end;
end;

{ ============================================================
  Internal: find window ID by frame object
  ============================================================ }
function findByFrame(frame: Plv_obj): uint32;
var
    i: uint32;
begin
    findByFrame := 0;
    for i := 1 to MAX_WINDOWS do begin
        if (wins[i].state <> wsNone) and (wins[i].frame = frame) then begin
            findByFrame := i;
            exit;
        end;
    end;
end;

{ ============================================================
  Internal: find window ID by any child object (titlebar, btn, etc)
  ============================================================ }
function findByChild(obj: Plv_obj): uint32;
var
    i: uint32;
begin
    findByChild := 0;
    for i := 1 to MAX_WINDOWS do begin
        if wins[i].state <> wsNone then begin
            if (wins[i].frame = obj) or
               (wins[i].titlebar = obj) or
               (wins[i].close_btn = obj) or
               (wins[i].collapse_btn = obj) or
               (wins[i].content = obj) then begin
                findByChild := i;
                exit;
            end;
        end;
    end;
end;

{ ============================================================
  Internal: bring window to front
  ============================================================ }
procedure bringToFront(id: uint32);
begin
    if (id < 1) or (id > MAX_WINDOWS) then exit;
    if wins[id].state = wsNone then exit;
    lv_obj_move_foreground(wins[id].frame);
    if wins[id].cursor_obj <> nil then
        lv_obj_move_foreground(wins[id].cursor_obj);
end;

{ ============================================================
  Event: titlebar pressed — start drag / detect resize zone
  ============================================================ }
procedure titlebar_press_cb(e: Plv_event); cdecl;
var
    code   : lv_event_code_t;
    tb     : Plv_obj;
    id     : uint32;
    mx, my : sint32;
    fx, fy : sint32;
    fw, fh : sint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_PRESSED then exit;

    tb := lv_event_get_target(e);
    { Walk up: titlebar's parent is the frame }
    id := findByChild(tb);
    if id = 0 then exit;

    mx := driver.hid.mouse.getMouseX;
    my := driver.hid.mouse.getMouseY;
    fx := lv_obj_get_x(wins[id].frame);
    fy := lv_obj_get_y(wins[id].frame);

    wins[id].drag_ox := mx - fx;
    wins[id].drag_oy := my - fy;
    wins[id].dragging := true;
    wins[id].resizing := false;

    bringToFront(id);
end;

{ ============================================================
  Event: titlebar pressing — continue drag
  ============================================================ }
procedure titlebar_pressing_cb(e: Plv_event); cdecl;
var
    code     : lv_event_code_t;
    tb       : Plv_obj;
    id       : uint32;
    mx, my   : sint32;
    new_x, new_y : sint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_PRESSING then exit;

    tb := lv_event_get_target(e);
    id := findByChild(tb);
    if id = 0 then exit;

    if not wins[id].dragging then exit;

    mx := driver.hid.mouse.getMouseX;
    my := driver.hid.mouse.getMouseY;
    new_x := mx - wins[id].drag_ox;
    new_y := my - wins[id].drag_oy;

    lv_obj_set_pos(wins[id].frame, new_x, new_y);
end;

{ ============================================================
  Event: titlebar released — stop drag
  ============================================================ }
procedure titlebar_release_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    tb   : Plv_obj;
    id   : uint32;
begin
    code := lv_event_get_code(e);
    if (code <> LV_EVENT_RELEASED) and (code <> LV_EVENT_PRESS_LOST) then exit;

    tb := lv_event_get_target(e);
    id := findByChild(tb);
    if id = 0 then exit;

    wins[id].dragging := false;
end;

{ ============================================================
  Internal: find window ID by resize grip object
  ============================================================ }
function findByGrip(grip: Plv_obj): uint32;
var
    i: uint32;
begin
    findByGrip := 0;
    for i := 1 to MAX_WINDOWS do begin
        if (wins[i].state <> wsNone) and (wins[i].resize_grip = grip) then begin
            findByGrip := i;
            exit;
        end;
    end;
end;

{ ============================================================
  Internal: reposition the resize grip to frame bottom-right
  ============================================================ }
procedure repositionGrip(id: uint32);
begin
    if (id < 1) or (id > MAX_WINDOWS) then exit;
    if wins[id].resize_grip = nil then exit;
    lv_obj_set_pos(wins[id].resize_grip,
                   wins[id].win_w - WIN_RESIZE_GRIP,
                   wins[id].win_h - WIN_RESIZE_GRIP);
end;

{ ============================================================
  Event: grip pressed — start resize
  ============================================================ }
procedure grip_press_cb(e: Plv_event); cdecl;
var
    code   : lv_event_code_t;
    grip   : Plv_obj;
    id     : uint32;
    mx, my : sint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_PRESSED then exit;

    grip := lv_event_get_target(e);
    id := findByGrip(grip);
    if id = 0 then exit;
    if wins[id].state = wsCollapsed then exit;

    mx := driver.hid.mouse.getMouseX;
    my := driver.hid.mouse.getMouseY;

    wins[id].resizing := true;
    wins[id].dragging := false;
    wins[id].drag_ox := mx;
    wins[id].drag_oy := my;

    bringToFront(id);
end;

{ ============================================================
  Event: grip pressing — continue resize drag
  ============================================================ }
procedure grip_pressing_cb(e: Plv_event); cdecl;
var
    code         : lv_event_code_t;
    grip         : Plv_obj;
    id           : uint32;
    mx, my       : sint32;
    dx, dy       : sint32;
    new_w, new_h : sint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_PRESSING then exit;

    grip := lv_event_get_target(e);
    id := findByGrip(grip);
    if id = 0 then exit;

    if not wins[id].resizing then exit;

    mx := driver.hid.mouse.getMouseX;
    my := driver.hid.mouse.getMouseY;
    dx := mx - wins[id].drag_ox;
    dy := my - wins[id].drag_oy;

    new_w := wins[id].win_w + dx;
    new_h := wins[id].win_h + dy;

    if new_w < wins[id].min_w then new_w := wins[id].min_w;
    if new_h < wins[id].min_h then new_h := wins[id].min_h;

    lv_obj_set_size(wins[id].frame, new_w, new_h);
    lv_obj_set_width(wins[id].titlebar, new_w);
    lv_obj_set_size(wins[id].content, new_w, new_h - WIN_TITLEBAR_H);

    wins[id].win_w := new_w;
    wins[id].win_h := new_h;
    wins[id].drag_ox := mx;
    wins[id].drag_oy := my;

    { Move grip to new bottom-right }
    repositionGrip(id);

    { Notify callback }
    if wins[id].on_resize <> nil then
        wins[id].on_resize(id, new_w, new_h);
end;

{ ============================================================
  Event: grip released — stop resize
  ============================================================ }
procedure grip_release_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    grip : Plv_obj;
    id   : uint32;
begin
    code := lv_event_get_code(e);
    if (code <> LV_EVENT_RELEASED) and (code <> LV_EVENT_PRESS_LOST) then exit;

    grip := lv_event_get_target(e);
    id := findByGrip(grip);
    if id = 0 then exit;

    wins[id].resizing := false;
end;

{ ============================================================
  Event: close button clicked
  ============================================================ }
procedure close_click_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    id   : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;

    id := uint32(lv_event_get_user_data(e));
    if (id < 1) or (id > MAX_WINDOWS) then exit;
    if wins[id].state = wsNone then exit;

    if wins[id].on_close <> nil then
        wins[id].on_close(id)
    else
        destroyWindow(id);
end;

{ ============================================================
  Event: collapse button clicked
  ============================================================ }
procedure collapse_click_cb(e: Plv_event); cdecl;
var
    code : lv_event_code_t;
    id   : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;

    id := uint32(lv_event_get_user_data(e));
    if (id < 1) or (id > MAX_WINDOWS) then exit;
    if wins[id].state = wsNone then exit;

    if wins[id].state = wsCollapsed then begin
        { Expand }
        wins[id].state := wsOpen;
        lv_obj_set_size(wins[id].frame, wins[id].win_w, wins[id].win_h);
        lv_obj_remove_flag(wins[id].content, LV_OBJ_FLAG_HIDDEN);
        if wins[id].resize_grip <> nil then begin
            lv_obj_remove_flag(wins[id].resize_grip, LV_OBJ_FLAG_HIDDEN);
            repositionGrip(id);
        end;
    end else begin
        { Collapse to just the title bar }
        wins[id].state := wsCollapsed;
        lv_obj_set_size(wins[id].frame, wins[id].win_w, WIN_TITLEBAR_H);
        lv_obj_add_flag(wins[id].content, LV_OBJ_FLAG_HIDDEN);
        if wins[id].resize_grip <> nil then
            lv_obj_add_flag(wins[id].resize_grip, LV_OBJ_FLAG_HIDDEN);
    end;
end;

{ ============================================================
  Public: create a window
  ============================================================ }
function createWindow(title: pchar; x, y, w, h: sint32; closeCB: TWinCloseCallback; cursor: Plv_obj): uint32;
var
    id        : uint32;
    scr       : Plv_obj;
    frame     : Plv_obj;
    titlebar  : Plv_obj;
    title_lbl : Plv_obj;
    close_btn : Plv_obj;
    close_lbl : Plv_obj;
    coll_btn  : Plv_obj;
    coll_lbl  : Plv_obj;
    content   : Plv_obj;
begin
    createWindow := 0;

    id := allocSlot;
    if id = 0 then exit;

    debug.tracer.push_trace('driver.video.windows.create');

    { Initialize grip line points on first window creation }
    if not grip_pts_init then begin
        { Line 1: longest diagonal }
        grip_pts[0][0].x := WIN_RESIZE_GRIP - 2;
        grip_pts[0][0].y := 2;
        grip_pts[0][1].x := 2;
        grip_pts[0][1].y := WIN_RESIZE_GRIP - 2;
        { Line 2: middle diagonal }
        grip_pts[1][0].x := WIN_RESIZE_GRIP - 2;
        grip_pts[1][0].y := 7;
        grip_pts[1][1].x := 7;
        grip_pts[1][1].y := WIN_RESIZE_GRIP - 2;
        { Line 3: shortest diagonal }
        grip_pts[2][0].x := WIN_RESIZE_GRIP - 2;
        grip_pts[2][0].y := 12;
        grip_pts[2][1].x := 12;
        grip_pts[2][1].y := WIN_RESIZE_GRIP - 2;
        grip_pts_init := true;
    end;

    scr := lv_screen_active;

    { ---- Outer frame ---- }
    frame := lv_obj_create(scr);
    lv_obj_remove_style_all(frame);
    lv_obj_set_size(frame, w, h);
    lv_obj_set_pos(frame, x, y);
    lv_obj_set_style_bg_color(frame, lv_color_make(35, 38, 48), 0);
    lv_obj_set_style_bg_opa(frame, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(frame, WIN_BORDER_RAD, 0);
    lv_obj_set_style_clip_corner(frame, true, 0);
    lv_obj_set_style_border_width(frame, 1, 0);
    lv_obj_set_style_border_color(frame, lv_color_make(60, 65, 80), 0);
    lv_obj_set_style_border_opa(frame, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(frame, 24, 0);
    lv_obj_set_style_shadow_color(frame, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_shadow_opa(frame, 160, 0);
    lv_obj_set_style_shadow_offset_y(frame, 4, 0);
    lv_obj_set_style_pad_all(frame, 0, 0);
    lv_obj_remove_flag(frame, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(frame, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_style_layout(frame, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(frame, LV_FLEX_FLOW_COLUMN);
    lv_obj_add_flag(frame, LV_OBJ_FLAG_CLICKABLE);

    { ---- Title bar ---- }
    titlebar := lv_obj_create(frame);
    lv_obj_remove_style_all(titlebar);
    lv_obj_set_size(titlebar, w, WIN_TITLEBAR_H);
    lv_obj_set_style_bg_color(titlebar, lv_color_make(45, 48, 58), 0);
    lv_obj_set_style_bg_opa(titlebar, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_left(titlebar, 0, 0);
    lv_obj_set_style_pad_right(titlebar, 0, 0);
    lv_obj_set_style_pad_top(titlebar, 0, 0);
    lv_obj_set_style_pad_bottom(titlebar, 0, 0);
    lv_obj_remove_flag(titlebar, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(titlebar, LV_SCROLLBAR_MODE_OFF);
    lv_obj_add_flag(titlebar, LV_OBJ_FLAG_CLICKABLE);

    { Flex layout: title(grow) | minimize | close }
    lv_obj_set_style_layout(titlebar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(titlebar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(titlebar, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(titlebar, 0, 0);

    { Titlebar events for drag }
    lv_obj_add_event_cb(titlebar, @titlebar_press_cb, LV_EVENT_PRESSED, nil);
    lv_obj_add_event_cb(titlebar, @titlebar_pressing_cb, LV_EVENT_PRESSING, nil);
    lv_obj_add_event_cb(titlebar, @titlebar_release_cb, LV_EVENT_RELEASED, nil);
    lv_obj_add_event_cb(titlebar, @titlebar_release_cb, LV_EVENT_PRESS_LOST, nil);

    { ---- Title label (fills remaining space, centered text) ---- }
    title_lbl := lv_label_create(titlebar);
    lv_label_set_text(title_lbl, title);
    lv_obj_set_style_text_color(title_lbl, lv_color_make(210, 215, 230), 0);
    lv_obj_set_style_text_font(title_lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_style_text_align(title_lbl, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_pad_left(title_lbl, 10, 0);
    lv_label_set_long_mode(title_lbl, LV_LABEL_LONG_CLIP);
    lv_obj_set_width(title_lbl, 0);
    lv_obj_set_flex_grow(title_lbl, 1);

    { ---- Minimize button (full height) ---- }
    coll_btn := lv_button_create(titlebar);
    lv_obj_remove_style_all(coll_btn);
    lv_obj_set_size(coll_btn, WIN_TITLEBAR_H, WIN_TITLEBAR_H);
    lv_obj_set_style_bg_color(coll_btn, lv_color_make(55, 58, 70), 0);
    lv_obj_set_style_bg_opa(coll_btn, 0, 0);
    lv_obj_set_style_radius(coll_btn, 0, 0);
    lv_obj_set_style_border_width(coll_btn, 0, 0);
    lv_obj_set_style_shadow_width(coll_btn, 0, 0);
    lv_obj_set_style_pad_all(coll_btn, 0, 0);
    lv_obj_add_event_cb(coll_btn, @collapse_click_cb, LV_EVENT_CLICKED, pointer(id));

    coll_lbl := lv_label_create(coll_btn);
    lv_label_set_text(coll_lbl, #$EF#$81#$A8);
    lv_obj_set_style_text_color(coll_lbl, lv_color_make(160, 165, 180), 0);
    lv_obj_set_style_text_font(coll_lbl, @lv_font_fa_solid_16, 0);
    lv_obj_center(coll_lbl);

    { ---- Close button (right edge, full height) ---- }
    close_btn := lv_button_create(titlebar);
    lv_obj_remove_style_all(close_btn);
    lv_obj_set_size(close_btn, WIN_TITLEBAR_H, WIN_TITLEBAR_H);
    lv_obj_set_style_bg_color(close_btn, lv_color_make(180, 50, 50), 0);
    lv_obj_set_style_bg_opa(close_btn, 0, 0);
    lv_obj_set_style_radius(close_btn, 0, 0);
    lv_obj_set_style_border_width(close_btn, 0, 0);
    lv_obj_set_style_shadow_width(close_btn, 0, 0);
    lv_obj_set_style_pad_all(close_btn, 0, 0);
    lv_obj_add_event_cb(close_btn, @close_click_cb, LV_EVENT_CLICKED, pointer(id));

    close_lbl := lv_label_create(close_btn);
    lv_label_set_text(close_lbl, #$EF#$80#$8D);
    lv_obj_set_style_text_color(close_lbl, lv_color_make(160, 165, 180), 0);
    lv_obj_set_style_text_font(close_lbl, @lv_font_fa_solid_16, 0);
    lv_obj_center(close_lbl);

    { ---- Content area ---- }
    content := lv_obj_create(frame);
    lv_obj_remove_style_all(content);
    lv_obj_set_size(content, w, h - WIN_TITLEBAR_H);
    lv_obj_set_style_bg_color(content, lv_color_make(35, 38, 48), 0);
    lv_obj_set_style_bg_opa(content, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_left(content, 20, 0);
    lv_obj_set_style_pad_right(content, 20, 0);
    lv_obj_set_style_pad_top(content, 12, 0);
    lv_obj_set_style_pad_bottom(content, 12, 0);
    lv_obj_set_style_layout(content, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(content, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(content, 6, 0);
    lv_obj_add_flag(content, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(content, LV_SCROLLBAR_MODE_AUTO);

    { Style the scrollbar so it's visible against the dark background }
    lv_obj_set_style_bg_color(content, lv_color_make(100, 115, 160), LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_opa(content, LV_OPA_COVER, LV_PART_SCROLLBAR);
    lv_obj_set_style_radius(content, 4, LV_PART_SCROLLBAR);
    lv_obj_set_style_width(content, 6, LV_PART_SCROLLBAR);
    lv_obj_set_style_pad_all(content, 2, LV_PART_SCROLLBAR);

    { ---- Resize grip (floating over frame bottom-right) ---- }
    { The grip is a child of frame but ignores flex layout }
    wins[id].resize_grip := lv_obj_create(frame);
    lv_obj_remove_style_all(wins[id].resize_grip);
    lv_obj_set_size(wins[id].resize_grip, WIN_RESIZE_GRIP, WIN_RESIZE_GRIP);
    lv_obj_add_flag(wins[id].resize_grip, LV_OBJ_FLAG_FLOATING);
    lv_obj_add_flag(wins[id].resize_grip, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_flag(wins[id].resize_grip, LV_OBJ_FLAG_PRESS_LOCK);
    lv_obj_remove_flag(wins[id].resize_grip, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(wins[id].resize_grip, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_style_bg_opa(wins[id].resize_grip, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(wins[id].resize_grip, 0, 0);
    lv_obj_set_style_pad_all(wins[id].resize_grip, 0, 0);
    lv_obj_set_pos(wins[id].resize_grip, w - WIN_RESIZE_GRIP, h - WIN_RESIZE_GRIP);

    { Diagonal grip lines (three short lines suggesting resize) }
    wins[id].grip_line1 := lv_line_create(wins[id].resize_grip);
    lv_obj_set_style_line_color(wins[id].grip_line1, lv_color_make(120, 125, 140), 0);
    lv_obj_set_style_line_width(wins[id].grip_line1, 1, 0);
    lv_obj_set_style_line_opa(wins[id].grip_line1, 180, 0);
    lv_line_set_points(wins[id].grip_line1, @grip_pts[0][0], 2);

    wins[id].grip_line2 := lv_line_create(wins[id].resize_grip);
    lv_obj_set_style_line_color(wins[id].grip_line2, lv_color_make(120, 125, 140), 0);
    lv_obj_set_style_line_width(wins[id].grip_line2, 1, 0);
    lv_obj_set_style_line_opa(wins[id].grip_line2, 180, 0);
    lv_line_set_points(wins[id].grip_line2, @grip_pts[1][0], 2);

    wins[id].grip_line3 := lv_line_create(wins[id].resize_grip);
    lv_obj_set_style_line_color(wins[id].grip_line3, lv_color_make(120, 125, 140), 0);
    lv_obj_set_style_line_width(wins[id].grip_line3, 1, 0);
    lv_obj_set_style_line_opa(wins[id].grip_line3, 180, 0);
    lv_line_set_points(wins[id].grip_line3, @grip_pts[2][0], 2);

    { Grip events }
    lv_obj_add_event_cb(wins[id].resize_grip, @grip_press_cb, LV_EVENT_PRESSED, nil);
    lv_obj_add_event_cb(wins[id].resize_grip, @grip_pressing_cb, LV_EVENT_PRESSING, nil);
    lv_obj_add_event_cb(wins[id].resize_grip, @grip_release_cb, LV_EVENT_RELEASED, nil);
    lv_obj_add_event_cb(wins[id].resize_grip, @grip_release_cb, LV_EVENT_PRESS_LOST, nil);

    { ---- Store record ---- }
    wins[id].state        := wsOpen;
    wins[id].frame        := frame;
    wins[id].titlebar     := titlebar;
    wins[id].title_lbl    := title_lbl;
    wins[id].close_btn    := close_btn;
    wins[id].collapse_btn := coll_btn;
    wins[id].content      := content;
    wins[id].win_w        := w;
    wins[id].win_h        := h;
    wins[id].min_w        := WIN_MIN_W;
    wins[id].min_h        := WIN_MIN_H;
    wins[id].dragging     := false;
    wins[id].resizing     := false;
    wins[id].drag_ox      := 0;
    wins[id].drag_oy      := 0;
    wins[id].on_close     := closeCB;
    wins[id].on_resize    := nil;
    wins[id].cursor_obj   := cursor;
    wins[id].owner_pid    := 0;

    { Bring to front }
    bringToFront(id);

    debug.tracer.pop_trace;

    createWindow := id;
end;

{ ============================================================
  Public: get content area
  ============================================================ }
function getWindowContent(win_id: uint32): Plv_obj;
begin
    getWindowContent := nil;
    if (win_id < 1) or (win_id > MAX_WINDOWS) then exit;
    if wins[win_id].state = wsNone then exit;
    getWindowContent := wins[win_id].content;
end;

{ ============================================================
  Public: get frame object
  ============================================================ }
function getWindowFrame(win_id: uint32): Plv_obj;
begin
    getWindowFrame := nil;
    if (win_id < 1) or (win_id > MAX_WINDOWS) then exit;
    if wins[win_id].state = wsNone then exit;
    getWindowFrame := wins[win_id].frame;
end;

{ ============================================================
  Public: destroy window
  ============================================================ }
procedure destroyWindow(win_id: uint32);
begin
    if (win_id < 1) or (win_id > MAX_WINDOWS) then exit;
    if wins[win_id].state = wsNone then exit;

    debug.tracer.push_trace('driver.video.windows.destroy');

    lv_obj_delete(wins[win_id].frame);

    wins[win_id].state     := wsNone;
    wins[win_id].frame     := nil;
    wins[win_id].titlebar  := nil;
    wins[win_id].title_lbl := nil;
    wins[win_id].close_btn := nil;
    wins[win_id].collapse_btn := nil;
    wins[win_id].content   := nil;
    wins[win_id].resize_grip := nil;
    wins[win_id].grip_line1  := nil;
    wins[win_id].grip_line2  := nil;
    wins[win_id].grip_line3  := nil;
    wins[win_id].on_close  := nil;
    wins[win_id].on_resize := nil;
    wins[win_id].cursor_obj := nil;
    wins[win_id].owner_pid := 0;

    debug.tracer.pop_trace;
end;

{ ============================================================
  Public: focus window (bring to front)
  ============================================================ }
procedure focusWindow(win_id: uint32);
begin
    bringToFront(win_id);
end;

{ ============================================================
  Public: check if window is open
  ============================================================ }
function isWindowOpen(win_id: uint32): boolean;
begin
    isWindowOpen := false;
    if (win_id < 1) or (win_id > MAX_WINDOWS) then exit;
    isWindowOpen := wins[win_id].state <> wsNone;
end;

{ ============================================================
  Public: get total number of open driver.video.windows
  ============================================================ }
function getWindowCount: uint32;
var
    i: uint32;
    cnt: uint32;
begin
    cnt := 0;
    for i := 1 to MAX_WINDOWS do begin
        if wins[i].state <> wsNone then
            cnt := cnt + 1;
    end;
    getWindowCount := cnt;
end;

{ ============================================================
  Public: set resize callback
  ============================================================ }
procedure setWindowResizeCallback(win_id: uint32; cb: TWinResizeCallback);
begin
    if (win_id < 1) or (win_id > MAX_WINDOWS) then exit;
    if wins[win_id].state = wsNone then exit;
    wins[win_id].on_resize := cb;
end;

{ ============================================================
  Public: set window owner PID
  ============================================================ }
procedure setWindowOwner(win_id: uint32; pid: uint32);
begin
    if (win_id < 1) or (win_id > MAX_WINDOWS) then exit;
    if wins[win_id].state = wsNone then exit;
    wins[win_id].owner_pid := pid;
end;

{ ============================================================
  Public: reap driver.video.windows whose owning process has died
  ============================================================ }
procedure reapOrphanedWindows;
var
    i   : uint32;
    ctx : PProcessContext;
begin
    for i := 1 to MAX_WINDOWS do begin
        if wins[i].state = wsNone then continue;
        if wins[i].owner_pid = 0 then continue;
        ctx := proc.mgr.findByID(wins[i].owner_pid);
        if (ctx = nil) or (ctx^.State = psFinished) or (ctx^.State = psError) then begin
            { Owner is dead — trigger close callback or destroy directly }
            if wins[i].on_close <> nil then
                wins[i].on_close(i)
            else
                destroyWindow(i);
        end;
    end;
end;

end.
