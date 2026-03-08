{
    Driver->Video->LVGL - Comprehensive Pascal bindings for LVGL 9.x

    All LVGL C functions are declared as cdecl; external.
    Pascal callbacks are exported with public name for the C linker.
    Inline/macro C functions are wrapped as Pascal procedures.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.video.lvgl;

interface

uses
    driver.video, driver.video.types, core.gfx.color, driver.io.serial, debug.tracer, memory.heap,
    driver.hid.mouse, driver.hid.keyboard, arch.x86.isr.tmr0, core.util, arch.x86.util, io.syslog, driver.video.gpu;

{ ============================================================
  Opaque LVGL pointer core.types (internal C structs)
  ============================================================ }
type
    Plv_display   = pointer;
    Plv_indev     = pointer;
    Plv_obj       = pointer;
    Plv_group     = pointer;
    Plv_theme     = pointer;
    Plv_font      = pointer;
    Plv_event     = pointer;
    Plv_obj_class = pointer;
    Plv_event_dsc = pointer;
    Plv_draw_buf  = pointer;
    Plv_layer     = pointer;
    Plv_draw_task = pointer;
    Plv_image_dsc = pointer;
    Plv_color_filter_dsc = pointer;
    Plv_grad_dsc  = pointer;
    Plv_font_glyph_dsc = pointer;
    Plv_draw_rect_dsc  = pointer;
    Plv_draw_label_dsc = pointer;
    Plv_draw_image_dsc = pointer;
    Plv_draw_line_dsc  = pointer;
    Plv_draw_arc_dsc   = pointer;
    Plv_hit_test_info  = pointer;
    Plv_timer     = pointer;

{ ============================================================
  Stack-allocatable core.types with known sizes
  ============================================================ }
    { lv_style_t — ~12 bytes on 32-bit, padded to 16 for safety }
    lv_style_t = packed array[0..15] of uint8;
    Plv_style  = ^lv_style_t;

    { lv_anim_t — ~80-100 bytes on 32-bit, padded to 128 }
    lv_anim_t = packed array[0..127] of uint8;
    Plv_anim  = ^lv_anim_t;

    { lv_style_transition_dsc_t — ~20 bytes, padded to 24 }
    lv_style_transition_dsc_t = packed array[0..23] of uint8;
    Plv_style_transition_dsc  = ^lv_style_transition_dsc_t;

{ ============================================================
  Record core.types
  ============================================================ }
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

    { When LV_USE_FLOAT=0, lv_point_precise_t = lv_point_t }
    lv_point_precise_t = lv_point_t;
    Plv_point_precise  = ^lv_point_precise_t;

    lv_color_hsv_t = packed record
        h : uint16;
        s : uint8;
        v : uint8;
    end;

    { lv_style_value_t — C union: int32/pointer/color, all 4 bytes on 32-bit }
    lv_style_value_t = packed record
        case byte of
            0: (num: sint32);
            1: (ptr: pointer);
            2: (color: lv_color_t);
    end;
    Plv_style_value = ^lv_style_value_t;

    lv_indev_type_t = (
        LV_INDEV_TYPE_NONE    = 0,
        LV_INDEV_TYPE_POINTER = 1,
        LV_INDEV_TYPE_KEYPAD  = 2,
        LV_INDEV_TYPE_BUTTON  = 3,
        LV_INDEV_TYPE_ENCODER = 4
    );

    lv_indev_state_t = uint32;

    { lv_indev_data_t — matches LVGL 9.x C struct layout }
    lv_indev_data_t = packed record
        point            : lv_point_t;
        key              : uint32;
        btn_id           : uint32;
        enc_diff         : sint16;
        _pad1            : uint16;
        state            : lv_indev_state_t;
        continue_reading : boolean;
    end;
    Plv_indev_data = ^lv_indev_data_t;

{ ============================================================
  Callback core.types
  ============================================================ }
    { Display }
    lv_display_flush_cb_t = procedure(disp: Plv_display; area: Plv_area; color_p: Plv_color); cdecl;
    lv_display_flush_wait_cb_t = procedure(disp: Plv_display); cdecl;

    { Input device }
    lv_indev_read_cb_t = procedure(indev: Plv_indev; data: Plv_indev_data); cdecl;

    { Logging }
    lv_log_print_cb_t = procedure(level: sint32; buf: pchar); cdecl;

    { Events }
    lv_event_cb_t = procedure(e: Plv_event); cdecl;
    lv_event_code_t = uint32;

    { Animation }
    lv_anim_exec_xcb_t = procedure(obj: pointer; value: sint32); cdecl;
    lv_anim_custom_exec_cb_t = procedure(a: Plv_anim; value: sint32); cdecl;
    lv_anim_path_cb_t = function(a: Plv_anim): sint32; cdecl;
    lv_anim_start_cb_t = procedure(a: Plv_anim); cdecl;
    lv_anim_completed_cb_t = procedure(a: Plv_anim); cdecl;
    lv_anim_deleted_cb_t = procedure(a: Plv_anim); cdecl;
    lv_anim_get_value_cb_t = function(a: Plv_anim): sint32; cdecl;

    { Timer }
    lv_timer_cb_t = procedure(timer: Plv_timer); cdecl;
    lv_timer_handler_resume_cb_t = procedure(data: pointer); cdecl;

    { Group }
    lv_group_focus_cb_t = procedure(group: Plv_group); cdecl;
    lv_group_edge_cb_t = procedure(group: Plv_group; wrap_around: boolean); cdecl;

    { Tree walk }
    lv_obj_tree_walk_cb_t = function(obj: Plv_obj; user_data: pointer): uint32; cdecl;

{ ============================================================
  Constants
  ============================================================ }
const
    { Input device states }
    LV_INDEV_STATE_RELEASED = 0;
    LV_INDEV_STATE_PRESSED  = 1;

    { Render modes }
    LV_DISPLAY_RENDER_MODE_PARTIAL = 0;
    LV_DISPLAY_RENDER_MODE_DIRECT  = 1;
    LV_DISPLAY_RENDER_MODE_FULL    = 2;

    { Display rotation }
    LV_DISPLAY_ROTATION_0   = 0;
    LV_DISPLAY_ROTATION_90  = 1;
    LV_DISPLAY_ROTATION_180 = 2;
    LV_DISPLAY_ROTATION_270 = 3;

    { Screen load animations }
    LV_SCR_LOAD_ANIM_NONE         = 0;
    LV_SCR_LOAD_ANIM_OVER_LEFT    = 1;
    LV_SCR_LOAD_ANIM_OVER_RIGHT   = 2;
    LV_SCR_LOAD_ANIM_OVER_TOP     = 3;
    LV_SCR_LOAD_ANIM_OVER_BOTTOM  = 4;
    LV_SCR_LOAD_ANIM_MOVE_LEFT    = 5;
    LV_SCR_LOAD_ANIM_MOVE_RIGHT   = 6;
    LV_SCR_LOAD_ANIM_MOVE_TOP     = 7;
    LV_SCR_LOAD_ANIM_MOVE_BOTTOM  = 8;
    LV_SCR_LOAD_ANIM_FADE_IN      = 9;
    LV_SCR_LOAD_ANIM_FADE_OUT     = 10;
    LV_SCR_LOAD_ANIM_OUT_LEFT     = 11;
    LV_SCR_LOAD_ANIM_OUT_RIGHT    = 12;
    LV_SCR_LOAD_ANIM_OUT_TOP      = 13;
    LV_SCR_LOAD_ANIM_OUT_BOTTOM   = 14;

    { Event codes — Input device }
    LV_EVENT_ALL                  = 0;
    LV_EVENT_PRESSED              = 1;
    LV_EVENT_PRESSING             = 2;
    LV_EVENT_PRESS_LOST           = 3;
    LV_EVENT_SHORT_CLICKED        = 4;
    LV_EVENT_LONG_PRESSED         = 5;
    LV_EVENT_LONG_PRESSED_REPEAT  = 6;
    LV_EVENT_CLICKED              = 7;
    LV_EVENT_RELEASED             = 8;
    LV_EVENT_SCROLL_BEGIN         = 9;
    LV_EVENT_SCROLL_THROW_BEGIN   = 10;
    LV_EVENT_SCROLL_END           = 11;
    LV_EVENT_SCROLL               = 12;
    LV_EVENT_GESTURE              = 13;
    LV_EVENT_KEY                  = 14;
    LV_EVENT_ROTARY               = 15;
    LV_EVENT_FOCUSED              = 16;
    LV_EVENT_DEFOCUSED            = 17;
    LV_EVENT_LEAVE                = 18;
    LV_EVENT_HIT_TEST             = 19;
    LV_EVENT_INDEV_RESET          = 20;
    LV_EVENT_HOVER_OVER           = 21;
    LV_EVENT_HOVER_LEAVE          = 22;
    { Event codes — Drawing }
    LV_EVENT_COVER_CHECK          = 23;
    LV_EVENT_REFR_EXT_DRAW_SIZE   = 24;
    LV_EVENT_DRAW_MAIN_BEGIN      = 25;
    LV_EVENT_DRAW_MAIN            = 26;
    LV_EVENT_DRAW_MAIN_END        = 27;
    LV_EVENT_DRAW_POST_BEGIN      = 28;
    LV_EVENT_DRAW_POST            = 29;
    LV_EVENT_DRAW_POST_END        = 30;
    LV_EVENT_DRAW_TASK_ADDED      = 31;
    { Event codes — Special }
    LV_EVENT_VALUE_CHANGED        = 32;
    LV_EVENT_INSERT               = 33;
    LV_EVENT_REFRESH              = 34;
    LV_EVENT_READY                = 35;
    LV_EVENT_CANCEL               = 36;
    { Event codes — Other }
    LV_EVENT_CREATE               = 37;
    LV_EVENT_DELETE               = 38;
    LV_EVENT_CHILD_CHANGED        = 39;
    LV_EVENT_CHILD_CREATED        = 40;
    LV_EVENT_CHILD_DELETED        = 41;
    LV_EVENT_SCREEN_UNLOAD_START  = 42;
    LV_EVENT_SCREEN_LOAD_START    = 43;
    LV_EVENT_SCREEN_LOADED        = 44;
    LV_EVENT_SCREEN_UNLOADED      = 45;
    LV_EVENT_SIZE_CHANGED         = 46;
    LV_EVENT_STYLE_CHANGED        = 47;
    LV_EVENT_LAYOUT_CHANGED       = 48;
    LV_EVENT_GET_SELF_SIZE        = 49;

    { Part selectors }
    LV_PART_MAIN         = $000000;
    LV_PART_SCROLLBAR    = $010000;
    LV_PART_INDICATOR    = $020000;
    LV_PART_KNOB         = $030000;
    LV_PART_SELECTED     = $040000;
    LV_PART_ITEMS        = $050000;
    LV_PART_CURSOR       = $060000;
    LV_PART_CUSTOM_FIRST = $080000;

    { Object states }
    LV_STATE_DEFAULT   = $0000;
    LV_STATE_CHECKED   = $0001;
    LV_STATE_FOCUSED   = $0002;
    LV_STATE_FOCUS_KEY = $0004;
    LV_STATE_EDITED    = $0008;
    LV_STATE_HOVERED   = $0010;
    LV_STATE_PRESSED   = $0020;
    LV_STATE_SCROLLED  = $0040;
    LV_STATE_DISABLED  = $0080;
    LV_STATE_USER_1    = $1000;
    LV_STATE_USER_2    = $2000;
    LV_STATE_USER_3    = $4000;
    LV_STATE_USER_4    = $8000;
    LV_STATE_ANY       = $FFFF;

    { Object flags }
    LV_OBJ_FLAG_HIDDEN                = (1 SHL 0);
    LV_OBJ_FLAG_CLICKABLE             = (1 SHL 1);
    LV_OBJ_FLAG_CLICK_FOCUSABLE       = (1 SHL 2);
    LV_OBJ_FLAG_CHECKABLE             = (1 SHL 3);
    LV_OBJ_FLAG_SCROLLABLE            = (1 SHL 4);
    LV_OBJ_FLAG_SCROLL_ELASTIC        = (1 SHL 5);
    LV_OBJ_FLAG_SCROLL_MOMENTUM       = (1 SHL 6);
    LV_OBJ_FLAG_SCROLL_ONE            = (1 SHL 7);
    LV_OBJ_FLAG_SCROLL_CHAIN_HOR      = (1 SHL 8);
    LV_OBJ_FLAG_SCROLL_CHAIN_VER      = (1 SHL 9);
    LV_OBJ_FLAG_SCROLL_CHAIN          = (LV_OBJ_FLAG_SCROLL_CHAIN_HOR OR LV_OBJ_FLAG_SCROLL_CHAIN_VER);
    LV_OBJ_FLAG_SCROLL_ON_FOCUS       = (1 SHL 10);
    LV_OBJ_FLAG_SCROLL_WITH_ARROW     = (1 SHL 11);
    LV_OBJ_FLAG_SNAPPABLE             = (1 SHL 12);
    LV_OBJ_FLAG_PRESS_LOCK            = (1 SHL 13);
    LV_OBJ_FLAG_EVENT_BUBBLE          = (1 SHL 14);
    LV_OBJ_FLAG_GESTURE_BUBBLE        = (1 SHL 15);
    LV_OBJ_FLAG_ADV_HITTEST           = (1 SHL 16);
    LV_OBJ_FLAG_IGNORE_LAYOUT         = (1 SHL 17);
    LV_OBJ_FLAG_FLOATING              = (1 SHL 18);
    LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS = (1 SHL 19);
    LV_OBJ_FLAG_OVERFLOW_VISIBLE      = (1 SHL 20);
    LV_OBJ_FLAG_FLEX_IN_NEW_TRACK     = (1 SHL 21);
    LV_OBJ_FLAG_LAYOUT_1              = (1 SHL 23);
    LV_OBJ_FLAG_LAYOUT_2              = (1 SHL 24);
    LV_OBJ_FLAG_WIDGET_1              = (1 SHL 25);
    LV_OBJ_FLAG_WIDGET_2              = (1 SHL 26);
    LV_OBJ_FLAG_USER_1                = (1 SHL 27);
    LV_OBJ_FLAG_USER_2                = (1 SHL 28);
    LV_OBJ_FLAG_USER_3                = (1 SHL 29);
    LV_OBJ_FLAG_USER_4                = (1 SHL 30);

    { Alignment }
    LV_ALIGN_DEFAULT          = 0;
    LV_ALIGN_TOP_LEFT         = 1;
    LV_ALIGN_TOP_MID          = 2;
    LV_ALIGN_TOP_RIGHT        = 3;
    LV_ALIGN_BOTTOM_LEFT      = 4;
    LV_ALIGN_BOTTOM_MID       = 5;
    LV_ALIGN_BOTTOM_RIGHT     = 6;
    LV_ALIGN_LEFT_MID         = 7;
    LV_ALIGN_RIGHT_MID        = 8;
    LV_ALIGN_CENTER           = 9;
    LV_ALIGN_OUT_TOP_LEFT     = 10;
    LV_ALIGN_OUT_TOP_MID      = 11;
    LV_ALIGN_OUT_TOP_RIGHT    = 12;
    LV_ALIGN_OUT_BOTTOM_LEFT  = 13;
    LV_ALIGN_OUT_BOTTOM_MID   = 14;
    LV_ALIGN_OUT_BOTTOM_RIGHT = 15;
    LV_ALIGN_OUT_LEFT_TOP     = 16;
    LV_ALIGN_OUT_LEFT_MID     = 17;
    LV_ALIGN_OUT_LEFT_BOTTOM  = 18;
    LV_ALIGN_OUT_RIGHT_TOP    = 19;
    LV_ALIGN_OUT_RIGHT_MID    = 20;
    LV_ALIGN_OUT_RIGHT_BOTTOM = 21;

    { Opacity }
    LV_OPA_TRANSP = 0;
    LV_OPA_10     = 25;
    LV_OPA_20     = 51;
    LV_OPA_30     = 76;
    LV_OPA_40     = 102;
    LV_OPA_50     = 127;
    LV_OPA_60     = 153;
    LV_OPA_70     = 178;
    LV_OPA_80     = 204;
    LV_OPA_90     = 229;
    LV_OPA_COVER  = 255;

    { Scrollbar mode }
    LV_SCROLLBAR_MODE_OFF    = 0;
    LV_SCROLLBAR_MODE_ON     = 1;
    LV_SCROLLBAR_MODE_ACTIVE = 2;
    LV_SCROLLBAR_MODE_AUTO   = 3;

    { Scroll snap }
    LV_SCROLL_SNAP_NONE   = 0;
    LV_SCROLL_SNAP_START  = 1;
    LV_SCROLL_SNAP_END    = 2;
    LV_SCROLL_SNAP_CENTER = 3;

    { Animation enable }
    LV_ANIM_OFF = 0;
    LV_ANIM_ON  = 1;
    LV_ANIM_REPEAT_INFINITE = $FFFF;

    { Size / coordinate }
    LV_SIZE_CONTENT = sint32($3FFFFFFF);
    LV_COORD_MAX    = sint32($3FFFFFFE);
    LV_COORD_MIN    = sint32(-$3FFFFFFE);

    { Direction }
    LV_DIR_NONE   = $00;
    LV_DIR_LEFT   = $01;
    LV_DIR_RIGHT  = $02;
    LV_DIR_TOP    = $04;
    LV_DIR_BOTTOM = $08;
    LV_DIR_HOR    = LV_DIR_LEFT OR LV_DIR_RIGHT;
    LV_DIR_VER    = LV_DIR_TOP OR LV_DIR_BOTTOM;
    LV_DIR_ALL    = LV_DIR_HOR OR LV_DIR_VER;

    { Gradient direction }
    LV_GRAD_DIR_NONE = 0;
    LV_GRAD_DIR_VER  = 1;
    LV_GRAD_DIR_HOR  = 2;

    { Border side }
    LV_BORDER_SIDE_NONE     = $00;
    LV_BORDER_SIDE_BOTTOM   = $01;
    LV_BORDER_SIDE_TOP      = $02;
    LV_BORDER_SIDE_LEFT     = $04;
    LV_BORDER_SIDE_RIGHT    = $08;
    LV_BORDER_SIDE_FULL     = $0F;
    LV_BORDER_SIDE_INTERNAL = $10;

    { Blend mode }
    LV_BLEND_MODE_NORMAL      = 0;
    LV_BLEND_MODE_ADDITIVE    = 1;
    LV_BLEND_MODE_SUBTRACTIVE = 2;
    LV_BLEND_MODE_MULTIPLY    = 3;

    { Text alignment }
    LV_TEXT_ALIGN_AUTO   = 0;
    LV_TEXT_ALIGN_LEFT   = 1;
    LV_TEXT_ALIGN_CENTER = 2;
    LV_TEXT_ALIGN_RIGHT  = 3;

    { Text decoration }
    LV_TEXT_DECOR_NONE          = $00;
    LV_TEXT_DECOR_UNDERLINE     = $01;
    LV_TEXT_DECOR_STRIKETHROUGH = $02;

    { Base direction }
    LV_BASE_DIR_LTR  = 0;
    LV_BASE_DIR_RTL  = 1;
    LV_BASE_DIR_AUTO = 2;

    { Label long mode }
    LV_LABEL_LONG_WRAP            = 0;
    LV_LABEL_LONG_DOT             = 1;
    LV_LABEL_LONG_SCROLL          = 2;
    LV_LABEL_LONG_SCROLL_CIRCULAR = 3;
    LV_LABEL_LONG_CLIP            = 4;

    { Flex layout }
    LV_LAYOUT_FLEX                   = 1;
    LV_LAYOUT_GRID                   = 2;
    LV_FLEX_FLOW_ROW                 = 0;
    LV_FLEX_FLOW_COLUMN              = 1;
    LV_FLEX_FLOW_ROW_WRAP            = 4;
    LV_FLEX_FLOW_ROW_REVERSE         = 8;
    LV_FLEX_FLOW_ROW_WRAP_REVERSE    = 12;
    LV_FLEX_FLOW_COLUMN_WRAP         = 5;
    LV_FLEX_FLOW_COLUMN_REVERSE      = 9;
    LV_FLEX_FLOW_COLUMN_WRAP_REVERSE = 13;
    LV_FLEX_ALIGN_START              = 0;
    LV_FLEX_ALIGN_END                = 1;
    LV_FLEX_ALIGN_CENTER             = 2;
    LV_FLEX_ALIGN_SPACE_EVENLY       = 3;
    LV_FLEX_ALIGN_SPACE_AROUND       = 4;
    LV_FLEX_ALIGN_SPACE_BETWEEN      = 5;

    { Grid alignment }
    LV_GRID_ALIGN_START         = 0;
    LV_GRID_ALIGN_CENTER        = 1;
    LV_GRID_ALIGN_END           = 2;
    LV_GRID_ALIGN_STRETCH       = 3;
    LV_GRID_ALIGN_SPACE_EVENLY  = 4;
    LV_GRID_ALIGN_SPACE_AROUND  = 5;
    LV_GRID_ALIGN_SPACE_BETWEEN = 6;
    LV_GRID_TEMPLATE_LAST       = sint32($3FFFFFFD);

    { Key codes }
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
    LV_KEY_CTRLC     = 128;   { Ctrl+C — terminal interrupt }

    { Arc mode }
    LV_ARC_MODE_NORMAL      = 0;
    LV_ARC_MODE_SYMMETRICAL = 1;
    LV_ARC_MODE_REVERSE     = 2;

    { Bar mode }
    LV_BAR_MODE_NORMAL      = 0;
    LV_BAR_MODE_SYMMETRICAL = 1;
    LV_BAR_MODE_RANGE       = 2;

    { Bar orientation }
    LV_BAR_ORIENTATION_AUTO       = 0;
    LV_BAR_ORIENTATION_HORIZONTAL = 1;
    LV_BAR_ORIENTATION_VERTICAL   = 2;

    { Slider mode }
    LV_SLIDER_MODE_NORMAL      = 0;
    LV_SLIDER_MODE_SYMMETRICAL = 1;
    LV_SLIDER_MODE_RANGE       = 2;

    { Roller mode }
    LV_ROLLER_MODE_NORMAL   = 0;
    LV_ROLLER_MODE_INFINITE = 1;

    { Keyboard mode }
    LV_KEYBOARD_MODE_TEXT_LOWER = 0;
    LV_KEYBOARD_MODE_TEXT_UPPER = 1;
    LV_KEYBOARD_MODE_SPECIAL    = 2;
    LV_KEYBOARD_MODE_NUMBER     = 3;
    LV_KEYBOARD_MODE_USER_1     = 4;
    LV_KEYBOARD_MODE_USER_2     = 5;
    LV_KEYBOARD_MODE_USER_3     = 6;
    LV_KEYBOARD_MODE_USER_4     = 7;

    { Buttonmatrix ctrl flags }
    LV_BUTTONMATRIX_CTRL_HIDDEN     = $0010;
    LV_BUTTONMATRIX_CTRL_NO_REPEAT  = $0020;
    LV_BUTTONMATRIX_CTRL_DISABLED   = $0040;
    LV_BUTTONMATRIX_CTRL_CHECKABLE  = $0080;
    LV_BUTTONMATRIX_CTRL_CHECKED    = $0100;
    LV_BUTTONMATRIX_CTRL_CLICK_TRIG = $0200;
    LV_BUTTONMATRIX_CTRL_POPOVER    = $0400;
    LV_BUTTONMATRIX_CTRL_CUSTOM_1   = $1000;
    LV_BUTTONMATRIX_CTRL_CUSTOM_2   = $2000;

    { Table cell ctrl }
    LV_TABLE_CELL_CTRL_MERGE_RIGHT = (1 SHL 0);
    LV_TABLE_CELL_CTRL_TEXT_CROP   = (1 SHL 1);
    LV_TABLE_CELL_CTRL_CUSTOM_1    = (1 SHL 4);
    LV_TABLE_CELL_CTRL_CUSTOM_2    = (1 SHL 5);
    LV_TABLE_CELL_CTRL_CUSTOM_3    = (1 SHL 6);
    LV_TABLE_CELL_CTRL_CUSTOM_4    = (1 SHL 7);

    { Image alignment }
    LV_IMAGE_ALIGN_DEFAULT      = 0;
    LV_IMAGE_ALIGN_TOP_LEFT     = 1;
    LV_IMAGE_ALIGN_TOP_MID      = 2;
    LV_IMAGE_ALIGN_TOP_RIGHT    = 3;
    LV_IMAGE_ALIGN_BOTTOM_LEFT  = 4;
    LV_IMAGE_ALIGN_BOTTOM_MID   = 5;
    LV_IMAGE_ALIGN_BOTTOM_RIGHT = 6;
    LV_IMAGE_ALIGN_LEFT_MID     = 7;
    LV_IMAGE_ALIGN_RIGHT_MID    = 8;
    LV_IMAGE_ALIGN_CENTER       = 9;
    LV_IMAGE_ALIGN_STRETCH      = 10;
    LV_IMAGE_ALIGN_TILE         = 11;

    { Group refocus policy }
    LV_GROUP_REFOCUS_POLICY_NEXT = 0;
    LV_GROUP_REFOCUS_POLICY_PREV = 1;

    { Indev mode }
    LV_INDEV_MODE_NONE  = 0;
    LV_INDEV_MODE_TIMER = 1;

    { Result }
    LV_RESULT_INVALID = 0;
    LV_RESULT_OK      = 1;

    { Scroll wheel multiplier (pixels per scroll tick) }
    SCROLL_PIXELS_PER_TICK = 30;

{ ============================================================
  Fonts — LVGL built-in (declared as cvar for C linker)
  ============================================================ }
var
    lv_font_montserrat_14: uint8; cvar; external;
    lv_font_fa_solid_16: uint8; cvar; external;
    hack_14: uint8; cvar; external;

{ ============================================================
  Core Init / Tick / Timer
  ============================================================ }
procedure lv_init; cdecl; external;
procedure lv_deinit; cdecl; external;
procedure lv_tick_inc(tick_period_ms: uint32); cdecl; external;
function  lv_tick_get: uint32; cdecl; external;
function  lv_timer_handler: uint32; cdecl; external;
procedure lv_log_register_print_cb(print_cb: lv_log_print_cb_t); cdecl; external;

{ ============================================================
  Display API
  ============================================================ }
function  lv_display_create(hor_res, ver_res: sint32): Plv_display; cdecl; external;
procedure lv_display_delete(disp: Plv_display); cdecl; external;
procedure lv_display_set_default(disp: Plv_display); cdecl; external;
function  lv_display_get_default: Plv_display; cdecl; external;
function  lv_display_get_next(disp: Plv_display): Plv_display; cdecl; external;
procedure lv_display_set_resolution(disp: Plv_display; hor_res, ver_res: sint32); cdecl; external;
procedure lv_display_set_physical_resolution(disp: Plv_display; hor_res, ver_res: sint32); cdecl; external;
procedure lv_display_set_offset(disp: Plv_display; x, y: sint32); cdecl; external;
procedure lv_display_set_rotation(disp: Plv_display; rotation: uint32); cdecl; external;
procedure lv_display_set_dpi(disp: Plv_display; dpi: sint32); cdecl; external;
function  lv_display_get_horizontal_resolution(disp: Plv_display): sint32; cdecl; external;
function  lv_display_get_vertical_resolution(disp: Plv_display): sint32; cdecl; external;
function  lv_display_get_physical_horizontal_resolution(disp: Plv_display): sint32; cdecl; external;
function  lv_display_get_physical_vertical_resolution(disp: Plv_display): sint32; cdecl; external;
function  lv_display_get_offset_x(disp: Plv_display): sint32; cdecl; external;
function  lv_display_get_offset_y(disp: Plv_display): sint32; cdecl; external;
function  lv_display_get_rotation(disp: Plv_display): uint32; cdecl; external;
function  lv_display_get_dpi(disp: Plv_display): sint32; cdecl; external;
procedure lv_display_set_flush_cb(disp: Plv_display; flush_cb: lv_display_flush_cb_t); cdecl; external;
procedure lv_display_set_flush_wait_cb(disp: Plv_display; wait_cb: lv_display_flush_wait_cb_t); cdecl; external;
procedure lv_display_set_buffers(disp: Plv_display; buf1: pointer; buf2: pointer; buf_size_bytes: uint32; render_mode: sint32); cdecl; external;
procedure lv_display_set_draw_buffers(disp: Plv_display; buf1: Plv_draw_buf; buf2: Plv_draw_buf); cdecl; external;
procedure lv_display_set_render_mode(disp: Plv_display; render_mode: uint32); cdecl; external;
procedure lv_display_set_color_format(disp: Plv_display; color_format: uint32); cdecl; external;
function  lv_display_get_color_format(disp: Plv_display): uint32; cdecl; external;
procedure lv_display_set_antialiasing(disp: Plv_display; en: boolean); cdecl; external;
function  lv_display_get_antialiasing(disp: Plv_display): boolean; cdecl; external;
procedure lv_display_flush_ready(disp: Plv_display); cdecl; external;
function  lv_display_flush_is_last(disp: Plv_display): boolean; cdecl; external;
procedure lv_refr_now(disp: Plv_display); cdecl; external;
procedure lv_display_refr_timer(tmr: pointer); cdecl; external;
function  lv_display_is_double_buffered(disp: Plv_display): boolean; cdecl; external;
function  lv_display_get_screen_active(disp: Plv_display): Plv_obj; cdecl; external;
function  lv_display_get_screen_prev(disp: Plv_display): Plv_obj; cdecl; external;
function  lv_display_get_layer_top(disp: Plv_display): Plv_obj; cdecl; external;
function  lv_display_get_layer_sys(disp: Plv_display): Plv_obj; cdecl; external;
function  lv_display_get_layer_bottom(disp: Plv_display): Plv_obj; cdecl; external;
procedure lv_display_add_event_cb(disp: Plv_display; event_cb: lv_event_cb_t; filter: lv_event_code_t; user_data: pointer); cdecl; external;
function  lv_display_get_event_count(disp: Plv_display): uint32; cdecl; external;
function  lv_display_get_event_dsc(disp: Plv_display; index: uint32): Plv_event_dsc; cdecl; external;
function  lv_display_delete_event(disp: Plv_display; index: uint32): boolean; cdecl; external;
function  lv_display_send_event(disp: Plv_display; code: lv_event_code_t; param: pointer): uint32; cdecl; external;
procedure lv_display_set_theme(disp: Plv_display; th: Plv_theme); cdecl; external;
function  lv_display_get_theme(disp: Plv_display): Plv_theme; cdecl; external;
function  lv_display_get_inactive_time(disp: Plv_display): uint32; cdecl; external;
procedure lv_display_trigger_activity(disp: Plv_display); cdecl; external;
procedure lv_display_enable_invalidation(disp: Plv_display; en: boolean); cdecl; external;
function  lv_display_is_invalidation_enabled(disp: Plv_display): boolean; cdecl; external;
function  lv_display_get_refr_timer(disp: Plv_display): Plv_timer; cdecl; external;
procedure lv_display_delete_refr_timer(disp: Plv_display); cdecl; external;
procedure lv_display_set_user_data(disp: Plv_display; user_data: pointer); cdecl; external;
procedure lv_display_set_driver_data(disp: Plv_display; driver_data: pointer); cdecl; external;
function  lv_display_get_user_data(disp: Plv_display): pointer; cdecl; external;
function  lv_display_get_driver_data(disp: Plv_display): pointer; cdecl; external;
function  lv_display_get_buf_active(disp: Plv_display): Plv_draw_buf; cdecl; external;
procedure lv_display_rotate_area(disp: Plv_display; area: Plv_area); cdecl; external;

{ Screen / layer convenience }
procedure lv_screen_load(scr: Plv_obj); cdecl; external;
procedure lv_screen_load_anim(scr: Plv_obj; anim_type: uint32; time: uint32; delay: uint32; auto_del: boolean); cdecl; external;
function  lv_screen_active: Plv_obj; cdecl; external;
function  lv_layer_top: Plv_obj; cdecl; external;
function  lv_layer_sys: Plv_obj; cdecl; external;
function  lv_layer_bottom: Plv_obj; cdecl; external;
function  lv_dpx(n: sint32): sint32; cdecl; external;
function  lv_display_dpx(disp: Plv_display; n: sint32): sint32; cdecl; external;

{ ============================================================
  Input Device API
  ============================================================ }
function  lv_indev_create: Plv_indev; cdecl; external;
procedure lv_indev_delete(indev: Plv_indev); cdecl; external;
function  lv_indev_get_next(indev: Plv_indev): Plv_indev; cdecl; external;
procedure lv_indev_read(indev: Plv_indev); cdecl; external;
procedure lv_indev_enable(indev: Plv_indev; en: boolean); cdecl; external;
function  lv_indev_active: Plv_indev; cdecl; external;
procedure lv_indev_set_type(indev: Plv_indev; indev_type: lv_indev_type_t); cdecl; external;
procedure lv_indev_set_read_cb(indev: Plv_indev; read_cb: lv_indev_read_cb_t); cdecl; external;
procedure lv_indev_set_user_data(indev: Plv_indev; user_data: pointer); cdecl; external;
procedure lv_indev_set_driver_data(indev: Plv_indev; driver_data: pointer); cdecl; external;
procedure lv_indev_set_display(indev: Plv_indev; disp: Plv_display); cdecl; external;
procedure lv_indev_set_long_press_time(indev: Plv_indev; long_press_time: uint16); cdecl; external;
procedure lv_indev_set_scroll_limit(indev: Plv_indev; scroll_limit: uint8); cdecl; external;
procedure lv_indev_set_scroll_throw(indev: Plv_indev; scroll_throw: uint8); cdecl; external;
function  lv_indev_get_type(indev: Plv_indev): uint32; cdecl; external;
function  lv_indev_get_state(indev: Plv_indev): uint32; cdecl; external;
function  lv_indev_get_group(indev: Plv_indev): Plv_group; cdecl; external;
function  lv_indev_get_display(indev: Plv_indev): Plv_display; cdecl; external;
function  lv_indev_get_user_data(indev: Plv_indev): pointer; cdecl; external;
function  lv_indev_get_driver_data(indev: Plv_indev): pointer; cdecl; external;
function  lv_indev_get_press_moved(indev: Plv_indev): boolean; cdecl; external;
procedure lv_indev_reset(indev: Plv_indev; obj: Plv_obj); cdecl; external;
procedure lv_indev_stop_processing(indev: Plv_indev); cdecl; external;
procedure lv_indev_reset_long_press(indev: Plv_indev); cdecl; external;
procedure lv_indev_set_cursor(indev: Plv_indev; cur_obj: Plv_obj); cdecl; external;
procedure lv_indev_set_group(indev: Plv_indev; group: Plv_group); cdecl; external;
procedure lv_indev_set_button_points(indev: Plv_indev; points: Plv_point); cdecl; external;
procedure lv_indev_get_point(indev: Plv_indev; point: Plv_point); cdecl; external;
function  lv_indev_get_gesture_dir(indev: Plv_indev): uint32; cdecl; external;
function  lv_indev_get_key(indev: Plv_indev): uint32; cdecl; external;
function  lv_indev_get_scroll_dir(indev: Plv_indev): uint32; cdecl; external;
function  lv_indev_get_scroll_obj(indev: Plv_indev): Plv_obj; cdecl; external;
procedure lv_indev_get_vect(indev: Plv_indev; point: Plv_point); cdecl; external;
procedure lv_indev_wait_release(indev: Plv_indev); cdecl; external;
function  lv_indev_get_active_obj: Plv_obj; cdecl; external;
function  lv_indev_get_read_timer(indev: Plv_indev): Plv_timer; cdecl; external;
procedure lv_indev_set_mode(indev: Plv_indev; mode: uint32); cdecl; external;
function  lv_indev_get_mode(indev: Plv_indev): uint32; cdecl; external;
function  lv_indev_search_obj(obj: Plv_obj; point: Plv_point): Plv_obj; cdecl; external;
procedure lv_indev_add_event_cb(indev: Plv_indev; event_cb: lv_event_cb_t; filter: lv_event_code_t; user_data: pointer); cdecl; external;
function  lv_indev_send_event(indev: Plv_indev; code: lv_event_code_t; param: pointer): uint32; cdecl; external;

{ ============================================================
  Group API
  ============================================================ }
function  lv_group_create: Plv_group; cdecl; external;
procedure lv_group_delete(group: Plv_group); cdecl; external;
procedure lv_group_set_default(group: Plv_group); cdecl; external;
function  lv_group_get_default: Plv_group; cdecl; external;
procedure lv_group_add_obj(group: Plv_group; obj: Plv_obj); cdecl; external;
procedure lv_group_swap_obj(obj1: Plv_obj; obj2: Plv_obj); cdecl; external;
procedure lv_group_remove_obj(obj: Plv_obj); cdecl; external;
procedure lv_group_remove_all_objs(group: Plv_group); cdecl; external;
procedure lv_group_focus_obj(obj: Plv_obj); cdecl; external;
procedure lv_group_focus_next(group: Plv_group); cdecl; external;
procedure lv_group_focus_prev(group: Plv_group); cdecl; external;
procedure lv_group_focus_freeze(group: Plv_group; en: boolean); cdecl; external;
function  lv_group_send_data(group: Plv_group; c: uint32): uint32; cdecl; external;
procedure lv_group_set_focus_cb(group: Plv_group; focus_cb: lv_group_focus_cb_t); cdecl; external;
procedure lv_group_set_edge_cb(group: Plv_group; edge_cb: lv_group_edge_cb_t); cdecl; external;
procedure lv_group_set_refocus_policy(group: Plv_group; policy: uint32); cdecl; external;
procedure lv_group_set_editing(group: Plv_group; edit: boolean); cdecl; external;
procedure lv_group_set_wrap(group: Plv_group; en: boolean); cdecl; external;
function  lv_group_get_focused(group: Plv_group): Plv_obj; cdecl; external;
function  lv_group_get_focus_cb(group: Plv_group): lv_group_focus_cb_t; cdecl; external;
function  lv_group_get_edge_cb(group: Plv_group): lv_group_edge_cb_t; cdecl; external;
function  lv_group_get_editing(group: Plv_group): boolean; cdecl; external;
function  lv_group_get_wrap(group: Plv_group): boolean; cdecl; external;
function  lv_group_get_obj_count(group: Plv_group): uint32; cdecl; external;
function  lv_group_get_obj_by_index(group: Plv_group; index: uint32): Plv_obj; cdecl; external;
function  lv_group_get_count: uint32; cdecl; external;
function  lv_group_by_index(index: uint32): Plv_group; cdecl; external;

{ ============================================================
  Object — Core (lv_obj.h)
  ============================================================ }
function  lv_obj_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_obj_add_flag(obj: Plv_obj; flag: uint32); cdecl; external;
procedure lv_obj_remove_flag(obj: Plv_obj; flag: uint32); cdecl; external;
procedure lv_obj_update_flag(obj: Plv_obj; flag: uint32; v: boolean); cdecl; external;
procedure lv_obj_add_state(obj: Plv_obj; state: uint16); cdecl; external;
procedure lv_obj_remove_state(obj: Plv_obj; state: uint16); cdecl; external;
procedure lv_obj_set_state(obj: Plv_obj; state: uint16; v: boolean); cdecl; external;
procedure lv_obj_set_user_data(obj: Plv_obj; user_data: pointer); cdecl; external;
function  lv_obj_has_flag(obj: Plv_obj; flag: uint32): boolean; cdecl; external;
function  lv_obj_has_flag_any(obj: Plv_obj; flag: uint32): boolean; cdecl; external;
function  lv_obj_get_state(obj: Plv_obj): uint16; cdecl; external;
function  lv_obj_has_state(obj: Plv_obj; state: uint16): boolean; cdecl; external;
function  lv_obj_get_group(obj: Plv_obj): Plv_group; cdecl; external;
function  lv_obj_get_user_data(obj: Plv_obj): pointer; cdecl; external;
procedure lv_obj_allocate_spec_attr(obj: Plv_obj); cdecl; external;
function  lv_obj_check_type(obj: Plv_obj; class_p: Plv_obj_class): boolean; cdecl; external;
function  lv_obj_has_class(obj: Plv_obj; class_p: Plv_obj_class): boolean; cdecl; external;
function  lv_obj_get_class(obj: Plv_obj): Plv_obj_class; cdecl; external;
function  lv_obj_is_valid(obj: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Object — Position & Size (lv_obj_pos.h)
  ============================================================ }
procedure lv_obj_set_pos(obj: Plv_obj; x, y: sint32); cdecl; external;
procedure lv_obj_set_x(obj: Plv_obj; x: sint32); cdecl; external;
procedure lv_obj_set_y(obj: Plv_obj; y: sint32); cdecl; external;
procedure lv_obj_set_size(obj: Plv_obj; w, h: sint32); cdecl; external;
function  lv_obj_refr_size(obj: Plv_obj): boolean; cdecl; external;
procedure lv_obj_set_width(obj: Plv_obj; w: sint32); cdecl; external;
procedure lv_obj_set_height(obj: Plv_obj; h: sint32); cdecl; external;
procedure lv_obj_set_content_width(obj: Plv_obj; w: sint32); cdecl; external;
procedure lv_obj_set_content_height(obj: Plv_obj; h: sint32); cdecl; external;
procedure lv_obj_set_layout(obj: Plv_obj; layout: uint32); cdecl; external;
function  lv_obj_is_layout_positioned(obj: Plv_obj): boolean; cdecl; external;
procedure lv_obj_mark_layout_as_dirty(obj: Plv_obj); cdecl; external;
procedure lv_obj_update_layout(obj: Plv_obj); cdecl; external;
procedure lv_obj_set_align(obj: Plv_obj; align: uint8); cdecl; external;
procedure lv_obj_align(obj: Plv_obj; align: uint8; x_ofs, y_ofs: sint32); cdecl; external;
procedure lv_obj_align_to(obj: Plv_obj; base: Plv_obj; align: uint8; x_ofs, y_ofs: sint32); cdecl; external;
procedure lv_obj_center(obj: Plv_obj); cdecl; external;
procedure lv_obj_get_coords(obj: Plv_obj; coords: Plv_area); cdecl; external;
function  lv_obj_get_x(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_x2(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_y(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_y2(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_x_aligned(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_y_aligned(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_width(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_height(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_content_width(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_content_height(obj: Plv_obj): sint32; cdecl; external;
procedure lv_obj_get_content_coords(obj: Plv_obj; area: Plv_area); cdecl; external;
function  lv_obj_get_self_width(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_self_height(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_refresh_self_size(obj: Plv_obj): boolean; cdecl; external;
procedure lv_obj_refr_pos(obj: Plv_obj); cdecl; external;
procedure lv_obj_move_to(obj: Plv_obj; x, y: sint32); cdecl; external;
procedure lv_obj_move_children_by(obj: Plv_obj; x_diff, y_diff: sint32; ignore_floating: boolean); cdecl; external;
procedure lv_obj_transform_point(obj: Plv_obj; p: Plv_point; flags: uint32); cdecl; external;
procedure lv_obj_get_transformed_area(obj: Plv_obj; area: Plv_area; flags: uint32); cdecl; external;
procedure lv_obj_invalidate_area(obj: Plv_obj; area: Plv_area); cdecl; external;
procedure lv_obj_invalidate(obj: Plv_obj); cdecl; external;
function  lv_obj_area_is_visible(obj: Plv_obj; area: Plv_area): boolean; cdecl; external;
function  lv_obj_is_visible(obj: Plv_obj): boolean; cdecl; external;
procedure lv_obj_set_ext_click_area(obj: Plv_obj; size: sint32); cdecl; external;
procedure lv_obj_get_click_area(obj: Plv_obj; area: Plv_area); cdecl; external;
function  lv_obj_hit_test(obj: Plv_obj; point: Plv_point): boolean; cdecl; external;
function  lv_clamp_width(width, min_width, max_width, ref_width: sint32): sint32; cdecl; external;
function  lv_clamp_height(height, min_height, max_height, ref_height: sint32): sint32; cdecl; external;

{ ============================================================
  Object — Scroll (lv_obj_scroll.h)
  ============================================================ }
procedure lv_obj_set_scrollbar_mode(obj: Plv_obj; mode: uint32); cdecl; external;
procedure lv_obj_set_scroll_dir(obj: Plv_obj; dir: uint32); cdecl; external;
procedure lv_obj_set_scroll_snap_x(obj: Plv_obj; align: uint32); cdecl; external;
procedure lv_obj_set_scroll_snap_y(obj: Plv_obj; align: uint32); cdecl; external;
function  lv_obj_get_scrollbar_mode(obj: Plv_obj): uint32; cdecl; external;
function  lv_obj_get_scroll_dir(obj: Plv_obj): uint32; cdecl; external;
function  lv_obj_get_scroll_snap_x(obj: Plv_obj): uint32; cdecl; external;
function  lv_obj_get_scroll_snap_y(obj: Plv_obj): uint32; cdecl; external;
function  lv_obj_get_scroll_x(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_scroll_y(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_scroll_top(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_scroll_bottom(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_scroll_left(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_scroll_right(obj: Plv_obj): sint32; cdecl; external;
procedure lv_obj_get_scroll_end(obj: Plv_obj; end_point: Plv_point); cdecl; external;
procedure lv_obj_scroll_by(obj: Plv_obj; x, y: sint32; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_by_bounded(obj: Plv_obj; dx, dy: sint32; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_to(obj: Plv_obj; x, y: sint32; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_to_x(obj: Plv_obj; x: sint32; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_to_y(obj: Plv_obj; y: sint32; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_to_view(obj: Plv_obj; anim_en: uint32); cdecl; external;
procedure lv_obj_scroll_to_view_recursive(obj: Plv_obj; anim_en: uint32); cdecl; external;
function  lv_obj_is_scrolling(obj: Plv_obj): boolean; cdecl; external;
procedure lv_obj_update_snap(obj: Plv_obj; anim_en: uint32); cdecl; external;
procedure lv_obj_get_scrollbar_area(obj: Plv_obj; hor: Plv_area; ver: Plv_area); cdecl; external;
procedure lv_obj_scrollbar_invalidate(obj: Plv_obj); cdecl; external;
procedure lv_obj_readjust_scroll(obj: Plv_obj; anim_en: uint32); cdecl; external;

{ ============================================================
  Object — Style General (lv_obj_style.h)
  ============================================================ }
procedure lv_obj_add_style(obj: Plv_obj; style: Plv_style; selector: uint32); cdecl; external;
function  lv_obj_replace_style(obj: Plv_obj; old_style: Plv_style; new_style: Plv_style; selector: uint32): boolean; cdecl; external;
procedure lv_obj_remove_style(obj: Plv_obj; style: Plv_style; selector: uint32); cdecl; external;
procedure lv_obj_remove_style_all(obj: Plv_obj); cdecl; external;
procedure lv_obj_report_style_change(style: Plv_style); cdecl; external;
procedure lv_obj_refresh_style(obj: Plv_obj; part: uint32; prop: uint32); cdecl; external;
procedure lv_obj_enable_style_refresh(en: boolean); cdecl; external;
function  lv_obj_get_style_prop(obj: Plv_obj; part: uint32; prop: uint32): lv_style_value_t; cdecl; external;
function  lv_obj_has_style_prop(obj: Plv_obj; selector: uint32; prop: uint32): boolean; cdecl; external;
procedure lv_obj_set_local_style_prop(obj: Plv_obj; prop: uint32; value: lv_style_value_t; selector: uint32); cdecl; external;
function  lv_obj_get_local_style_prop(obj: Plv_obj; prop: uint32; value: Plv_style_value; selector: uint32): uint32; cdecl; external;
function  lv_obj_remove_local_style_prop(obj: Plv_obj; prop: uint32; selector: uint32): boolean; cdecl; external;
procedure lv_obj_fade_in(obj: Plv_obj; time: uint32; delay: uint32); cdecl; external;
procedure lv_obj_fade_out(obj: Plv_obj; time: uint32; delay: uint32); cdecl; external;

{ ============================================================
  Object — Style setters (lv_obj_style_gen.h) — Sizing
  ============================================================ }
procedure lv_obj_set_style_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_min_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_max_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_height(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_min_height(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_max_height(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_length(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_x(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_y(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_align(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;

{ Style setters — Transform }
procedure lv_obj_set_style_transform_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_height(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_translate_x(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_translate_y(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_scale_x(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_scale_y(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_rotation(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_pivot_x(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_pivot_y(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_skew_x(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transform_skew_y(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;

{ Style setters — Padding }
procedure lv_obj_set_style_pad_top(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_bottom(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_left(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_right(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_row(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_pad_column(obj: Plv_obj; pad: sint32; selector: uint32); cdecl; external;

{ Style setters — Margin }
procedure lv_obj_set_style_margin_top(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_margin_bottom(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_margin_left(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_margin_right(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;

{ Style setters — Background }
procedure lv_obj_set_style_bg_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_grad_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_grad_dir(obj: Plv_obj; dir: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_main_stop(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_grad_stop(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_main_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_grad_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_grad(obj: Plv_obj; value: Plv_grad_dsc; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_image_src(obj: Plv_obj; value: pointer; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_image_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_image_recolor(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_image_recolor_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bg_image_tiled(obj: Plv_obj; value: boolean; selector: uint32); cdecl; external;

{ Style setters — Border }
procedure lv_obj_set_style_border_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_border_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_border_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_border_side(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_border_post(obj: Plv_obj; value: boolean; selector: uint32); cdecl; external;

{ Style setters — Outline }
procedure lv_obj_set_style_outline_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_outline_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_outline_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_outline_pad(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;

{ Style setters — Shadow }
procedure lv_obj_set_style_shadow_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_offset_x(obj: Plv_obj; ofs: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_offset_y(obj: Plv_obj; ofs: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_spread(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_shadow_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;

{ Style setters — Image }
procedure lv_obj_set_style_image_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_image_recolor(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_image_recolor_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;

{ Style setters — Line }
procedure lv_obj_set_style_line_width(obj: Plv_obj; width: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_dash_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_dash_gap(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_rounded(obj: Plv_obj; en: boolean; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_line_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;

{ Style setters — Arc }
procedure lv_obj_set_style_arc_width(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_arc_rounded(obj: Plv_obj; en: boolean; selector: uint32); cdecl; external;
procedure lv_obj_set_style_arc_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_arc_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_arc_image_src(obj: Plv_obj; value: pointer; selector: uint32); cdecl; external;

{ Style setters — Text }
procedure lv_obj_set_style_text_color(obj: Plv_obj; color: lv_color_t; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_font(obj: Plv_obj; font: Plv_font; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_letter_space(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_line_space(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_decor(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_text_align(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;

{ Style setters — Misc }
procedure lv_obj_set_style_radius(obj: Plv_obj; radius: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_clip_corner(obj: Plv_obj; en: boolean; selector: uint32); cdecl; external;
procedure lv_obj_set_style_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_opa_layered(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_color_filter_dsc(obj: Plv_obj; value: Plv_color_filter_dsc; selector: uint32); cdecl; external;
procedure lv_obj_set_style_color_filter_opa(obj: Plv_obj; opa: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_anim(obj: Plv_obj; value: Plv_anim; selector: uint32); cdecl; external;
procedure lv_obj_set_style_anim_duration(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_transition(obj: Plv_obj; value: Plv_style_transition_dsc; selector: uint32); cdecl; external;
procedure lv_obj_set_style_blend_mode(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_layout(obj: Plv_obj; layout: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_base_dir(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;
procedure lv_obj_set_style_bitmap_mask_src(obj: Plv_obj; value: pointer; selector: uint32); cdecl; external;
procedure lv_obj_set_style_rotary_sensitivity(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;

{ Style setters — Flex (on obj via style) }
procedure lv_obj_set_style_flex_flow(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_flex_main_place(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_flex_cross_place(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_flex_track_place(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_flex_grow(obj: Plv_obj; value: uint8; selector: uint32); cdecl; external;

{ Style setters — Grid (on obj via style) }
procedure lv_obj_set_style_grid_column_dsc_array(obj: Plv_obj; value: pointer; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_column_align(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_row_dsc_array(obj: Plv_obj; value: pointer; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_row_align(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_cell_column_pos(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_cell_x_align(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_cell_column_span(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_cell_row_pos(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_cell_y_align(obj: Plv_obj; value: uint32; selector: uint32); cdecl; external;
procedure lv_obj_set_style_grid_cell_row_span(obj: Plv_obj; value: sint32; selector: uint32); cdecl; external;

{ Pascal wrappers for inline/macro style setters }
procedure lv_obj_set_style_pad_all(obj: Plv_obj; pad: sint32; selector: uint32);
procedure lv_obj_set_style_pad_gap(obj: Plv_obj; gap: sint32; selector: uint32);

{ ============================================================
  Object — Event (lv_obj_event.h)
  ============================================================ }
function  lv_obj_send_event(obj: Plv_obj; event_code: lv_event_code_t; param: pointer): uint32; cdecl; external;
procedure lv_obj_add_event_cb(obj: Plv_obj; event_cb: lv_event_cb_t; filter: lv_event_code_t; user_data: pointer); cdecl; external;
function  lv_obj_get_event_count(obj: Plv_obj): uint32; cdecl; external;
function  lv_obj_get_event_dsc(obj: Plv_obj; index: uint32): Plv_event_dsc; cdecl; external;
function  lv_obj_remove_event(obj: Plv_obj; index: uint32): boolean; cdecl; external;
function  lv_obj_remove_event_cb(obj: Plv_obj; event_cb: lv_event_cb_t): boolean; cdecl; external;
function  lv_event_get_code(e: Plv_event): lv_event_code_t; cdecl; external;
function  lv_event_get_target(e: Plv_event): Plv_obj; cdecl; external;
function  lv_event_get_target_obj(e: Plv_event): Plv_obj; cdecl; external;
function  lv_event_get_current_target_obj(e: Plv_event): Plv_obj; cdecl; external;
function  lv_event_get_user_data(e: Plv_event): pointer; cdecl; external;
function  lv_event_get_key(e: Plv_event): uint32; cdecl; external;
function  lv_event_get_rotary_diff(e: Plv_event): sint32; cdecl; external;
function  lv_event_get_indev(e: Plv_event): Plv_indev; cdecl; external;
function  lv_event_get_layer(e: Plv_event): Plv_layer; cdecl; external;
function  lv_event_get_old_size(e: Plv_event): Plv_area; cdecl; external;
function  lv_event_get_draw_task(e: Plv_event): Plv_draw_task; cdecl; external;
procedure lv_event_set_ext_draw_size(e: Plv_event; size: sint32); cdecl; external;
function  lv_event_get_self_size_info(e: Plv_event): Plv_point; cdecl; external;
function  lv_event_get_hit_test_info(e: Plv_event): Plv_hit_test_info; cdecl; external;
function  lv_event_get_cover_area(e: Plv_event): Plv_area; cdecl; external;
procedure lv_event_set_cover_res(e: Plv_event; res: uint32); cdecl; external;

{ ============================================================
  Object — Tree (lv_obj_tree.h)
  ============================================================ }
procedure lv_obj_delete(obj: Plv_obj); cdecl; external;
procedure lv_obj_clean(obj: Plv_obj); cdecl; external;
procedure lv_obj_delete_delayed(obj: Plv_obj; delay_ms: uint32); cdecl; external;
procedure lv_obj_delete_async(obj: Plv_obj); cdecl; external;
procedure lv_obj_set_parent(obj: Plv_obj; parent: Plv_obj); cdecl; external;
procedure lv_obj_swap(obj1: Plv_obj; obj2: Plv_obj); cdecl; external;
procedure lv_obj_move_to_index(obj: Plv_obj; index: sint32); cdecl; external;
function  lv_obj_get_screen(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_obj_get_display(obj: Plv_obj): Plv_display; cdecl; external;
function  lv_obj_get_parent(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_obj_get_child(obj: Plv_obj; idx: sint32): Plv_obj; cdecl; external;
function  lv_obj_get_child_by_type(obj: Plv_obj; idx: sint32; class_p: Plv_obj_class): Plv_obj; cdecl; external;
function  lv_obj_get_sibling(obj: Plv_obj; idx: sint32): Plv_obj; cdecl; external;
function  lv_obj_get_sibling_by_type(obj: Plv_obj; idx: sint32; class_p: Plv_obj_class): Plv_obj; cdecl; external;
function  lv_obj_get_child_count(obj: Plv_obj): uint32; cdecl; external;
function  lv_obj_get_child_count_by_type(obj: Plv_obj; class_p: Plv_obj_class): uint32; cdecl; external;
function  lv_obj_get_index(obj: Plv_obj): sint32; cdecl; external;
function  lv_obj_get_index_by_type(obj: Plv_obj; class_p: Plv_obj_class): sint32; cdecl; external;
procedure lv_obj_tree_walk(start_obj: Plv_obj; cb: lv_obj_tree_walk_cb_t; user_data: pointer); cdecl; external;

{ Pascal wrappers }
procedure lv_obj_move_foreground(obj: Plv_obj);
procedure lv_obj_move_background(obj: Plv_obj);

{ ============================================================
  Object — Class (lv_obj_class.h)
  ============================================================ }
function  lv_obj_class_create_obj(class_p: Plv_obj_class; parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_obj_class_init_obj(obj: Plv_obj); cdecl; external;
function  lv_obj_is_editable(obj: Plv_obj): boolean; cdecl; external;
function  lv_obj_is_group_def(obj: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Object — Draw (lv_obj_draw.h)
  ============================================================ }
procedure lv_obj_init_draw_rect_dsc(obj: Plv_obj; part: uint32; draw_dsc: Plv_draw_rect_dsc); cdecl; external;
procedure lv_obj_init_draw_label_dsc(obj: Plv_obj; part: uint32; draw_dsc: Plv_draw_label_dsc); cdecl; external;
procedure lv_obj_init_draw_image_dsc(obj: Plv_obj; part: uint32; draw_dsc: Plv_draw_image_dsc); cdecl; external;
procedure lv_obj_init_draw_line_dsc(obj: Plv_obj; part: uint32; draw_dsc: Plv_draw_line_dsc); cdecl; external;
procedure lv_obj_init_draw_arc_dsc(obj: Plv_obj; part: uint32; draw_dsc: Plv_draw_arc_dsc); cdecl; external;
function  lv_obj_calculate_ext_draw_size(obj: Plv_obj; part: uint32): sint32; cdecl; external;
procedure lv_obj_refresh_ext_draw_size(obj: Plv_obj); cdecl; external;

{ ============================================================
  Style — Init & management (lv_style.h)
  ============================================================ }
procedure lv_style_init(style: Plv_style); cdecl; external;
procedure lv_style_reset(style: Plv_style); cdecl; external;
function  lv_style_remove_prop(style: Plv_style; prop: uint32): boolean; cdecl; external;
procedure lv_style_set_prop(style: Plv_style; prop: uint32; value: lv_style_value_t); cdecl; external;
function  lv_style_get_prop(style: Plv_style; prop: uint32; value: Plv_style_value): uint32; cdecl; external;
procedure lv_style_transition_dsc_init(tr: Plv_style_transition_dsc; props: pointer; path_cb: lv_anim_path_cb_t; time: uint32; delay: uint32; user_data: pointer); cdecl; external;
function  lv_style_is_empty(style: Plv_style): boolean; cdecl; external;

{ ============================================================
  Style — Property setters (lv_style_gen.h)
  ============================================================ }
{ Sizing }
procedure lv_style_set_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_min_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_max_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_height(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_min_height(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_max_height(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_length(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_x(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_y(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_align(style: Plv_style; value: uint8); cdecl; external;
{ Transform }
procedure lv_style_set_transform_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_height(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_translate_x(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_translate_y(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_scale_x(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_scale_y(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_rotation(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_pivot_x(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_pivot_y(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_skew_x(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_transform_skew_y(style: Plv_style; value: sint32); cdecl; external;
{ Padding }
procedure lv_style_set_pad_top(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_pad_bottom(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_pad_left(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_pad_right(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_pad_row(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_pad_column(style: Plv_style; value: sint32); cdecl; external;
{ Margin }
procedure lv_style_set_margin_top(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_margin_bottom(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_margin_left(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_margin_right(style: Plv_style; value: sint32); cdecl; external;
{ Background }
procedure lv_style_set_bg_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_bg_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_bg_grad_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_bg_grad_dir(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_bg_main_stop(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_bg_grad_stop(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_bg_main_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_bg_grad_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_bg_grad(style: Plv_style; value: Plv_grad_dsc); cdecl; external;
procedure lv_style_set_bg_image_src(style: Plv_style; value: pointer); cdecl; external;
procedure lv_style_set_bg_image_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_bg_image_recolor(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_bg_image_recolor_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_bg_image_tiled(style: Plv_style; value: boolean); cdecl; external;
{ Border }
procedure lv_style_set_border_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_border_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_border_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_border_side(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_border_post(style: Plv_style; value: boolean); cdecl; external;
{ Outline }
procedure lv_style_set_outline_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_outline_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_outline_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_outline_pad(style: Plv_style; value: sint32); cdecl; external;
{ Shadow }
procedure lv_style_set_shadow_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_shadow_offset_x(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_shadow_offset_y(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_shadow_spread(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_shadow_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_shadow_opa(style: Plv_style; value: uint8); cdecl; external;
{ Image }
procedure lv_style_set_image_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_image_recolor(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_image_recolor_opa(style: Plv_style; value: uint8); cdecl; external;
{ Line }
procedure lv_style_set_line_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_line_dash_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_line_dash_gap(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_line_rounded(style: Plv_style; value: boolean); cdecl; external;
procedure lv_style_set_line_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_line_opa(style: Plv_style; value: uint8); cdecl; external;
{ Arc }
procedure lv_style_set_arc_width(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_arc_rounded(style: Plv_style; value: boolean); cdecl; external;
procedure lv_style_set_arc_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_arc_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_arc_image_src(style: Plv_style; value: pointer); cdecl; external;
{ Text }
procedure lv_style_set_text_color(style: Plv_style; value: lv_color_t); cdecl; external;
procedure lv_style_set_text_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_text_font(style: Plv_style; value: Plv_font); cdecl; external;
procedure lv_style_set_text_letter_space(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_text_line_space(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_text_decor(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_text_align(style: Plv_style; value: uint8); cdecl; external;
{ Misc }
procedure lv_style_set_radius(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_clip_corner(style: Plv_style; value: boolean); cdecl; external;
procedure lv_style_set_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_opa_layered(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_color_filter_dsc(style: Plv_style; value: Plv_color_filter_dsc); cdecl; external;
procedure lv_style_set_color_filter_opa(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_anim(style: Plv_style; value: Plv_anim); cdecl; external;
procedure lv_style_set_anim_duration(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_transition(style: Plv_style; value: Plv_style_transition_dsc); cdecl; external;
procedure lv_style_set_blend_mode(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_layout(style: Plv_style; value: uint16); cdecl; external;
procedure lv_style_set_base_dir(style: Plv_style; value: uint8); cdecl; external;
procedure lv_style_set_bitmap_mask_src(style: Plv_style; value: pointer); cdecl; external;
procedure lv_style_set_rotary_sensitivity(style: Plv_style; value: uint32); cdecl; external;
{ Flex on style }
procedure lv_style_set_flex_flow(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_flex_main_place(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_flex_cross_place(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_flex_track_place(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_flex_grow(style: Plv_style; value: uint8); cdecl; external;
{ Grid on style }
procedure lv_style_set_grid_column_dsc_array(style: Plv_style; value: pointer); cdecl; external;
procedure lv_style_set_grid_column_align(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_grid_row_dsc_array(style: Plv_style; value: pointer); cdecl; external;
procedure lv_style_set_grid_row_align(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_grid_cell_column_pos(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_grid_cell_x_align(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_grid_cell_column_span(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_grid_cell_row_pos(style: Plv_style; value: sint32); cdecl; external;
procedure lv_style_set_grid_cell_y_align(style: Plv_style; value: uint32); cdecl; external;
procedure lv_style_set_grid_cell_row_span(style: Plv_style; value: sint32); cdecl; external;

{ ============================================================
  Flex Layout API (lv_flex.h)
  ============================================================ }
procedure lv_obj_set_flex_flow(obj: Plv_obj; flow: uint32); cdecl; external;
procedure lv_obj_set_flex_align(obj: Plv_obj; main_place, cross_place, track_place: uint32); cdecl; external;
procedure lv_obj_set_flex_grow(obj: Plv_obj; grow: uint8); cdecl; external;

{ ============================================================
  Grid Layout API (lv_grid.h)
  ============================================================ }
procedure lv_obj_set_grid_dsc_array(obj: Plv_obj; col_dsc: pointer; row_dsc: pointer); cdecl; external;
procedure lv_obj_set_grid_align(obj: Plv_obj; column_align, row_align: uint32); cdecl; external;
procedure lv_obj_set_grid_cell(obj: Plv_obj; column_align: uint32; col_pos, col_span: sint32; row_align: uint32; row_pos, row_span: sint32); cdecl; external;
function  lv_grid_fr(x: uint8): sint32; cdecl; external;

{ ============================================================
  Theme API
  ============================================================ }
function  lv_theme_default_init(disp: Plv_display; color_primary, color_secondary: lv_color_t; dark: boolean; font: Plv_font): Plv_theme; cdecl; external;
function  lv_theme_default_get: Plv_theme; cdecl; external;
function  lv_theme_default_is_inited: boolean; cdecl; external;
procedure lv_theme_default_deinit; cdecl; external;
function  lv_theme_simple_init(disp: Plv_display): Plv_theme; cdecl; external;
function  lv_theme_simple_get: Plv_theme; cdecl; external;
function  lv_theme_simple_is_inited: boolean; cdecl; external;
procedure lv_theme_simple_deinit; cdecl; external;

{ ============================================================
  Animation API (lv_anim.h)
  ============================================================ }
procedure lv_anim_init(a: Plv_anim); cdecl; external;
procedure lv_anim_set_var(a: Plv_anim; v: pointer); cdecl; external;
procedure lv_anim_set_exec_cb(a: Plv_anim; exec_cb: lv_anim_exec_xcb_t); cdecl; external;
procedure lv_anim_set_duration(a: Plv_anim; duration: uint32); cdecl; external;
procedure lv_anim_set_time(a: Plv_anim; duration: uint32); cdecl; external;
procedure lv_anim_set_delay(a: Plv_anim; delay: uint32); cdecl; external;
procedure lv_anim_set_values(a: Plv_anim; start_val, end_val: sint32); cdecl; external;
procedure lv_anim_set_custom_exec_cb(a: Plv_anim; exec_cb: lv_anim_custom_exec_cb_t); cdecl; external;
procedure lv_anim_set_path_cb(a: Plv_anim; path_cb: lv_anim_path_cb_t); cdecl; external;
procedure lv_anim_set_start_cb(a: Plv_anim; start_cb: lv_anim_start_cb_t); cdecl; external;
procedure lv_anim_set_get_value_cb(a: Plv_anim; get_value_cb: lv_anim_get_value_cb_t); cdecl; external;
procedure lv_anim_set_completed_cb(a: Plv_anim; completed_cb: lv_anim_completed_cb_t); cdecl; external;
procedure lv_anim_set_deleted_cb(a: Plv_anim; deleted_cb: lv_anim_deleted_cb_t); cdecl; external;
procedure lv_anim_set_playback_duration(a: Plv_anim; duration: uint32); cdecl; external;
procedure lv_anim_set_playback_time(a: Plv_anim; duration: uint32); cdecl; external;
procedure lv_anim_set_playback_delay(a: Plv_anim; delay: uint32); cdecl; external;
procedure lv_anim_set_repeat_count(a: Plv_anim; cnt: uint32); cdecl; external;
procedure lv_anim_set_repeat_delay(a: Plv_anim; delay: uint32); cdecl; external;
procedure lv_anim_set_early_apply(a: Plv_anim; en: boolean); cdecl; external;
procedure lv_anim_set_user_data(a: Plv_anim; user_data: pointer); cdecl; external;
procedure lv_anim_set_bezier3_param(a: Plv_anim; x1, y1, x2, y2: sint16); cdecl; external;
function  lv_anim_start(a: Plv_anim): Plv_anim; cdecl; external;
function  lv_anim_get_delay(a: Plv_anim): uint32; cdecl; external;
function  lv_anim_get_playtime(a: Plv_anim): uint32; cdecl; external;
function  lv_anim_get_time(a: Plv_anim): uint32; cdecl; external;
function  lv_anim_get_repeat_count(a: Plv_anim): uint32; cdecl; external;
function  lv_anim_get_user_data(a: Plv_anim): pointer; cdecl; external;
function  lv_anim_delete(v: pointer; exec_cb: lv_anim_exec_xcb_t): boolean; cdecl; external;
procedure lv_anim_delete_all; cdecl; external;
function  lv_anim_get(v: pointer; exec_cb: lv_anim_exec_xcb_t): Plv_anim; cdecl; external;
function  lv_anim_count_running: uint16; cdecl; external;
function  lv_anim_speed(speed: uint32): uint32; cdecl; external;
function  lv_anim_speed_clamped(speed, min_time, max_time: uint32): uint32; cdecl; external;
function  lv_anim_speed_to_time(speed: uint32; start_val, end_val: sint32): uint32; cdecl; external;
procedure lv_anim_refr_now; cdecl; external;
function  lv_anim_path_linear(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_ease_in(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_ease_out(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_ease_in_out(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_overshoot(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_bounce(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_step(a: Plv_anim): sint32; cdecl; external;
function  lv_anim_path_custom_bezier3(a: Plv_anim): sint32; cdecl; external;

{ ============================================================
  Timer API (lv_timer.h)
  ============================================================ }
function  lv_timer_create_basic: Plv_timer; cdecl; external;
function  lv_timer_create(timer_cb: lv_timer_cb_t; period: uint32; user_data: pointer): Plv_timer; cdecl; external;
procedure lv_timer_delete(timer: Plv_timer); cdecl; external;
procedure lv_timer_pause(timer: Plv_timer); cdecl; external;
procedure lv_timer_resume(timer: Plv_timer); cdecl; external;
procedure lv_timer_set_cb(timer: Plv_timer; timer_cb: lv_timer_cb_t); cdecl; external;
procedure lv_timer_set_period(timer: Plv_timer; period: uint32); cdecl; external;
procedure lv_timer_ready(timer: Plv_timer); cdecl; external;
procedure lv_timer_set_repeat_count(timer: Plv_timer; repeat_count: sint32); cdecl; external;
procedure lv_timer_set_auto_delete(timer: Plv_timer; auto_delete: boolean); cdecl; external;
procedure lv_timer_set_user_data(timer: Plv_timer; user_data: pointer); cdecl; external;
procedure lv_timer_reset(timer: Plv_timer); cdecl; external;
procedure lv_timer_enable(en: boolean); cdecl; external;
function  lv_timer_get_idle: uint32; cdecl; external;
function  lv_timer_get_time_until_next: uint32; cdecl; external;
function  lv_timer_get_next(timer: Plv_timer): Plv_timer; cdecl; external;
function  lv_timer_get_user_data(timer: Plv_timer): pointer; cdecl; external;
function  lv_timer_get_paused(timer: Plv_timer): boolean; cdecl; external;

{ ============================================================
  Font API (lv_font.h) — only compiled functions
  ============================================================ }
function  lv_font_get_glyph_dsc(font: Plv_font; dsc_out: Plv_font_glyph_dsc; letter, letter_next: uint32): boolean; cdecl; external;
function  lv_font_get_glyph_width(font: Plv_font; letter, letter_next: uint32): uint16; cdecl; external;
procedure lv_font_set_kerning(font: Plv_font; kerning: uint32); cdecl; external;

{ ============================================================
  Area / Point utilities (lv_area.h) — compiled functions only
  ============================================================ }
procedure lv_area_set(area: Plv_area; x1, y1, x2, y2: sint32); cdecl; external;
procedure lv_area_increase(area: Plv_area; w_extra, h_extra: sint32); cdecl; external;
procedure lv_area_move(area: Plv_area; x_ofs, y_ofs: sint32); cdecl; external;
procedure lv_area_align(base: Plv_area; to_align: Plv_area; align: uint8; ofs_x, ofs_y: sint32); cdecl; external;
function  lv_pct(x: sint32): sint32; cdecl; external;
function  lv_pct_to_px(v, base: sint32): sint32; cdecl; external;

{ ============================================================
  Color utilities (lv_color.h) — compiled functions
  ============================================================ }
function  lv_color_hex(c: uint32): lv_color_t; cdecl; external;
function  lv_color_lighten(c: lv_color_t; lvl: uint8): lv_color_t; cdecl; external;
function  lv_color_darken(c: lv_color_t; lvl: uint8): lv_color_t; cdecl; external;
function  lv_color_hsv_to_rgb(h: uint16; s, v: uint8): lv_color_t; cdecl; external;
function  lv_color_rgb_to_hsv(r, g, b: uint8): lv_color_hsv_t; cdecl; external;
function  lv_color_to_hsv(c: lv_color_t): lv_color_hsv_t; cdecl; external;
function  lv_color_format_get_bpp(cf: uint32): uint8; cdecl; external;
function  lv_color_format_get_size(cf: uint32): uint8; cdecl; external;
function  lv_color_format_has_alpha(cf: uint32): boolean; cdecl; external;

{ Text utilities (lv_text.h) }
procedure lv_text_get_size(size_res: Plv_point; text: pchar; font: Plv_font; letter_space, line_space, max_width: sint32; flag: uint32); cdecl; external;
function  lv_text_get_width(txt: pchar; length: uint32; font: Plv_font; letter_space: sint32): sint32; cdecl; external;

{ ============================================================
  Widget — Label (lv_label.h)
  ============================================================ }
function  lv_label_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_label_set_text(lbl: Plv_obj; txt: pchar); cdecl; external;
procedure lv_label_set_text_static(lbl: Plv_obj; txt: pchar); cdecl; external;
procedure lv_label_set_long_mode(lbl: Plv_obj; long_mode: uint32); cdecl; external;
procedure lv_label_set_text_selection_start(lbl: Plv_obj; index: uint32); cdecl; external;
procedure lv_label_set_text_selection_end(lbl: Plv_obj; index: uint32); cdecl; external;
function  lv_label_get_text(lbl: Plv_obj): pchar; cdecl; external;
function  lv_label_get_long_mode(lbl: Plv_obj): uint32; cdecl; external;
procedure lv_label_get_letter_pos(lbl: Plv_obj; char_id: uint32; pos: Plv_point); cdecl; external;
function  lv_label_get_letter_on(lbl: Plv_obj; pos_in: Plv_point; bidi: boolean): uint32; cdecl; external;
function  lv_label_is_char_under_pos(lbl: Plv_obj; pos: Plv_point): boolean; cdecl; external;
function  lv_label_get_text_selection_start(lbl: Plv_obj): uint32; cdecl; external;
function  lv_label_get_text_selection_end(lbl: Plv_obj): uint32; cdecl; external;
procedure lv_label_ins_text(lbl: Plv_obj; pos: uint32; txt: pchar); cdecl; external;
procedure lv_label_cut_text(lbl: Plv_obj; pos, cnt: uint32); cdecl; external;

{ ============================================================
  Widget — Button (lv_button.h)
  ============================================================ }
function  lv_button_create(parent: Plv_obj): Plv_obj; cdecl; external;

{ ============================================================
  Widget — Image (lv_image.h)
  ============================================================ }
function  lv_image_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_image_set_src(obj: Plv_obj; src: pointer); cdecl; external;
procedure lv_image_set_offset_x(obj: Plv_obj; x: sint32); cdecl; external;
procedure lv_image_set_offset_y(obj: Plv_obj; y: sint32); cdecl; external;
procedure lv_image_set_rotation(obj: Plv_obj; angle: sint32); cdecl; external;
procedure lv_image_set_pivot(obj: Plv_obj; x, y: sint32); cdecl; external;
procedure lv_image_set_scale(obj: Plv_obj; zoom: uint32); cdecl; external;
procedure lv_image_set_scale_x(obj: Plv_obj; zoom: uint32); cdecl; external;
procedure lv_image_set_scale_y(obj: Plv_obj; zoom: uint32); cdecl; external;
procedure lv_image_set_blend_mode(obj: Plv_obj; blend_mode: uint32); cdecl; external;
procedure lv_image_set_antialias(obj: Plv_obj; antialias: boolean); cdecl; external;
procedure lv_image_set_inner_align(obj: Plv_obj; align: uint32); cdecl; external;
function  lv_image_get_src(obj: Plv_obj): pointer; cdecl; external;
function  lv_image_get_offset_x(obj: Plv_obj): sint32; cdecl; external;
function  lv_image_get_offset_y(obj: Plv_obj): sint32; cdecl; external;
function  lv_image_get_rotation(obj: Plv_obj): sint32; cdecl; external;
procedure lv_image_get_pivot(obj: Plv_obj; pivot: Plv_point); cdecl; external;
function  lv_image_get_scale(obj: Plv_obj): sint32; cdecl; external;
function  lv_image_get_scale_x(obj: Plv_obj): sint32; cdecl; external;
function  lv_image_get_scale_y(obj: Plv_obj): sint32; cdecl; external;
function  lv_image_get_blend_mode(obj: Plv_obj): uint32; cdecl; external;
function  lv_image_get_antialias(obj: Plv_obj): boolean; cdecl; external;
function  lv_image_get_inner_align(obj: Plv_obj): uint32; cdecl; external;

{ ============================================================
  Widget — Line (lv_line.h)
  ============================================================ }
function  lv_line_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_line_set_points(line: Plv_obj; points: Plv_point; point_num: uint32); cdecl; external;
procedure lv_line_set_points_mutable(line: Plv_obj; points: Plv_point; point_num: uint32); cdecl; external;
procedure lv_line_set_y_invert(line: Plv_obj; en: boolean); cdecl; external;
function  lv_line_get_points(line: Plv_obj): Plv_point; cdecl; external;
function  lv_line_get_point_count(line: Plv_obj): uint32; cdecl; external;
function  lv_line_get_y_invert(line: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Widget — Arc (lv_arc.h)
  ============================================================ }
function  lv_arc_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_arc_set_start_angle(obj: Plv_obj; start_angle: sint32); cdecl; external;
procedure lv_arc_set_end_angle(obj: Plv_obj; end_angle: sint32); cdecl; external;
procedure lv_arc_set_angles(obj: Plv_obj; start_angle, end_angle: sint32); cdecl; external;
procedure lv_arc_set_bg_start_angle(obj: Plv_obj; start_angle: sint32); cdecl; external;
procedure lv_arc_set_bg_end_angle(obj: Plv_obj; end_angle: sint32); cdecl; external;
procedure lv_arc_set_bg_angles(obj: Plv_obj; start_angle, end_angle: sint32); cdecl; external;
procedure lv_arc_set_rotation(obj: Plv_obj; rotation: sint32); cdecl; external;
procedure lv_arc_set_mode(obj: Plv_obj; mode: uint32); cdecl; external;
procedure lv_arc_set_value(obj: Plv_obj; value: sint32); cdecl; external;
procedure lv_arc_set_range(obj: Plv_obj; min_val, max_val: sint32); cdecl; external;
procedure lv_arc_set_change_rate(obj: Plv_obj; rate: uint32); cdecl; external;
procedure lv_arc_set_knob_offset(obj: Plv_obj; offset: sint32); cdecl; external;
function  lv_arc_get_angle_start(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_angle_end(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_bg_angle_start(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_bg_angle_end(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_min_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_max_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_mode(obj: Plv_obj): uint32; cdecl; external;
function  lv_arc_get_rotation(obj: Plv_obj): sint32; cdecl; external;
function  lv_arc_get_knob_offset(obj: Plv_obj): sint32; cdecl; external;
procedure lv_arc_align_obj_to_angle(obj: Plv_obj; obj_to_align: Plv_obj; r_offset: sint32); cdecl; external;
procedure lv_arc_rotate_obj_to_angle(obj: Plv_obj; obj_to_rotate: Plv_obj; r_offset: sint32); cdecl; external;

{ ============================================================
  Widget — Bar (lv_bar.h)
  ============================================================ }
function  lv_bar_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_bar_set_value(obj: Plv_obj; value: sint32; anim: uint32); cdecl; external;
procedure lv_bar_set_start_value(obj: Plv_obj; start_value: sint32; anim: uint32); cdecl; external;
procedure lv_bar_set_range(obj: Plv_obj; min_val, max_val: sint32); cdecl; external;
procedure lv_bar_set_mode(obj: Plv_obj; mode: uint32); cdecl; external;
procedure lv_bar_set_orientation(obj: Plv_obj; orientation: uint32); cdecl; external;
function  lv_bar_get_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_bar_get_start_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_bar_get_min_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_bar_get_max_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_bar_get_mode(obj: Plv_obj): uint32; cdecl; external;
function  lv_bar_get_orientation(obj: Plv_obj): uint32; cdecl; external;
function  lv_bar_is_symmetrical(obj: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Widget — Slider (lv_slider.h)
  ============================================================ }
function  lv_slider_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_slider_set_value(obj: Plv_obj; value: sint32; anim: uint32); cdecl; external;
procedure lv_slider_set_left_value(obj: Plv_obj; value: sint32; anim: uint32); cdecl; external;
procedure lv_slider_set_range(obj: Plv_obj; min_val, max_val: sint32); cdecl; external;
procedure lv_slider_set_mode(obj: Plv_obj; mode: uint32); cdecl; external;
function  lv_slider_get_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_slider_get_left_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_slider_get_min_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_slider_get_max_value(obj: Plv_obj): sint32; cdecl; external;
function  lv_slider_is_dragged(obj: Plv_obj): boolean; cdecl; external;
function  lv_slider_get_mode(obj: Plv_obj): uint32; cdecl; external;
function  lv_slider_is_symmetrical(obj: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Widget — Switch (lv_switch.h)
  ============================================================ }
function  lv_switch_create(parent: Plv_obj): Plv_obj; cdecl; external;

{ ============================================================
  Widget — Checkbox (lv_checkbox.h)
  ============================================================ }
function  lv_checkbox_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_checkbox_set_text(obj: Plv_obj; txt: pchar); cdecl; external;
procedure lv_checkbox_set_text_static(obj: Plv_obj; txt: pchar); cdecl; external;
function  lv_checkbox_get_text(obj: Plv_obj): pchar; cdecl; external;

{ ============================================================
  Widget — Dropdown (lv_dropdown.h)
  ============================================================ }
function  lv_dropdown_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_dropdown_set_text(obj: Plv_obj; txt: pchar); cdecl; external;
procedure lv_dropdown_set_options(obj: Plv_obj; options: pchar); cdecl; external;
procedure lv_dropdown_set_options_static(obj: Plv_obj; options: pchar); cdecl; external;
procedure lv_dropdown_add_option(obj: Plv_obj; option: pchar; pos: uint32); cdecl; external;
procedure lv_dropdown_clear_options(obj: Plv_obj); cdecl; external;
procedure lv_dropdown_set_selected(obj: Plv_obj; sel_opt: uint32); cdecl; external;
procedure lv_dropdown_set_dir(obj: Plv_obj; dir: uint32); cdecl; external;
procedure lv_dropdown_set_symbol(obj: Plv_obj; symbol: pointer); cdecl; external;
procedure lv_dropdown_set_selected_highlight(obj: Plv_obj; en: boolean); cdecl; external;
function  lv_dropdown_get_list(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_dropdown_get_text(obj: Plv_obj): pchar; cdecl; external;
function  lv_dropdown_get_options(obj: Plv_obj): pchar; cdecl; external;
function  lv_dropdown_get_selected(obj: Plv_obj): uint32; cdecl; external;
function  lv_dropdown_get_option_count(obj: Plv_obj): uint32; cdecl; external;
procedure lv_dropdown_get_selected_str(obj: Plv_obj; buf: pchar; buf_size: uint32); cdecl; external;
function  lv_dropdown_get_option_index(obj: Plv_obj; option: pchar): sint32; cdecl; external;
function  lv_dropdown_get_symbol(obj: Plv_obj): pchar; cdecl; external;
function  lv_dropdown_get_selected_highlight(obj: Plv_obj): boolean; cdecl; external;
function  lv_dropdown_get_dir(obj: Plv_obj): uint32; cdecl; external;
procedure lv_dropdown_open(obj: Plv_obj); cdecl; external;
procedure lv_dropdown_close(obj: Plv_obj); cdecl; external;
function  lv_dropdown_is_open(obj: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Widget — Roller (lv_roller.h)
  ============================================================ }
function  lv_roller_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_roller_set_options(obj: Plv_obj; options: pchar; mode: uint32); cdecl; external;
procedure lv_roller_set_selected(obj: Plv_obj; sel_opt: uint32; anim: uint32); cdecl; external;
procedure lv_roller_set_visible_row_count(obj: Plv_obj; row_cnt: uint32); cdecl; external;
function  lv_roller_get_selected(obj: Plv_obj): uint32; cdecl; external;
procedure lv_roller_get_selected_str(obj: Plv_obj; buf: pchar; buf_size: uint32); cdecl; external;
function  lv_roller_get_options(obj: Plv_obj): pchar; cdecl; external;
function  lv_roller_get_option_count(obj: Plv_obj): uint32; cdecl; external;

{ ============================================================
  Widget — Textarea (lv_textarea.h)
  ============================================================ }
function  lv_textarea_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_textarea_add_char(obj: Plv_obj; c: uint32); cdecl; external;
procedure lv_textarea_add_text(obj: Plv_obj; txt: pchar); cdecl; external;
procedure lv_textarea_delete_char(obj: Plv_obj); cdecl; external;
procedure lv_textarea_delete_char_forward(obj: Plv_obj); cdecl; external;
procedure lv_textarea_set_text(ta: Plv_obj; txt: pchar); cdecl; external;
procedure lv_textarea_set_placeholder_text(ta: Plv_obj; txt: pchar); cdecl; external;
procedure lv_textarea_set_cursor_pos(ta: Plv_obj; pos: sint32); cdecl; external;
procedure lv_textarea_set_cursor_click_pos(ta: Plv_obj; en: boolean); cdecl; external;
procedure lv_textarea_set_password_mode(obj: Plv_obj; en: boolean); cdecl; external;
procedure lv_textarea_set_password_bullet(obj: Plv_obj; bullet: pchar); cdecl; external;
procedure lv_textarea_set_one_line(ta: Plv_obj; en: boolean); cdecl; external;
procedure lv_textarea_set_accepted_chars(obj: Plv_obj; list: pchar); cdecl; external;
procedure lv_textarea_set_max_length(obj: Plv_obj; num: uint32); cdecl; external;
procedure lv_textarea_set_insert_replace(obj: Plv_obj; txt: pchar); cdecl; external;
procedure lv_textarea_set_text_selection(obj: Plv_obj; en: boolean); cdecl; external;
procedure lv_textarea_set_password_show_time(obj: Plv_obj; time: uint32); cdecl; external;
procedure lv_textarea_set_align(obj: Plv_obj; align: uint8); cdecl; external;
function  lv_textarea_get_text(ta: Plv_obj): pchar; cdecl; external;
function  lv_textarea_get_placeholder_text(obj: Plv_obj): pchar; cdecl; external;
function  lv_textarea_get_label(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_textarea_get_cursor_pos(obj: Plv_obj): uint32; cdecl; external;
function  lv_textarea_get_cursor_click_pos(obj: Plv_obj): boolean; cdecl; external;
function  lv_textarea_get_password_mode(obj: Plv_obj): boolean; cdecl; external;
function  lv_textarea_get_password_bullet(obj: Plv_obj): pchar; cdecl; external;
function  lv_textarea_get_one_line(obj: Plv_obj): boolean; cdecl; external;
function  lv_textarea_get_accepted_chars(obj: Plv_obj): pchar; cdecl; external;
function  lv_textarea_get_max_length(obj: Plv_obj): uint32; cdecl; external;
function  lv_textarea_text_is_selected(obj: Plv_obj): boolean; cdecl; external;
function  lv_textarea_get_text_selection(obj: Plv_obj): boolean; cdecl; external;
function  lv_textarea_get_password_show_time(obj: Plv_obj): uint32; cdecl; external;
function  lv_textarea_get_current_char(obj: Plv_obj): uint32; cdecl; external;
procedure lv_textarea_clear_selection(obj: Plv_obj); cdecl; external;
procedure lv_textarea_cursor_right(obj: Plv_obj); cdecl; external;
procedure lv_textarea_cursor_left(obj: Plv_obj); cdecl; external;
procedure lv_textarea_cursor_down(obj: Plv_obj); cdecl; external;
procedure lv_textarea_cursor_up(obj: Plv_obj); cdecl; external;

{ ============================================================
  Widget — Table (lv_table.h)
  ============================================================ }
function  lv_table_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_table_set_cell_value(obj: Plv_obj; row, col: uint32; txt: pchar); cdecl; external;
procedure lv_table_set_row_count(obj: Plv_obj; row_cnt: uint32); cdecl; external;
procedure lv_table_set_column_count(obj: Plv_obj; col_cnt: uint32); cdecl; external;
procedure lv_table_set_column_width(obj: Plv_obj; col_id: uint32; w: sint32); cdecl; external;
procedure lv_table_add_cell_ctrl(obj: Plv_obj; row, col: uint32; ctrl: uint32); cdecl; external;
procedure lv_table_clear_cell_ctrl(obj: Plv_obj; row, col: uint32; ctrl: uint32); cdecl; external;
procedure lv_table_set_cell_user_data(obj: Plv_obj; row, col: uint16; user_data: pointer); cdecl; external;
procedure lv_table_set_selected_cell(obj: Plv_obj; row, col: uint16); cdecl; external;
function  lv_table_get_cell_value(obj: Plv_obj; row, col: uint32): pchar; cdecl; external;
function  lv_table_get_row_count(obj: Plv_obj): uint32; cdecl; external;
function  lv_table_get_column_count(obj: Plv_obj): uint32; cdecl; external;
function  lv_table_get_column_width(obj: Plv_obj; col: uint32): sint32; cdecl; external;
function  lv_table_has_cell_ctrl(obj: Plv_obj; row, col: uint32; ctrl: uint32): boolean; cdecl; external;
procedure lv_table_get_selected_cell(obj: Plv_obj; row: pointer; col: pointer); cdecl; external;
function  lv_table_get_cell_user_data(obj: Plv_obj; row, col: uint16): pointer; cdecl; external;

{ ============================================================
  Widget — Button Matrix (lv_buttonmatrix.h)
  ============================================================ }
function  lv_buttonmatrix_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_buttonmatrix_set_map(obj: Plv_obj; map: pointer); cdecl; external;
procedure lv_buttonmatrix_set_ctrl_map(obj: Plv_obj; ctrl_map: pointer); cdecl; external;
procedure lv_buttonmatrix_set_selected_button(obj: Plv_obj; btn_id: uint32); cdecl; external;
procedure lv_buttonmatrix_set_button_ctrl(obj: Plv_obj; btn_id: uint32; ctrl: uint16); cdecl; external;
procedure lv_buttonmatrix_clear_button_ctrl(obj: Plv_obj; btn_id: uint32; ctrl: uint16); cdecl; external;
procedure lv_buttonmatrix_set_button_ctrl_all(obj: Plv_obj; ctrl: uint16); cdecl; external;
procedure lv_buttonmatrix_clear_button_ctrl_all(obj: Plv_obj; ctrl: uint16); cdecl; external;
procedure lv_buttonmatrix_set_button_width(obj: Plv_obj; btn_id: uint32; width: uint32); cdecl; external;
procedure lv_buttonmatrix_set_one_checked(obj: Plv_obj; en: boolean); cdecl; external;
function  lv_buttonmatrix_get_map(obj: Plv_obj): pointer; cdecl; external;
function  lv_buttonmatrix_get_selected_button(obj: Plv_obj): uint32; cdecl; external;
function  lv_buttonmatrix_get_button_text(obj: Plv_obj; btn_id: uint32): pchar; cdecl; external;
function  lv_buttonmatrix_has_button_ctrl(obj: Plv_obj; btn_id: uint32; ctrl: uint16): boolean; cdecl; external;
function  lv_buttonmatrix_get_one_checked(obj: Plv_obj): boolean; cdecl; external;

{ ============================================================
  Widget — Keyboard (lv_keyboard.h)
  ============================================================ }
function  lv_keyboard_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_keyboard_set_textarea(kb: Plv_obj; ta: Plv_obj); cdecl; external;
procedure lv_keyboard_set_mode(kb: Plv_obj; mode: uint32); cdecl; external;
procedure lv_keyboard_set_popovers(kb: Plv_obj; en: boolean); cdecl; external;
procedure lv_keyboard_set_map(kb: Plv_obj; mode: uint32; map: pointer; ctrl_map: pointer); cdecl; external;
function  lv_keyboard_get_textarea(kb: Plv_obj): Plv_obj; cdecl; external;
function  lv_keyboard_get_mode(kb: Plv_obj): uint32; cdecl; external;
function  lv_keyboard_get_popovers(kb: Plv_obj): boolean; cdecl; external;
function  lv_keyboard_get_map_array(kb: Plv_obj): pointer; cdecl; external;
function  lv_keyboard_get_selected_button(kb: Plv_obj): uint32; cdecl; external;
function  lv_keyboard_get_button_text(kb: Plv_obj; btn_id: uint32): pchar; cdecl; external;

{ ============================================================
  Widget — List (lv_list.h)
  ============================================================ }
function  lv_list_create(parent: Plv_obj): Plv_obj; cdecl; external;
function  lv_list_add_text(list: Plv_obj; txt: pchar): Plv_obj; cdecl; external;
function  lv_list_add_button(list: Plv_obj; icon: pointer; txt: pchar): Plv_obj; cdecl; external;
function  lv_list_get_button_text(list: Plv_obj; btn: Plv_obj): pchar; cdecl; external;
procedure lv_list_set_button_text(list: Plv_obj; btn: Plv_obj; txt: pchar); cdecl; external;

{ ============================================================
  Widget — Message Box (lv_msgbox.h)
  ============================================================ }
function  lv_msgbox_create(parent: Plv_obj): Plv_obj; cdecl; external;
function  lv_msgbox_add_title(obj: Plv_obj; title: pchar): Plv_obj; cdecl; external;
function  lv_msgbox_add_header_button(obj: Plv_obj; icon: pointer): Plv_obj; cdecl; external;
function  lv_msgbox_add_text(obj: Plv_obj; text: pchar): Plv_obj; cdecl; external;
function  lv_msgbox_add_footer_button(obj: Plv_obj; text: pchar): Plv_obj; cdecl; external;
function  lv_msgbox_add_close_button(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_msgbox_get_header(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_msgbox_get_footer(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_msgbox_get_content(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_msgbox_get_title(obj: Plv_obj): Plv_obj; cdecl; external;
procedure lv_msgbox_close(mbox: Plv_obj); cdecl; external;
procedure lv_msgbox_close_async(mbox: Plv_obj); cdecl; external;

{ ============================================================
  Widget — Spinner (lv_spinner.h)
  ============================================================ }
function  lv_spinner_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_spinner_set_anim_params(obj: Plv_obj; t, angle: uint32); cdecl; external;

{ ============================================================
  Widget — Tabview (lv_tabview.h)
  ============================================================ }
function  lv_tabview_create(parent: Plv_obj): Plv_obj; cdecl; external;
function  lv_tabview_add_tab(obj: Plv_obj; name: pchar): Plv_obj; cdecl; external;
procedure lv_tabview_rename_tab(obj: Plv_obj; idx: uint32; new_name: pchar); cdecl; external;
procedure lv_tabview_set_active(obj: Plv_obj; idx: uint32; anim_en: uint32); cdecl; external;
procedure lv_tabview_set_tab_bar_position(obj: Plv_obj; dir: uint32); cdecl; external;
procedure lv_tabview_set_tab_bar_size(obj: Plv_obj; size: sint32); cdecl; external;
function  lv_tabview_get_tab_count(obj: Plv_obj): uint32; cdecl; external;
function  lv_tabview_get_tab_active(obj: Plv_obj): uint32; cdecl; external;
function  lv_tabview_get_content(obj: Plv_obj): Plv_obj; cdecl; external;
function  lv_tabview_get_tab_bar(obj: Plv_obj): Plv_obj; cdecl; external;

{ ============================================================
  Widget — Window (lv_win.h)
  ============================================================ }
function  lv_win_create(parent: Plv_obj): Plv_obj; cdecl; external;
function  lv_win_add_title(win: Plv_obj; txt: pchar): Plv_obj; cdecl; external;
function  lv_win_add_button(win: Plv_obj; icon: pointer; btn_w: sint32): Plv_obj; cdecl; external;
function  lv_win_get_header(win: Plv_obj): Plv_obj; cdecl; external;
function  lv_win_get_content(win: Plv_obj): Plv_obj; cdecl; external;

{ ============================================================
  Widget — Animated Image (lv_animimage.h)
  ============================================================ }
function  lv_animimg_create(parent: Plv_obj): Plv_obj; cdecl; external;
procedure lv_animimg_set_src(img: Plv_obj; dsc: pointer; num: uint32); cdecl; external;
procedure lv_animimg_start(obj: Plv_obj); cdecl; external;
procedure lv_animimg_set_duration(img: Plv_obj; duration: uint32); cdecl; external;
procedure lv_animimg_set_repeat_count(img: Plv_obj; count: uint32); cdecl; external;
function  lv_animimg_get_src(img: Plv_obj): pointer; cdecl; external;
function  lv_animimg_get_src_count(img: Plv_obj): uint8; cdecl; external;
function  lv_animimg_get_duration(img: Plv_obj): uint32; cdecl; external;
function  lv_animimg_get_repeat_count(img: Plv_obj): uint32; cdecl; external;

{ ============================================================
  High-level API for core.version
  ============================================================ }
procedure lvgl_init(screen_w, screen_h: uint32);
function  lvgl_handler: uint32;
function  lvgl_get_display: Plv_display;
procedure lvgl_set_mouse_cursor(cursor: Plv_obj);
function  lvgl_get_ticks: uint32;
function  lvgl_get_kb_group: Plv_group;
procedure lvgl_update_resolution(screen_w, screen_h: uint32);

{ Color helper (Pascal wrapper for inline C function) }
function lv_color_make(r, g, b: uint8): lv_color_t;

{ ============================================================
  IMPLEMENTATION
  ============================================================ }
implementation

uses
    app.uidebug;

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

procedure lv_obj_set_style_pad_gap(obj: Plv_obj; gap: sint32; selector: uint32);
begin
    lv_obj_set_style_pad_row(obj, gap, selector);
    lv_obj_set_style_pad_column(obj, gap, selector);
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

    { Keyboard ring buffer for LVGL }
    kb_buf      : array[0..15] of uint32;
    kb_head     : uint32;  { next write slot (hook side) }
    kb_tail     : uint32;  { next read slot (LVGL poll side) }
    kb_current_key : uint32;   { key currently reported as pressed to LVGL, 0 = none }
    kb_key_held    : boolean;  { true while physical key is down }
    kb_held_code   : uint32;   { the LVGL key code of the held key }

const
    KB_BUF_SIZE = 16;
    { LVGL render buffer: 1/10th of screen }
    LV_BUF_LINES = 120;

var
    lv_buf1: pointer;
    lv_buf1_size: uint32;

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
  Flush callback — copies LVGL render buffer to driver.video back buffer
  Handles 32bpp (direct copy) and 16bpp (ARGB8888 -> RGB565).
  ============================================================ }
procedure lvgl_flush_cb(disp: Plv_display; area: Plv_area; color_p: Plv_color); cdecl;
var
    y, x, area_w: sint32;
    src: puint32;
    dst32: puint32;
    dst16: puint16;
    fb_w: uint32;
    bpp: uint8;
    pixel: uint32;
    r, g, b: uint8;
begin
    fb_w := driver.video.backBufferWidth;
    bpp := driver.video.backBufferBpp;
    area_w := (area^.x2 - area^.x1) + 1;
    src := puint32(color_p);

    if bpp >= 32 then begin
        { 32bpp: direct copy, 4 bytes per pixel }
        for y := area^.y1 to area^.y2 do begin
            dst32 := puint32(driver.video.backBufferLocation + uint32((y * sint32(fb_w) + area^.x1) * 4));
            for x := 0 to area_w - 1 do begin
                dst32[x] := src[x];
            end;
            src := puint32(uint32(src) + uint32(area_w * 4));
        end;
    end else if bpp = 16 then begin
        { 16bpp: convert ARGB8888 -> RGB565, 2 bytes per pixel }
        for y := area^.y1 to area^.y2 do begin
            dst16 := puint16(driver.video.backBufferLocation + uint32((y * sint32(fb_w) + area^.x1) * 2));
            for x := 0 to area_w - 1 do begin
                pixel := src[x];
                b := pixel and $FF;
                g := (pixel shr 8) and $FF;
                r := (pixel shr 16) and $FF;
                dst16[x] := uint16(((uint16(r) shr 3) shl 11) or ((uint16(g) shr 2) shl 5) or (uint16(b) shr 3));
            end;
            src := puint32(uint32(src) + uint32(area_w * 4));
        end;
    end;

    lv_display_flush_ready(disp);
end;

{ ============================================================
  Log callback — route LVGL logs to driver.io.serial
  ============================================================ }
procedure lvgl_log_cb(level: sint32; buf: pchar); cdecl;
begin
    driver.io.serial.sendString('[LVGL] ');
    driver.io.serial.sendString(buf);
end;

{ ============================================================
  Mouse read callback — LVGL polls this for pointer state
  ============================================================ }
procedure lvgl_mouse_read_cb(indev: Plv_indev; data: Plv_indev_data); cdecl;
begin
    data^.point.x := driver.hid.mouse.getMouseX;
    data^.point.y := driver.hid.mouse.getMouseY;
    if driver.hid.mouse.getMouseLMB then
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
    if (kb_current_key <> 0) and
       ((not kb_key_held) or (kb_held_code <> kb_current_key) or (kb_tail <> kb_head)) then begin
        { Release current key: physical key released, different key now held, or new keys queued }
        data^.key   := kb_current_key;
        data^.state := LV_INDEV_STATE_RELEASED;
        kb_current_key := 0;
        data^.continue_reading := (kb_tail <> kb_head);
    end else if kb_tail <> kb_head then begin
        { Consume next key from ring buffer — press }
        kb_current_key := kb_buf[kb_tail];
        kb_tail := (kb_tail + 1) mod KB_BUF_SIZE;
        data^.key   := kb_current_key;
        data^.state := LV_INDEV_STATE_PRESSED;
        data^.continue_reading := false; { one press per timer cycle for proper long-press timing }
    end else if (kb_current_key <> 0) and kb_key_held then begin
        { Key still physically held — keep reporting pressed for LVGL long-press repeat }
        data^.key   := kb_current_key;
        data^.state := LV_INDEV_STATE_PRESSED;
        data^.continue_reading := false;
    end else begin
        { Idle — no keys }
        data^.key   := 0;
        data^.state := LV_INDEV_STATE_RELEASED;
        data^.continue_reading := false;
    end;
end;

{ ============================================================
  Keyboard hook — receives keypresses from Asuro driver.hid.keyboard driver
  ============================================================ }
procedure lvgl_keyboard_hook(key_info: TKeyInfo);
var
    k: uint32;
    next_head: uint32;
begin
    { Ctrl+D toggles debug overlay (press only) }
    if key_info.is_down_code and key_info.CTRL_DOWN and (key_info.key_code = ord('d')) then begin
        app.uidebug.toggle;
        exit;
    end;

    { Ctrl+C — inject custom key code so focused terminal can handle it }
    if key_info.is_down_code and key_info.CTRL_DOWN and (key_info.key_code = ord('c')) then begin
        next_head := (kb_head + 1) mod KB_BUF_SIZE;
        if next_head <> kb_tail then begin
            kb_buf[kb_head] := LV_KEY_CTRLC;
            kb_head := next_head;
        end;
        exit;
    end;

    { Map Asuro key codes to LVGL key codes }
    case key_info.key_code of
        $1B: k := LV_KEY_ESC;
        $08: k := LV_KEY_BACKSPACE;
        $0D: k := LV_KEY_ENTER;
        $09: k := LV_KEY_NEXT;
        $10: k := LV_KEY_UP;
        $12: k := LV_KEY_DOWN;
        $13: k := LV_KEY_LEFT;
        $14: k := LV_KEY_RIGHT;
        else k := uint32(key_info.key_code);
    end;

    if key_info.is_down_code then begin
        { Key press — push into ring buffer and track held state }
        next_head := (kb_head + 1) mod KB_BUF_SIZE;
        if next_head <> kb_tail then begin
            kb_buf[kb_head] := k;
            kb_head := next_head;
        end;
        kb_key_held := true;
        kb_held_code := k;
    end else begin
        { Key release — clear held state if it matches }
        if kb_key_held and (kb_held_code = k) then
            kb_key_held := false;
    end;
end;

{ ============================================================
  1024Hz timer tick — called from arch.x86.isr.tmr0 (~1ms per tick)
  ============================================================ }
procedure lvgl_timer_tick(data: void);
begin
    tick_accumulator := tick_accumulator + 1;
end;

{ ============================================================
  GPU mode-change callback — updates LVGL display resolution
  ============================================================ }
procedure lvglModeChanged(const info : TGPUModeInfo);
begin
    lvgl_update_resolution(info.Width, info.Height);
end;

{ ============================================================
  High-level init
  ============================================================ }
procedure lvgl_init(screen_w, screen_h: uint32);
begin
    debug.tracer.push_trace('driver.video.lvgl.init.enter');

    tick_accumulator := 0;
    kb_head := 0;
    kb_tail := 0;
    kb_current_key := 0;
    kb_key_held := false;
    kb_held_code := 0;

    { Initialize LVGL core }
    lv_init;

    { Register log callback }
    lv_log_register_print_cb(@lvgl_log_cb);

    { Allocate LVGL render buffer dynamically (1/10th of screen) }
    lv_buf1_size := screen_w * LV_BUF_LINES * SizeOf(lv_color_t);
    lv_buf1 := pointer(kalloc(lv_buf1_size));

    { Create display }
    disp := lv_display_create(sint32(screen_w), sint32(screen_h));
    lv_display_set_flush_cb(disp, @lvgl_flush_cb);
    lv_display_set_buffers(disp, lv_buf1, nil,
        lv_buf1_size, LV_DISPLAY_RENDER_MODE_PARTIAL);

    { Create driver.hid.mouse input device with read callback }
    mouse_indev := lv_indev_create;
    lv_indev_set_type(mouse_indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(mouse_indev, @lvgl_mouse_read_cb);

    { Create driver.hid.keyboard input device with read callback }
    kb_indev := lv_indev_create;
    lv_indev_set_type(kb_indev, LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(kb_indev, @lvgl_kb_read_cb);
    kb_group := lv_group_create;
    lv_group_set_default(kb_group);
    lv_indev_set_group(kb_indev, kb_group);

    { Disable drag-to-scroll on driver.hid.mouse (driver.video.desktop style: scroll wheel only) }
    lv_indev_set_scroll_limit(mouse_indev, 255);
    lv_indev_set_scroll_throw(mouse_indev, 0);

    { Hook driver.hid.keyboard driver for key events }
    driver.hid.keyboard.hook(@lvgl_keyboard_hook);

    { Hook 1024Hz timer for accurate LVGL tick }
    arch.x86.isr.tmr0.hook(uint32(@lvgl_timer_tick));

    { Register for GPU mode-change notifications so LVGL resolution updates automatically }
    driver.video.gpu.registerModeChangeCallback(@lvglModeChanged);

    debug.tracer.push_trace('driver.video.lvgl.init.exit');
end;

procedure lvgl_update_resolution(screen_w, screen_h: uint32);
var
    new_buf : pointer;
    new_size : uint32;

begin
    debug.tracer.push_trace('driver.video.lvgl.update_resolution.enter');

    { Allocate new render buffer for the new width }
    new_size := screen_w * LV_BUF_LINES * SizeOf(lv_color_t);
    new_buf := pointer(kalloc(new_size));

    if new_buf <> nil then begin
        { Free old render buffer }
        if lv_buf1 <> nil then
            kfree(lv_buf1);

        lv_buf1 := new_buf;
        lv_buf1_size := new_size;

        { Update LVGL display resolution and buffers }
        lv_display_set_resolution(disp, sint32(screen_w), sint32(screen_h));
        lv_display_set_buffers(disp, lv_buf1, nil,
            lv_buf1_size, LV_DISPLAY_RENDER_MODE_PARTIAL);

        io.syslog.logln('LVGL', 'Resolution updated successfully.');
    end else begin
        io.syslog.logln('LVGL', 'Failed to allocate new render buffer.');
    end;

    debug.tracer.push_trace('driver.video.lvgl.update_resolution.exit');
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
    scroll_delta := driver.hid.mouse.getMouseScroll;
    if scroll_delta <> 0 then begin
        mx := driver.hid.mouse.getMouseX;
        my := driver.hid.mouse.getMouseY;
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
