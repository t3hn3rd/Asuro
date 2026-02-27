{
    Driver->Video->LVGL - Pascal bindings for LVGL 9.x
    
    All LVGL C functions are declared as cdecl; external.
    Pascal callbacks are exported with public name for the C linker.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit lvgl;

interface

uses
    video, videotypes, color, serial, tracer, lmemorymanager,
    mouse, keyboard, TMR_0_ISR, util;

{ ============================================================
  Opaque LVGL types
  ============================================================ }
type
    Plv_display   = pointer;
    Plv_indev     = pointer;
    Plv_obj       = pointer;
    Plv_group     = pointer;
    Plv_theme     = pointer;
    Plv_font      = pointer;
    Plv_event     = pointer;

    lv_color32_t = packed record
        blue  : uint8;
        green : uint8;
        red   : uint8;
        alpha : uint8;
    end;
    Plv_color32 = ^lv_color32_t;

    lv_color_t = lv_color32_t;
    Plv_color  = ^lv_color_t;

    lv_area_t = packed record
        x1 : sint32;
        y1 : sint32;
        x2 : sint32;
        y2 : sint32;
    end;
    Plv_area = ^lv_area_t;

    lv_point_t = packed record
        x : sint32;
        y : sint32;
    end;
    Plv_point = ^lv_point_t;

    lv_indev_type_t = (
        LV_INDEV_TYPE_NONE    = 0,
        LV_INDEV_TYPE_POINTER = 1,
        LV_INDEV_TYPE_KEYPAD  = 2,
        LV_INDEV_TYPE_BUTTON  = 3,
        LV_INDEV_TYPE_ENCODER = 4
    );

    lv_indev_state_t = uint32;  { C enum = int = 4 bytes on i386 }

    { lv_indev_data_t — matches LVGL 9.x C struct layout (with C alignment padding) }
    lv_indev_data_t = packed record
        point            : lv_point_t;       { offset 0, 8 bytes }
        key              : uint32;           { offset 8, 4 bytes }
        btn_id           : uint32;           { offset 12, 4 bytes }
        enc_diff         : sint16;           { offset 16, 2 bytes }
        _pad1            : uint16;           { offset 18, 2 bytes - C alignment padding }
        state            : lv_indev_state_t; { offset 20, 4 bytes }
        continue_reading : boolean;          { offset 24, 1 byte }
    end;
    Plv_indev_data = ^lv_indev_data_t;

    { Flush callback type }
    lv_display_flush_cb_t = procedure(disp: Plv_display; area: Plv_area; color_p: Plv_color); cdecl;

    { Input device read callback type }
    lv_indev_read_cb_t = procedure(indev: Plv_indev; data: Plv_indev_data); cdecl;

    { Log callback type }
    lv_log_print_cb_t = procedure(level: sint32; buf: pchar); cdecl;

const
    LV_INDEV_STATE_RELEASED = 0;
    LV_INDEV_STATE_PRESSED  = 1;

{ ============================================================
  LVGL Core API — cdecl; external
  ============================================================ }

{ Init / tick / timer }
procedure lv_init; cdecl; external;
procedure lv_tick_inc(tick_period_ms: uint32); cdecl; external;
function  lv_tick_get: uint32; cdecl; external;
function  lv_timer_handler: uint32; cdecl; external;

{ Display }
function  lv_display_create(hor_res, ver_res: sint32): Plv_display; cdecl; external;
procedure lv_display_set_flush_cb(disp: Plv_display; flush_cb: lv_display_flush_cb_t); cdecl; external;
procedure lv_display_set_buffers(disp: Plv_display; buf1: pointer; buf2: pointer; buf_size_bytes: uint32; render_mode: sint32); cdecl; external;
procedure lv_display_flush_ready(disp: Plv_display); cdecl; external;
function  lv_display_get_screen_active(disp: Plv_display): Plv_obj; cdecl; external;

{ Render modes }
const
    LV_DISPLAY_RENDER_MODE_PARTIAL = 0;
    LV_DISPLAY_RENDER_MODE_DIRECT  = 1;
    LV_DISPLAY_RENDER_MODE_FULL    = 2;

{ Input devices }
function  lv_indev_create: Plv_indev; cdecl; external;
procedure lv_indev_set_type(indev: Plv_indev; indev_type: lv_indev_type_t); cdecl; external;
procedure lv_indev_set_read_cb(indev: Plv_indev; read_cb: lv_indev_read_cb_t); cdecl; external;
procedure lv_indev_set_cursor(indev: Plv_indev; cur_obj: Plv_obj); cdecl; external;
procedure lv_indev_set_group(indev: Plv_indev; group: Plv_group); cdecl; external;
procedure lv_indev_set_scroll_limit(indev: Plv_indev; scroll_limit: uint8); cdecl; external;
procedure lv_indev_set_scroll_throw(indev: Plv_indev; scroll_throw: uint8); cdecl; external;
function  lv_indev_search_obj(obj: Plv_obj; point: Plv_point): Plv_obj; cdecl; external;

{ Groups }
function  lv_group_create: Plv_group; cdecl; external;
procedure lv_group_set_default(group: Plv_group); cdecl; external;

{ Logging }
procedure lv_log_register_print_cb(print_cb: lv_log_print_cb_t); cdecl; external;

{ Object / widget basics }
function  lv_obj_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_obj_set_size(obj: Plv_obj; w, h: sint32); cdecl; external;
procedure lv_obj_set_pos(obj: Plv_obj; x, y: sint32); cdecl; external;
procedure lv_obj_set_width(obj: Plv_obj; w: sint32); cdecl; external;
procedure lv_obj_set_height(obj: Plv_obj; h: sint32); cdecl; external;
function  lv_obj_get_x(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_y(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_width(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_height(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_parent(obj: Plv_obj): Plv_obj; cdecl; external;
procedure lv_obj_align(obj: Plv_obj; align: uint8; x_ofs, y_ofs: sint32); cdecl; external;
procedure lv_obj_align_to(obj: Plv_obj; base: Plv_obj; align: uint8; x_ofs, y_ofs: sint32); cdecl; external;
procedure lv_obj_set_style_bg_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_height(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_font(obj: Plv_obj; font: Plv_font; selector: uint32); cdecl; external;
procedure lv_obj_set_style_border_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_radius(obj: Plv_obj; radius: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_all(obj: Plv_obj; pad: sint32; selector: uint32);
procedure lv_obj_set_style_pad_left(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_right(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_top(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_bottom(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_gap(obj: Plv_obj; gap: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_layout(obj: Plv_obj; layout: uint32; selector: uint32); cdecl; external;
procedure lv_obj_remove_style_all(obj: Plv_obj); cdecl; external;
procedure lv_obj_set_flex_flow(obj: Plv_obj; flow: uint32); cdecl; external;
procedure lv_obj_set_flex_align(obj: Plv_obj; main_place, cross_place, track_place: uint32); cdecl; external;
procedure lv_obj_add_flag(obj: Plv_obj; flag: uint32); cdecl; external;
procedure lv_obj_remove_flag(obj: Plv_obj; flag: uint32); cdecl; external;
procedure lv_obj_set_scroll_dir(obj: Plv_obj; dir: uint32); cdecl; external;
procedure lv_obj_set_scrollbar_mode(obj: Plv_obj; mode: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_offset_x(obj: Plv_obj; ofs: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_offset_y(obj: Plv_obj; ofs: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_clip_corner(obj: Plv_obj; en: boolean; selector: uint32); cdecl; external;
procedure lv_obj_set_style_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
function  lv_obj_has_flag(obj: Plv_obj; flag: uint32): boolean; cdecl; external;
function  lv_obj_get_child_count(obj: Plv_obj): uint32; cdecl; external;

{ Label }
function  lv_label_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_label_set_text(lbl: Plv_obj; txt: pchar); cdecl; external;
procedure lv_label_set_long_mode(lbl: Plv_obj; long_mode: uint32); cdecl; external;

{ Line }
function  lv_line_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_line_set_points(line: Plv_obj; points: Plv_point; point_num: uint32); cdecl; external;
procedure lv_obj_set_style_line_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_rounded(obj: Plv_obj; en: boolean; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;

procedure lv_obj_scroll_by(obj: Plv_obj; x, y: sint32; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_by_bounded(obj: Plv_obj; dx, dy: sint32; anim_en: uint32); cdecl; external;

{ Button }
function  lv_button_create(parent: Plv_obj): Plv_obj; cdecl; external;

{ Textarea (input box) }
function  lv_textarea_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_textarea_set_text(ta: Plv_obj; txt: pchar); cdecl; external;
function  lv_textarea_get_text(ta: Plv_obj): pchar; cdecl; external;
procedure lv_textarea_set_placeholder_text(ta: Plv_obj; txt: pchar); cdecl; external;
procedure lv_textarea_set_one_line(ta: Plv_obj; en: boolean); cdecl; external;
procedure lv_textarea_set_cursor_click_pos(ta: Plv_obj; en: boolean); cdecl; external;
procedure lv_textarea_set_cursor_pos(ta: Plv_obj; pos: sint32); cdecl; external;

{ Group (for keyboard navigation/focus) }
procedure lv_group_add_obj(group: Plv_group; obj: Plv_obj); cdecl; external;
procedure lv_group_remove_obj(obj: Plv_obj); cdecl; external;
procedure lv_group_focus_obj(obj: Plv_obj); cdecl; external;

{ Screen }
function  lv_screen_active: Plv_obj; cdecl; external;

{ Object lifecycle }
procedure lv_obj_delete(obj: Plv_obj); cdecl; external;
procedure lv_obj_move_to_index(obj: Plv_obj; index: sint32); cdecl; external;
procedure lv_obj_move_foreground(obj: Plv_obj);
procedure lv_obj_move_background(obj: Plv_obj);
procedure lv_obj_invalidate(obj: Plv_obj); cdecl; external;

{ Events }
type
    lv_event_cb_t = procedure(e: Plv_event); cdecl;
    lv_event_code_t = uint32;

procedure lv_obj_add_event_cb(obj: Plv_obj; event_cb: lv_event_cb_t; filter: lv_event_code_t; user_data: pointer); cdecl; external;
function  lv_event_get_code(e: Plv_event): lv_event_code_t; cdecl; external;
function  lv_event_get_target(e: Plv_event): Plv_obj; cdecl; external;
function  lv_event_get_user_data(e: Plv_event): pointer; cdecl; external;

const
    LV_EVENT_ALL                  = 0;
    LV_EVENT_PRESSED              = 1;
    LV_EVENT_PRESSING             = 2;
    LV_EVENT_PRESS_LOST           = 3;
    LV_EVENT_SHORT_CLICKED        = 4;
    LV_EVENT_LONG_PRESSED         = 5;
    LV_EVENT_LONG_PRESSED_REPEAT  = 6;
    LV_EVENT_CLICKED              = 7;
    LV_EVENT_RELEASED             = 8;
    LV_EVENT_FOCUSED              = 14;
    LV_EVENT_DEFOCUSED            = 15;
    LV_EVENT_VALUE_CHANGED        = 28;
    LV_EVENT_READY                = 31;

{ Part selectors }
const
    LV_PART_MAIN      = $000000;
    LV_PART_SCROLLBAR = $010000;
    LV_PART_CURSOR    = $060000;

{ Animation style }
procedure lv_obj_set_style_anim_duration(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;

{ Gradient }
procedure lv_obj_set_style_bg_grad_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_grad_dir(obj: Plv_obj; dir: uint32; selector: uint32); cdecl; external;

const
    LV_GRAD_DIR_NONE = 0;
    LV_GRAD_DIR_VER  = 1;
    LV_GRAD_DIR_HOR  = 2;

{ Label long mode }
const
    LV_LABEL_LONG_WRAP         = 0;
    LV_LABEL_LONG_DOT          = 1;
    LV_LABEL_LONG_SCROLL       = 2;
    LV_LABEL_LONG_SCROLL_CIRCULAR = 3;
    LV_LABEL_LONG_CLIP         = 4;

{ Additional style }
procedure lv_obj_set_style_border_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_border_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_outline_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_outline_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_row(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_column(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;

{ Fonts - LVGL built-in }
var
    lv_font_montserrat_14: uint8; cvar; external;

{ Flex layout constants }
const
    LV_FLEX_FLOW_ROW          = 0;
    LV_FLEX_FLOW_COLUMN       = 1;
    LV_FLEX_FLOW_ROW_WRAP     = 2;
    LV_FLEX_FLOW_COLUMN_WRAP  = 5;

    LV_SIZE_CONTENT           = sint32($3FFFFFFF);
    LV_FLEX_ALIGN_START       = 0;
    LV_FLEX_ALIGN_END         = 1;
    LV_FLEX_ALIGN_CENTER      = 2;
    LV_FLEX_ALIGN_SPACE_EVENLY  = 3;
    LV_FLEX_ALIGN_SPACE_AROUND  = 4;
    LV_FLEX_ALIGN_SPACE_BETWEEN = 5;
    LV_LAYOUT_FLEX              = 1;

{ Alignment constants }
const
    LV_ALIGN_DEFAULT       = 0;
    LV_ALIGN_TOP_LEFT      = 1;
    LV_ALIGN_TOP_MID       = 2;
    LV_ALIGN_TOP_RIGHT     = 3;
    LV_ALIGN_BOTTOM_LEFT   = 4;
    LV_ALIGN_BOTTOM_MID    = 5;
    LV_ALIGN_BOTTOM_RIGHT  = 6;
    LV_ALIGN_LEFT_MID      = 7;
    LV_ALIGN_RIGHT_MID     = 8;
    LV_ALIGN_CENTER        = 9;

    LV_OPA_COVER  = 255;
    LV_OPA_TRANSP = 0;

{ Object flags }
const
    LV_OBJ_FLAG_CLICKABLE     = (1 SHL 1);
    LV_OBJ_FLAG_SCROLLABLE    = (1 SHL 4);
    LV_OBJ_FLAG_HIDDEN        = (1 SHL 0);
    LV_OBJ_FLAG_PRESS_LOCK    = (1 SHL 13);
    LV_OBJ_FLAG_IGNORE_LAYOUT = (1 SHL 17);
    LV_OBJ_FLAG_FLOATING      = (1 SHL 18);

{ Scrollbar mode }
const
    LV_SCROLLBAR_MODE_OFF    = 0;
    LV_SCROLLBAR_MODE_ON     = 1;
    LV_SCROLLBAR_MODE_ACTIVE = 2;
    LV_SCROLLBAR_MODE_AUTO   = 3;

{ Animation enable }
const
    LV_ANIM_OFF = 0;
    LV_ANIM_ON  = 1;

{ Scroll wheel multiplier (pixels per scroll tick) }
const
    SCROLL_PIXELS_PER_TICK = 30;

{ Scroll direction }
const
    LV_DIR_NONE   = $00;
    LV_DIR_LEFT   = $01;
    LV_DIR_RIGHT  = $02;
    LV_DIR_TOP    = $04;
    LV_DIR_BOTTOM = $08;
    LV_DIR_HOR    = LV_DIR_LEFT OR LV_DIR_RIGHT;
    LV_DIR_VER    = LV_DIR_TOP OR LV_DIR_BOTTOM;
    LV_DIR_ALL    = LV_DIR_HOR OR LV_DIR_VER;

{ LVGL key codes }
const
    LV_KEY_UP        = 17;
    LV_KEY_DOWN      = 18;
    LV_KEY_RIGHT     = 19;
    LV_KEY_LEFT      = 20;
    LV_KEY_ESC       = 27;
    LV_KEY_DEL       = 127;
    LV_KEY_BACKSPACE = 8;
    LV_KEY_ENTER     = 10;
    LV_KEY_NEXT      = 9;
    LV_KEY_PREV      = 11;
    LV_KEY_HOME      = 2;
    LV_KEY_END       = 3;

{ ============================================================
  High-level API for kernel
  ============================================================ }

procedure lvgl_init(screen_w, screen_h: uint32);
function  lvgl_handler: uint32;
function  lvgl_get_display: Plv_display;
procedure lvgl_set_mouse_cursor(cursor: Plv_obj);
function  lvgl_get_ticks: uint32;
function  lvgl_get_kb_group: Plv_group;

{ Color helper }
function lv_color_make(r, g, b: uint8): lv_color_t;

implementation

uses
    uidebug;

{ ============================================================
  Wrappers for LVGL inline/macro functions
  ============================================================ }
procedure lv_obj_set_style_pad_all(obj: Plv_obj; pad: sint32; selector: uint32);
begin
    lv_obj_set_style_pad_left(obj, pad, selector);
    lv_obj_set_style_pad_right(obj, pad, selector);
    lv_obj_set_style_pad_top(obj, pad, selector);
    lv_obj_set_style_pad_bottom(obj, pad, selector);
end;

procedure lv_obj_move_foreground(obj: Plv_obj);
begin
    lv_obj_move_to_index(obj, -1);
end;

procedure lv_obj_move_background(obj: Plv_obj);
begin
    lv_obj_move_to_index(obj, 0);
end;

var
    disp        : Plv_display;
    mouse_indev : Plv_indev;
    kb_indev    : Plv_indev;
    kb_group    : Plv_group;

    { Tick counter — incremented by 1024Hz timer ISR }
    tick_accumulator : uint32;

    { Keyboard state for LVGL }
    last_key    : uint32;
    key_pressed : boolean;

const
    { LVGL render buffer: 1/10th of screen }
    LV_BUF_LINES = 120;

var
    lv_buf1: array[0..1600*LV_BUF_LINES-1] of lv_color_t;

{ ============================================================
  Color helper
  ============================================================ }
function lv_color_make(r, g, b: uint8): lv_color_t;
begin
    lv_color_make.blue  := b;
    lv_color_make.green := g;
    lv_color_make.red   := r;
    lv_color_make.alpha := 255;
end;

{ ============================================================
  Flush callback — copies LVGL render buffer to video back buffer
  ============================================================ }
procedure lvgl_flush_cb(disp: Plv_display; area: Plv_area; color_p: Plv_color); cdecl;
var
    y, x, area_w: sint32;
    src: puint32;
    dst: puint32;
    fb_w: uint32;
begin
    fb_w := video.backBufferWidth;
    area_w := (area^.x2 - area^.x1) + 1;
    src := puint32(color_p);

    for y := area^.y1 to area^.y2 do begin
        dst := puint32(video.backBufferLocation + uint32((y * sint32(fb_w) + area^.x1) * 4));
        for x := 0 to area_w - 1 do begin
            dst[x] := src[x];
        end;
        src := puint32(uint32(src) + uint32(area_w * 4));
    end;

    lv_display_flush_ready(disp);
end;

{ ============================================================
  Log callback — route LVGL logs to serial
  ============================================================ }
procedure lvgl_log_cb(level: sint32; buf: pchar); cdecl;
begin
    serial.sendString('[LVGL] ');
    serial.sendString(buf);
end;

{ ============================================================
  Mouse read callback — LVGL polls this for pointer state
  ============================================================ }
procedure lvgl_mouse_read_cb(indev: Plv_indev; data: Plv_indev_data); cdecl;
begin
    data^.point.x := mouse.getMouseX;
    data^.point.y := mouse.getMouseY;
    if mouse.getMouseLMB then
        data^.state := LV_INDEV_STATE_PRESSED
    else
        data^.state := LV_INDEV_STATE_RELEASED;
    data^.continue_reading := false;
end;

{ ============================================================
  Keyboard read callback — LVGL polls this for key state
  ============================================================ }
procedure lvgl_kb_read_cb(indev: Plv_indev; data: Plv_indev_data); cdecl;
begin
    if key_pressed then begin
        data^.key   := last_key;
        data^.state := LV_INDEV_STATE_PRESSED;
        key_pressed := false;
    end else begin
        data^.key   := last_key;
        data^.state := LV_INDEV_STATE_RELEASED;
    end;
    data^.continue_reading := false;
end;

{ ============================================================
  Keyboard hook — receives keypresses from Asuro keyboard driver
  ============================================================ }
procedure lvgl_keyboard_hook(key_info: TKeyInfo);
begin
    { Ctrl+D toggles debug overlay }
    if key_info.CTRL_DOWN and (key_info.key_code = ord('d')) then begin
        uidebug.toggle;
        exit;
    end;

    case key_info.key_code of
        $1B: last_key := LV_KEY_ESC;
        $08: last_key := LV_KEY_BACKSPACE;
        $0D: last_key := LV_KEY_ENTER;
        $09: last_key := LV_KEY_NEXT;
        else last_key := uint32(key_info.key_code);
    end;
    key_pressed := true;
end;

{ ============================================================
  1024Hz timer tick — called from TMR_0_ISR (~1ms per tick)
  ============================================================ }
procedure lvgl_timer_tick(data: void);
begin
    tick_accumulator := tick_accumulator + 1;
end;

{ ============================================================
  High-level init
  ============================================================ }
procedure lvgl_init(screen_w, screen_h: uint32);
begin
    tracer.push_trace('lvgl.init.enter');

    tick_accumulator := 0;
    last_key := 0;
    key_pressed := false;

    { Initialize LVGL core }
    lv_init;

    { Register log callback }
    lv_log_register_print_cb(@lvgl_log_cb);

    { Create display }
    disp := lv_display_create(sint32(screen_w), sint32(screen_h));
    lv_display_set_flush_cb(disp, @lvgl_flush_cb);
    lv_display_set_buffers(disp, @lv_buf1[0], nil,
        SizeOf(lv_buf1), LV_DISPLAY_RENDER_MODE_PARTIAL);

    { Create mouse input device with read callback }
    mouse_indev := lv_indev_create;
    lv_indev_set_type(mouse_indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(mouse_indev, @lvgl_mouse_read_cb);

    { Create keyboard input device with read callback }
    kb_indev := lv_indev_create;
    lv_indev_set_type(kb_indev, LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(kb_indev, @lvgl_kb_read_cb);
    kb_group := lv_group_create;
    lv_group_set_default(kb_group);
    lv_indev_set_group(kb_indev, kb_group);

    { Disable drag-to-scroll on mouse (desktop style: scroll wheel only) }
    lv_indev_set_scroll_limit(mouse_indev, 255);
    lv_indev_set_scroll_throw(mouse_indev, 0);

    { Hook keyboard driver for key events }
    keyboard.hook(@lvgl_keyboard_hook);

    { Hook 1024Hz timer for accurate LVGL tick }
    TMR_0_ISR.hook(uint32(@lvgl_timer_tick));

    tracer.push_trace('lvgl.init.exit');
end;

function lvgl_handler: uint32;
var
    elapsed: uint32;
    scroll_delta: sint32;
    mx, my: sint32;
    pt: lv_point_t;
    target, walk: Plv_obj;
begin
    { Feed accumulated ticks to LVGL }
    elapsed := tick_accumulator;
    tick_accumulator := 0;
    if elapsed > 0 then
        lv_tick_inc(elapsed);

    { Process scroll wheel }
    scroll_delta := mouse.getMouseScroll;
    if scroll_delta <> 0 then begin
        mx := mouse.getMouseX;
        my := mouse.getMouseY;
        pt.x := mx;
        pt.y := my;
        target := lv_indev_search_obj(lv_screen_active, @pt);
        { Walk up to find the nearest scrollable ancestor }
        walk := target;
        while walk <> nil do begin
            if lv_obj_has_flag(walk, LV_OBJ_FLAG_SCROLLABLE) then begin
                lv_obj_scroll_by_bounded(walk, 0, -scroll_delta * SCROLL_PIXELS_PER_TICK, LV_ANIM_OFF);
                break;
            end;
            walk := lv_obj_get_parent(walk);
        end;
    end;

    { Run LVGL timer handler }
    lvgl_handler := lv_timer_handler;
end;

function lvgl_get_display: Plv_display;
begin
    lvgl_get_display := disp;
end;

procedure lvgl_set_mouse_cursor(cursor: Plv_obj);
begin
    lv_indev_set_cursor(mouse_indev, cursor);
end;

function lvgl_get_ticks: uint32;
begin
    lvgl_get_ticks := lv_tick_get;
end;

function lvgl_get_kb_group: Plv_group;
begin
    lvgl_get_kb_group := kb_group;
end;

end.
