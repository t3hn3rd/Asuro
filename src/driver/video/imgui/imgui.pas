{ 
    Driver->Video->Imgui->Imgui
    Pascal wrapper for Dear ImGui via cimgui.
    Provides:
      - External declarations for all cimgui C functions
      - Pascal allocator bridge (imgui_c_alloc / imgui_c_free) called by crtshim
      - Font texture storage callback (imgui_pascal_set_font_texture)
      - Software triangle rasterizer (imgui_pascal_render_triangle)
      - Input helpers (keyboard + mouse feeds for ImGuiIO)
      - High-level init / new_frame / render / shutdown API

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit imgui;

interface

uses
    imguitypes,
    video,
    color,
    lmemorymanager,
    console,
    tracer;

{ ============================================================
  Init / shutdown / frame
  ============================================================ }
procedure imgui_init(display_w, display_h: uint32);
procedure imgui_shutdown;
procedure imgui_new_frame;
procedure imgui_render;

{ ============================================================
  Input feed  (call from your keyboard / mouse hooks each frame)
  ============================================================ }
procedure imgui_feed_mouse_pos   (x, y: single);
procedure imgui_feed_mouse_button(button: sint32; down: boolean);
procedure imgui_feed_mouse_wheel (dy: single);
procedure imgui_feed_key         (imgui_key: sint32; down: boolean);
procedure imgui_feed_char        (codepoint: uint32);
procedure imgui_feed_delta_time  (dt: single);
procedure imgui_process_input;

{ ============================================================
  Context
  ============================================================ }
function  igCreateContext           (shared_font_atlas: PImFontAtlas): PImGuiContext; cdecl; external;
procedure igDestroyContext          (ctx: PImGuiContext); cdecl; external;
function  igGetCurrentContext       : PImGuiContext; cdecl; external;
procedure igSetCurrentContext       (ctx: PImGuiContext); cdecl; external;

{ ============================================================
  IO / style
  ============================================================ }
function  igGetIO_Nil               : PImGuiIO;    cdecl; external;
function  igGetStyle                : PImGuiStyle; cdecl; external;
procedure igStyleColorsDark         (dst: PImGuiStyle); cdecl; external;
procedure igStyleColorsLight        (dst: PImGuiStyle); cdecl; external;
procedure igStyleColorsClassic      (dst: PImGuiStyle); cdecl; external;
procedure ImGuiIO_AddInputCharacter (self: PImGuiIO; c: uint32); cdecl; external;
procedure ImGuiIO_AddKeyEvent       (self: PImGuiIO; key: ImGuiKeyType; down: boolean); cdecl; external;
procedure ImGuiIO_AddMousePosEvent  (self: PImGuiIO; x, y: single); cdecl; external;
procedure ImGuiIO_AddMouseButtonEvent(self: PImGuiIO; button: sint32; down: boolean); cdecl; external;
procedure ImGuiIO_AddMouseWheelEvent(self: PImGuiIO; delta_x, delta_y: single); cdecl; external;

{ ============================================================
  Frame lifecycle
  ============================================================ }
procedure igNewFrame                ; cdecl; external;
procedure igRender                  ; cdecl; external;
procedure igEndFrame                ; cdecl; external;
function  igGetDrawData             : PImDrawData; cdecl; external;

{ ============================================================
  Demo / metrics
  ============================================================ }
procedure igShowDemoWindow          (p_open: PBoolean); cdecl; external;
procedure igShowMetricsWindow       (p_open: PBoolean); cdecl; external;
procedure igShowStyleEditor         (ref: PImGuiStyle);  cdecl; external;
procedure igShowAboutWindow         (p_open: PBoolean); cdecl; external;
function  igShowStyleSelector       (lbl: pchar): boolean; cdecl; external;
procedure igShowFontSelector        (lbl: pchar); cdecl; external;
procedure igShowUserGuide           ; cdecl; external;
function  igGetVersion              : pchar; cdecl; external;

{ ============================================================
  Windows
  ============================================================ }
function  igBegin                   (name: pchar; p_open: PBoolean; flags: ImGuiWindowFlags): boolean; cdecl; external;
procedure igEnd                     ; cdecl; external;
function  igBeginChild_Str          (str_id: pchar; size: TImVec2; child_flags: ImGuiChildFlags; window_flags: ImGuiWindowFlags): boolean; cdecl; external;
function  igBeginChild_ID           (id: ImGuiID; size: TImVec2; child_flags: ImGuiChildFlags; window_flags: ImGuiWindowFlags): boolean; cdecl; external;
procedure igEndChild                ; cdecl; external;
function  igIsWindowAppearing       : boolean; cdecl; external;
function  igIsWindowCollapsed       : boolean; cdecl; external;
function  igIsWindowFocused         (flags: ImGuiFocusedFlags): boolean; cdecl; external;
function  igIsWindowHovered         (flags: ImGuiHoveredFlags): boolean; cdecl; external;
function  igGetWindowDrawList       : PImDrawList; cdecl; external;
function  igGetWindowDpiScale       : single; cdecl; external;
function  igGetWindowPos            : TImVec2; cdecl; external;
function  igGetWindowSize           : TImVec2; cdecl; external;
function  igGetWindowWidth          : single; cdecl; external;
function  igGetWindowHeight         : single; cdecl; external;
function  igGetScrollX              : single; cdecl; external;
function  igGetScrollY              : single; cdecl; external;
procedure igSetScrollX_Float        (scroll_x: single); cdecl; external;
procedure igSetScrollY_Float        (scroll_y: single); cdecl; external;
function  igGetScrollMaxX           : single; cdecl; external;
function  igGetScrollMaxY           : single; cdecl; external;
procedure igSetScrollHereX          (center_x_ratio: single); cdecl; external;
procedure igSetScrollHereY          (center_y_ratio: single); cdecl; external;
procedure igSetScrollFromPosX_Float (local_x: single; center_x_ratio: single); cdecl; external;
procedure igSetScrollFromPosY_Float (local_y: single; center_y_ratio: single); cdecl; external;

{ ============================================================
  Window setup (must call before Begin)
  ============================================================ }
procedure igSetNextWindowPos        (pos: TImVec2; cond: ImGuiCond_t; pivot: TImVec2); cdecl; external;
procedure igSetNextWindowSize       (size: TImVec2; cond: ImGuiCond_t); cdecl; external;
procedure igSetNextWindowSizeConstraints(size_min, size_max: TImVec2; custom_callback: ImGuiSizeCallback; custom_callback_data: pointer); cdecl; external;
procedure igSetNextWindowContentSize(size: TImVec2); cdecl; external;
procedure igSetNextWindowCollapsed  (collapsed: boolean; cond: ImGuiCond_t); cdecl; external;
procedure igSetNextWindowFocus      ; cdecl; external;
procedure igSetNextWindowScroll     (scroll: TImVec2); cdecl; external;
procedure igSetNextWindowBgAlpha    (alpha: single); cdecl; external;
procedure igSetWindowPos_Str        (name: pchar; pos: TImVec2; cond: ImGuiCond_t); cdecl; external;
procedure igSetWindowSize_Str       (name: pchar; size: TImVec2; cond: ImGuiCond_t); cdecl; external;
procedure igSetWindowCollapsed_Str  (name: pchar; collapsed: boolean; cond: ImGuiCond_t); cdecl; external;
procedure igSetWindowFocus_Str      (name: pchar); cdecl; external;
procedure igSetWindowFontScale      (scale: single); cdecl; external;

{ ============================================================
  Layout helpers
  ============================================================ }
procedure igPushItemWidth           (item_width: single); cdecl; external;
procedure igPopItemWidth            ; cdecl; external;
procedure igSetNextItemWidth        (item_width: single); cdecl; external;
function  igCalcItemWidth           : single; cdecl; external;
procedure igPushTextWrapPos         (wrap_local_pos_x: single); cdecl; external;
procedure igPopTextWrapPos          ; cdecl; external;
procedure igSameLine                (offset_from_start_x: single; spacing: single); cdecl; external;
procedure igNewLine                 ; cdecl; external;
procedure igSpacing                 ; cdecl; external;
procedure igDummy                   (size: TImVec2); cdecl; external;
procedure igIndent                  (indent_w: single); cdecl; external;
procedure igUnindent                (indent_w: single); cdecl; external;
procedure igBeginGroup              ; cdecl; external;
procedure igEndGroup                ; cdecl; external;
function  igGetCursorPos            : TImVec2; cdecl; external;
function  igGetCursorPosX           : single; cdecl; external;
function  igGetCursorPosY           : single; cdecl; external;
procedure igSetCursorPos            (local_pos: TImVec2); cdecl; external;
procedure igSetCursorPosX           (local_x: single); cdecl; external;
procedure igSetCursorPosY           (local_y: single); cdecl; external;
function  igGetCursorStartPos       : TImVec2; cdecl; external;
function  igGetCursorScreenPos      : TImVec2; cdecl; external;
procedure igSetCursorScreenPos      (pos: TImVec2); cdecl; external;
procedure igAlignTextToFramePadding ; cdecl; external;
function  igGetTextLineHeight       : single; cdecl; external;
function  igGetTextLineHeightWithSpacing: single; cdecl; external;
function  igGetFrameHeight          : single; cdecl; external;
function  igGetFrameHeightWithSpacing: single; cdecl; external;

{ ============================================================
  IDs
  ============================================================ }
procedure igPushID_Str              (str_id: pchar); cdecl; external;
procedure igPushID_StrStr           (str_id_begin: pchar; str_id_end: pchar); cdecl; external;
procedure igPushID_Ptr              (ptr_id: pointer); cdecl; external;
procedure igPushID_Int              (int_id: sint32); cdecl; external;
procedure igPopID                   ; cdecl; external;
function  igGetID_Str               (str_id: pchar): ImGuiID; cdecl; external;
function  igGetID_StrStr            (str_id_begin, str_id_end: pchar): ImGuiID; cdecl; external;
function  igGetID_Ptr               (ptr_id: pointer): ImGuiID; cdecl; external;
function  igGetID_Int               (int_id: sint32): ImGuiID; cdecl; external;

{ ============================================================
  Widgets: Text
  ============================================================ }
procedure igTextUnformatted         (text: pchar; text_end: pchar); cdecl; external;
procedure igText                    (fmt: pchar); cdecl; external;
procedure igTextColored             (col: TImVec4; fmt: pchar); cdecl; external;
procedure igTextDisabled            (fmt: pchar); cdecl; external;
procedure igTextWrapped             (fmt: pchar); cdecl; external;
procedure igLabelText               (lbl: pchar; fmt: pchar); cdecl; external;
procedure igBulletText              (fmt: pchar); cdecl; external;
procedure igSeparatorText           (lbl: pchar); cdecl; external;

{ ============================================================
  Widgets: Main buttons
  ============================================================ }
function  igButton                  (lbl: pchar; size: TImVec2): boolean; cdecl; external;
function  igSmallButton             (lbl: pchar): boolean; cdecl; external;
function  igInvisibleButton         (str_id: pchar; size: TImVec2; flags: sint32): boolean; cdecl; external;
function  igArrowButton             (str_id: pchar; dir: ImGuiDir_t): boolean; cdecl; external;
procedure igImage                   (tex_ref: TImTextureRef; image_size: TImVec2; uv0: TImVec2; uv1: TImVec2); cdecl; external;
function  igImageButton             (str_id: pchar; tex_ref: TImTextureRef; image_size: TImVec2; uv0: TImVec2; uv1: TImVec2; bg_col: TImVec4; tint_col: TImVec4): boolean; cdecl; external;
function  igCheckbox                (lbl: pchar; v: PBoolean): boolean; cdecl; external;
function  igCheckboxFlags_IntPtr    (lbl: pchar; flags: psint32; flags_value: sint32): boolean; cdecl; external;
function  igRadioButton_Bool        (lbl: pchar; active: boolean): boolean; cdecl; external;
function  igRadioButton_IntPtr      (lbl: pchar; v: psint32; v_button: sint32): boolean; cdecl; external;
procedure igProgressBar             (fraction: single; size_arg: TImVec2; overlay: pchar); cdecl; external;
procedure igBullet                  ; cdecl; external;
function  igTextLink                (lbl: pchar): boolean; cdecl; external;

{ ============================================================
  Widgets: Combo box
  ============================================================ }
function  igBeginCombo              (lbl: pchar; preview_value: pchar; flags: ImGuiComboFlags): boolean; cdecl; external;
procedure igEndCombo                ; cdecl; external;
function  igCombo_Str_arr           (lbl: pchar; current_item: psint32; items: ppchar; items_count: sint32; popup_max_height_in_items: sint32): boolean; cdecl; external;
function  igCombo_Str               (lbl: pchar; current_item: psint32; items_separated_by_zeros: pchar; popup_max_height_in_items: sint32): boolean; cdecl; external;
function  igCombo_FnBoolPtr         (lbl: pchar; current_item: psint32; getter: pointer; user_data: pointer; items_count: sint32; popup_max_height_in_items: sint32): boolean; cdecl; external;

{ ============================================================
  Widgets: Drag sliders
  ============================================================ }
function  igDragFloat               (lbl: pchar; v: PSingle; v_speed: single; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragFloat2              (lbl: pchar; v: PSingle; v_speed: single; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragFloat3              (lbl: pchar; v: PSingle; v_speed: single; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragFloat4              (lbl: pchar; v: PSingle; v_speed: single; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragFloatRange2         (lbl: pchar; v_current_min, v_current_max: PSingle; v_speed: single; v_min, v_max: single; format: pchar; format_max: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragInt                 (lbl: pchar; v: psint32; v_speed: single; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragInt2                (lbl: pchar; v: psint32; v_speed: single; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragInt3                (lbl: pchar; v: psint32; v_speed: single; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragInt4                (lbl: pchar; v: psint32; v_speed: single; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragIntRange2           (lbl: pchar; v_current_min, v_current_max: psint32; v_speed: single; v_min, v_max: sint32; format: pchar; format_max: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igDragScalar              (lbl: pchar; data_type: ImGuiDataType_t; p_data: pointer; v_speed: single; p_min, p_max: pointer; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;

{ ============================================================
  Widgets: Regular sliders
  ============================================================ }
function  igSliderFloat             (lbl: pchar; v: PSingle; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderFloat2            (lbl: pchar; v: PSingle; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderFloat3            (lbl: pchar; v: PSingle; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderFloat4            (lbl: pchar; v: PSingle; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderAngle             (lbl: pchar; v_rad: PSingle; v_degrees_min, v_degrees_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderInt               (lbl: pchar; v: psint32; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderInt2              (lbl: pchar; v: psint32; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderInt3              (lbl: pchar; v: psint32; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderInt4              (lbl: pchar; v: psint32; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igSliderScalar            (lbl: pchar; data_type: ImGuiDataType_t; p_data: pointer; p_min, p_max: pointer; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igVSliderFloat            (lbl: pchar; size: TImVec2; v: PSingle; v_min, v_max: single; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;
function  igVSliderInt              (lbl: pchar; size: TImVec2; v: psint32; v_min, v_max: sint32; format: pchar; flags: ImGuiSliderFlags): boolean; cdecl; external;

{ ============================================================
  Widgets: Input with keyboard
  ============================================================ }
function  igInputText               (lbl: pchar; buf: pchar; buf_size: uint32; flags: ImGuiInputTextFlags; callback: ImGuiInputTextCallback; user_data: pointer): boolean; cdecl; external;
function  igInputTextMultiline      (lbl: pchar; buf: pchar; buf_size: uint32; size: TImVec2; flags: ImGuiInputTextFlags; callback: ImGuiInputTextCallback; user_data: pointer): boolean; cdecl; external;
function  igInputTextWithHint       (lbl: pchar; hint: pchar; buf: pchar; buf_size: uint32; flags: ImGuiInputTextFlags; callback: ImGuiInputTextCallback; user_data: pointer): boolean; cdecl; external;
function  igInputFloat              (lbl: pchar; v: PSingle; step, step_fast: single; format: pchar; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputFloat2             (lbl: pchar; v: PSingle; format: pchar; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputFloat3             (lbl: pchar; v: PSingle; format: pchar; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputFloat4             (lbl: pchar; v: PSingle; format: pchar; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputInt                (lbl: pchar; v: psint32; step, step_fast: sint32; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputInt2               (lbl: pchar; v: psint32; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputInt3               (lbl: pchar; v: psint32; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputInt4               (lbl: pchar; v: psint32; flags: ImGuiInputTextFlags): boolean; cdecl; external;
function  igInputDouble             (lbl: pchar; v: PDouble; step, step_fast: double; format: pchar; flags: ImGuiInputTextFlags): boolean; cdecl; external;

{ ============================================================
  Widgets: Color editor / picker
  ============================================================ }
function  igColorEdit3              (lbl: pchar; col: PSingle; flags: ImGuiColorEditFlags): boolean; cdecl; external;
function  igColorEdit4              (lbl: pchar; col: PSingle; flags: ImGuiColorEditFlags): boolean; cdecl; external;
function  igColorPicker3            (lbl: pchar; col: PSingle; flags: ImGuiColorEditFlags): boolean; cdecl; external;
function  igColorPicker4            (lbl: pchar; col: PSingle; ref_col: PSingle; flags: ImGuiColorEditFlags): boolean; cdecl; external;
function  igColorButton             (desc_id: pchar; col: TImVec4; flags: ImGuiColorEditFlags; size: TImVec2): boolean; cdecl; external;
procedure igSetColorEditOptions     (flags: ImGuiColorEditFlags); cdecl; external;

{ ============================================================
  Widgets: Trees & collapsing headers
  ============================================================ }
function  igTreeNode_Str            (lbl: pchar): boolean; cdecl; external;
function  igTreeNode_StrStr         (str_id: pchar; fmt: pchar): boolean; cdecl; external;
function  igTreeNodeEx_Str          (lbl: pchar; flags: ImGuiTreeNodeFlags): boolean; cdecl; external;
function  igTreeNodeEx_StrStr       (str_id: pchar; flags: ImGuiTreeNodeFlags; fmt: pchar): boolean; cdecl; external;
procedure igTreePush_Str            (str_id: pchar); cdecl; external;
procedure igTreePush_Ptr            (ptr_id: pointer); cdecl; external;
procedure igTreePop                 ; cdecl; external;
function  igGetTreeNodeToLabelSpacing: single; cdecl; external;
function  igCollapsingHeader_TreeNodeFlags(lbl: pchar; flags: ImGuiTreeNodeFlags): boolean; cdecl; external;
function  igCollapsingHeader_BoolPtr(lbl: pchar; p_visible: PBoolean; flags: ImGuiTreeNodeFlags): boolean; cdecl; external;
procedure igSetNextItemOpen         (is_open: boolean; cond: ImGuiCond_t); cdecl; external;
procedure igSetNextItemStorageID    (storage_id: ImGuiID); cdecl; external;

{ ============================================================
  Widgets: Selectables
  ============================================================ }
function  igSelectable_Bool         (lbl: pchar; selected: boolean; flags: ImGuiSelectableFlags; size: TImVec2): boolean; cdecl; external;
function  igSelectable_BoolPtr      (lbl: pchar; p_selected: PBoolean; flags: ImGuiSelectableFlags; size: TImVec2): boolean; cdecl; external;

{ ============================================================
  Widgets: List boxes
  ============================================================ }
function  igBeginListBox            (lbl: pchar; size: TImVec2): boolean; cdecl; external;
procedure igEndListBox              ; cdecl; external;
function  igListBox_Str_arr         (lbl: pchar; current_item: psint32; items: ppchar; items_count: sint32; height_in_items: sint32): boolean; cdecl; external;
function  igListBox_FnBoolPtr       (lbl: pchar; current_item: psint32; getter: pointer; user_data: pointer; items_count: sint32; height_in_items: sint32): boolean; cdecl; external;

{ ============================================================
  Widgets: Value helpers
  ============================================================ }
procedure igValue_Bool              (prefix: pchar; b: boolean); cdecl; external;
procedure igValue_Int               (prefix: pchar; v: sint32); cdecl; external;
procedure igValue_Uint              (prefix: pchar; v: uint32); cdecl; external;
procedure igValue_Float             (prefix: pchar; v: single; float_format: pchar); cdecl; external;

{ ============================================================
  Widgets: Plotting
  ============================================================ }
procedure igPlotLines_FloatPtr      (lbl: pchar; values: PSingle; values_count: sint32; values_offset: sint32; overlay_text: pchar; scale_min, scale_max: single; graph_size: TImVec2; stride: sint32); cdecl; external;
procedure igPlotHistogram_FloatPtr  (lbl: pchar; values: PSingle; values_count: sint32; values_offset: sint32; overlay_text: pchar; scale_min, scale_max: single; graph_size: TImVec2; stride: sint32); cdecl; external;

{ ============================================================
  Menus
  ============================================================ }
function  igBeginMenuBar            : boolean; cdecl; external;
procedure igEndMenuBar              ; cdecl; external;
function  igBeginMainMenuBar        : boolean; cdecl; external;
procedure igEndMainMenuBar          ; cdecl; external;
function  igBeginMenu               (lbl: pchar; enabled: boolean): boolean; cdecl; external;
procedure igEndMenu                 ; cdecl; external;
function  igMenuItem_Bool           (lbl: pchar; shortcut: pchar; selected: boolean; enabled: boolean): boolean; cdecl; external;
function  igMenuItem_BoolPtr        (lbl: pchar; shortcut: pchar; p_selected: PBoolean; enabled: boolean): boolean; cdecl; external;

{ ============================================================
  Tooltips
  ============================================================ }
function  igBeginTooltip            : boolean; cdecl; external;
procedure igEndTooltip              ; cdecl; external;
procedure igSetTooltip              (fmt: pchar); cdecl; external;
function  igBeginItemTooltip        : boolean; cdecl; external;
procedure igSetItemTooltip          (fmt: pchar); cdecl; external;

{ ============================================================
  Popups / modals
  ============================================================ }
function  igBeginPopup              (str_id: pchar; flags: ImGuiWindowFlags): boolean; cdecl; external;
function  igBeginPopupModal         (name: pchar; p_open: PBoolean; flags: ImGuiWindowFlags): boolean; cdecl; external;
procedure igEndPopup                ; cdecl; external;
procedure igOpenPopup_Str           (str_id: pchar; popup_flags: ImGuiPopupFlags); cdecl; external;
procedure igOpenPopupOnItemClick    (str_id: pchar; popup_flags: ImGuiPopupFlags); cdecl; external;
procedure igCloseCurrentPopup       ; cdecl; external;
function  igBeginPopupContextItem   (str_id: pchar; popup_flags: ImGuiPopupFlags): boolean; cdecl; external;
function  igBeginPopupContextWindow (str_id: pchar; popup_flags: ImGuiPopupFlags): boolean; cdecl; external;
function  igBeginPopupContextVoid   (str_id: pchar; popup_flags: ImGuiPopupFlags): boolean; cdecl; external;
function  igIsPopupOpen_Str         (str_id: pchar; flags: ImGuiPopupFlags): boolean; cdecl; external;

{ ============================================================
  Tables
  ============================================================ }
function  igBeginTable              (str_id: pchar; column: sint32; flags: ImGuiTableFlags; outer_size: TImVec2; inner_width: single): boolean; cdecl; external;
procedure igEndTable                ; cdecl; external;
procedure igTableNextRow            (row_flags: ImGuiTableRowFlags; min_row_height: single); cdecl; external;
function  igTableNextColumn         : boolean; cdecl; external;
function  igTableSetColumnIndex     (column_n: sint32): boolean; cdecl; external;
procedure igTableSetupColumn        (lbl: pchar; flags: ImGuiTableColumnFlags; init_width_or_weight: single; user_id: ImGuiID); cdecl; external;
procedure igTableSetupScrollFreeze  (cols: sint32; rows: sint32); cdecl; external;
procedure igTableHeader             (lbl: pchar); cdecl; external;
procedure igTableHeadersRow         ; cdecl; external;
procedure igTableAngledHeadersRow   ; cdecl; external;
function  igTableGetSortSpecs       : pointer; cdecl; external;
function  igTableGetColumnCount     : sint32; cdecl; external;
function  igTableGetColumnIndex     : sint32; cdecl; external;
function  igTableGetRowIndex        : sint32; cdecl; external;
function  igTableGetColumnName_Int  (column_n: sint32): pchar; cdecl; external;
function  igTableGetColumnFlags     (column_n: sint32): ImGuiTableColumnFlags; cdecl; external;
procedure igTableSetColumnEnabled   (column_n: sint32; v: boolean); cdecl; external;
procedure igTableSetBgColor         (target: ImGuiTableBgTarget; color: ImU32; column_n: sint32); cdecl; external;

{ ============================================================
  Tab bars
  ============================================================ }
function  igBeginTabBar             (str_id: pchar; flags: ImGuiTabBarFlags): boolean; cdecl; external;
procedure igEndTabBar               ; cdecl; external;
function  igBeginTabItem            (lbl: pchar; p_open: PBoolean; flags: ImGuiTabItemFlags): boolean; cdecl; external;
procedure igEndTabItem              ; cdecl; external;
function  igTabItemButton           (lbl: pchar; flags: ImGuiTabItemFlags): boolean; cdecl; external;
procedure igSetTabItemClosed        (tab_or_docked_window_label: pchar); cdecl; external;

{ ============================================================
  Draw list API
  ============================================================ }
function  igGetBackgroundDrawList   (viewport: PImGuiViewport): PImDrawList; cdecl; external;
function  igGetForegroundDrawList_ViewportPtr(viewport: PImGuiViewport): PImDrawList; cdecl; external;

{ ImDrawList primitives }
procedure ImDrawList_AddLine        (self: PImDrawList; p1, p2: TImVec2; col: ImU32; thickness: single); cdecl; external;
procedure ImDrawList_AddRect        (self: PImDrawList; p_min, p_max: TImVec2; col: ImU32; rounding: single; flags: sint32; thickness: single); cdecl; external;
procedure ImDrawList_AddRectFilled  (self: PImDrawList; p_min, p_max: TImVec2; col: ImU32; rounding: single; flags: sint32); cdecl; external;
procedure ImDrawList_AddRectFilledMultiColor(self: PImDrawList; p_min, p_max: TImVec2; col_upr_left, col_upr_right, col_bot_right, col_bot_left: ImU32); cdecl; external;
procedure ImDrawList_AddCircle      (self: PImDrawList; center: TImVec2; radius: single; col: ImU32; num_segments: sint32; thickness: single); cdecl; external;
procedure ImDrawList_AddCircleFilled(self: PImDrawList; center: TImVec2; radius: single; col: ImU32; num_segments: sint32); cdecl; external;
procedure ImDrawList_AddTriangleFilled(self: PImDrawList; p1, p2, p3: TImVec2; col: ImU32); cdecl; external;
procedure ImDrawList_AddText_Vec2   (self: PImDrawList; pos: TImVec2; col: ImU32; text_begin: pchar; text_end: pchar); cdecl; external;
procedure ImDrawList_AddBezierCubic (self: PImDrawList; p1, p2, p3, p4: TImVec2; col: ImU32; thickness: single; num_segments: sint32); cdecl; external;
procedure ImDrawList_AddNgonFilled  (self: PImDrawList; center: TImVec2; radius: single; col: ImU32; num_segments: sint32); cdecl; external;
procedure ImDrawList_AddEllipseFilled(self: PImDrawList; center: TImVec2; radius: TImVec2; col: ImU32; rot: single; num_segments: sint32); cdecl; external;

{ ============================================================
  Utilities: Item / widget state
  ============================================================ }
function  igIsItemHovered           (flags: ImGuiHoveredFlags): boolean; cdecl; external;
function  igIsItemActive            : boolean; cdecl; external;
function  igIsItemFocused           : boolean; cdecl; external;
function  igIsItemClicked           (mouse_button: ImGuiMouseButton_t): boolean; cdecl; external;
function  igIsItemVisible           : boolean; cdecl; external;
function  igIsItemEdited            : boolean; cdecl; external;
function  igIsItemActivated         : boolean; cdecl; external;
function  igIsItemDeactivated       : boolean; cdecl; external;
function  igIsItemDeactivatedAfterEdit: boolean; cdecl; external;
function  igIsItemToggledOpen       : boolean; cdecl; external;
function  igIsAnyItemHovered        : boolean; cdecl; external;
function  igIsAnyItemActive         : boolean; cdecl; external;
function  igIsAnyItemFocused        : boolean; cdecl; external;
function  igGetItemRectMin          : TImVec2; cdecl; external;
function  igGetItemRectMax          : TImVec2; cdecl; external;
function  igGetItemRectSize         : TImVec2; cdecl; external;

{ ============================================================
  Utilities: Colors / style
  ============================================================ }
procedure igPushStyleColor_U32      (idx: ImGuiCol_t; col: ImU32); cdecl; external;
procedure igPushStyleColor_Vec4     (idx: ImGuiCol_t; col: TImVec4); cdecl; external;
procedure igPopStyleColor           (count: sint32); cdecl; external;
procedure igPushStyleVar_Float      (idx: ImGuiStyleVar_t; val: single); cdecl; external;
procedure igPushStyleVar_Vec2       (idx: ImGuiStyleVar_t; val: TImVec2); cdecl; external;
procedure igPopStyleVar             (count: sint32); cdecl; external;
procedure igPushItemFlag            (option: sint32; enabled: boolean); cdecl; external;
procedure igPopItemFlag             ; cdecl; external;
function  igGetStyleColorVec4       (idx: ImGuiCol_t): PImVec4; cdecl; external;
function  igGetStyleColorU32        (idx: ImGuiCol_t; alpha_mul: single): ImU32; cdecl; external;

{ ============================================================
  Utilities: Keyboard / mouse
  ============================================================ }
function  igIsKeyDown_Nil           (key: ImGuiKeyType): boolean; cdecl; external;
function  igIsKeyPressed_Bool       (key: ImGuiKeyType; repeat_: boolean): boolean; cdecl; external;
function  igIsKeyReleased_Nil       (key: ImGuiKeyType): boolean; cdecl; external;
function  igGetKeyPressedAmount     (key: ImGuiKeyType; repeat_delay, rate: single): sint32; cdecl; external;
function  igIsMouseDown_Nil         (button: ImGuiMouseButton_t): boolean; cdecl; external;
function  igIsMouseClicked_Bool     (button: ImGuiMouseButton_t; repeat_: boolean): boolean; cdecl; external;
function  igIsMouseReleased_Nil     (button: ImGuiMouseButton_t): boolean; cdecl; external;
function  igIsMouseDoubleClicked_Nil(button: ImGuiMouseButton_t): boolean; cdecl; external;
function  igIsMouseHoveringRect     (r_min, r_max: TImVec2; clip: boolean): boolean; cdecl; external;
function  igGetMousePos             : TImVec2; cdecl; external;
function  igGetMouseDelta           : TImVec2; cdecl; external;
function  igIsMouseDragging         (button: ImGuiMouseButton_t; lock_threshold: single): boolean; cdecl; external;
function  igGetMouseCursor          : ImGuiMouseCursor_t; cdecl; external;

{ ============================================================
  Utilities: Misc
  ============================================================ }
function  igGetTime                 : double; cdecl; external;
function  igGetFrameCount           : sint32; cdecl; external;
function  igGetFont                 : PImFont; cdecl; external;
function  igGetFontSize             : single; cdecl; external;
function  igIsRectVisible_Nil       (size: TImVec2): boolean; cdecl; external;
function  igIsRectVisible_Vec2      (rect_min, rect_max: TImVec2): boolean; cdecl; external;
function  igCalcTextSize            (text: pchar; text_end: pchar; hide_text_after_double_hash: boolean; wrap_width: single): TImVec2; cdecl; external;
function  igColorConvertFloat4ToU32 (inp: TImVec4): ImU32; cdecl; external;
function  igColorConvertU32ToFloat4 (inp: ImU32): TImVec4; cdecl; external;
procedure igColorConvertRGBtoHSV    (r, g, b: single; out_h, out_s, out_v: PSingle); cdecl; external;
procedure igColorConvertHSVtoRGB    (h, s, v: single; out_r, out_g, out_b: PSingle); cdecl; external;
procedure igBeginDisabled           (disabled: boolean); cdecl; external;
procedure igEndDisabled             ; cdecl; external;
procedure igPushClipRect            (clip_rect_min, clip_rect_max: TImVec2; intersect_with_current_clip_rect: boolean); cdecl; external;
procedure igPopClipRect             ; cdecl; external;
procedure igSetItemDefaultFocus     ; cdecl; external;
procedure igSetKeyboardFocusHere    (offset: sint32); cdecl; external;
function  igGetContentRegionAvail   : TImVec2; cdecl; external;

{ ============================================================
  Separator / other visual helpers
  ============================================================ }
procedure igSeparator               ; cdecl; external;

{ ============================================================
  Bridge IO helpers (in imgbridge.c)
  ============================================================ }
procedure imgui_set_display_size    (w, h: single); cdecl; external;
procedure imgui_set_delta_time      (dt: single); cdecl; external;
procedure imgui_set_config_flags    (flags: sint32); cdecl; external;
procedure imgui_add_mouse_pos       (x, y: single); cdecl; external;
procedure imgui_add_mouse_button    (button: sint32; down: sint32); cdecl; external;
procedure imgui_add_mouse_wheel     (dx, dy: single); cdecl; external;
procedure imgui_add_key_event       (key: sint32; down: sint32); cdecl; external;
procedure imgui_add_input_char      (c: uint32); cdecl; external;
procedure imgui_handle_scancode     (scancode: uint32); cdecl; external;
procedure imgui_handle_mouse_pos    (x, y: single); cdecl; external;
procedure imgui_handle_mouse_button (button: sint32; down: sint32); cdecl; external;
procedure imgui_drain_input         ; cdecl; external;
function  imgui_get_framerate       : single; cdecl; external;
procedure imgui_render_frame        ; cdecl; external;

{ Debug counters from imgbridge.c (render stats) }
var
    imgui_dbg_triangles      : sint32; external name 'imgui_dbg_triangles';
    imgui_dbg_quads_solid    : sint32; external name 'imgui_dbg_quads_solid';
    imgui_dbg_quads_gradient : sint32; external name 'imgui_dbg_quads_gradient';
    imgui_dbg_quads_textured : sint32; external name 'imgui_dbg_quads_textured';
    imgui_dbg_tris_fallback  : sint32; external name 'imgui_dbg_tris_fallback';

implementation

{ ============================================================
  Renderer globals
  ============================================================ }
var
    FontTexture  : puint8 = nil;
    FontTexWidth : uint32 = 0;
    FontTexHeight: uint32 = 0;
    ScreenWidth  : uint32 = 0;
    ScreenHeight : uint32 = 0;
    ContextCreated : boolean = false;
    dbg_pixels_drawn : uint32 = 0;
    RenderBufPtr   : uint32 = 0;   { Direct back-buffer address for fast rasterizer writes }
    RenderBufStride : uint32 = 0;  { Back-buffer width (pixels per row) }

{ Debug counters from imgbridge.c }
var
    imgui_dbg_valid    : sint32; external name 'imgui_dbg_valid';
    imgui_dbg_cmdlists : sint32; external name 'imgui_dbg_cmdlists';
    imgui_dbg_texcount : sint32; external name 'imgui_dbg_texcount';
    imgui_dbg_font_w   : sint32; external name 'imgui_dbg_font_w';
    imgui_dbg_font_h   : sint32; external name 'imgui_dbg_font_h';

{ ============================================================
  Pascal allocator bridge  (called from crtshim malloc/free)
  ============================================================ }
function imgui_c_alloc(size: uint32): pointer; cdecl; public name 'imgui_c_alloc';
begin
    imgui_c_alloc := kalloc(size);
end;

procedure imgui_c_free(ptr: pointer); cdecl; public name 'imgui_c_free';
begin
    if ptr <> nil then kfree(void(ptr));
end;

{ ============================================================
  Font texture callback  (called from imgbridge once per context)
  ============================================================ }
procedure imgui_pascal_set_font_texture(pixels: puint8; w, h: sint32); cdecl; public name 'imgui_pascal_set_font_texture';
begin
    { ImGui owns this memory (it's in its own heap which is our kalloc).
      Just store the pointer – it remains valid for the context lifetime. }
    FontTexture   := pixels;
    FontTexWidth  := uint32(w);
    FontTexHeight := uint32(h);
end;

{ ============================================================
  FPU helper: truncate float to integer (toward zero)
  Uses x87 FISTTP if available, otherwise FLDCW+FISTP pattern.
  ============================================================ }
function ftrunc(f: Single): sint32;
var r: sint32;
begin
    asm
        FLD    DWORD [f]
        FISTTP DWORD [r]
    end;
    ftrunc := r;
end;

{ ============================================================
  Fast axis-aligned rect fill  (called from imgbridge for detected quads)

  Solid-color variant: uniform vertex color, single texture sample.
  Uses REP STOSD per scanline — orders of magnitude faster than
  per-pixel FP barycentric rasterization for the ~80% of ImGui
  draws that are axis-aligned rectangles.
  ============================================================ }
procedure imgui_pascal_fill_rect(
    rx0, ry0, rx1, ry1: Single;
    col: uint32;
    tex_u, tex_v: Single;
    cx0, cy0, cx1, cy1: Single);
    cdecl; public name 'imgui_pascal_fill_rect';
var
    ix0, iy0, ix1, iy1, y: sint32;
    w: uint32;
    fill_color: uint32;
    cr, cg, cb: uint32;
    tx, ty: sint32;
    tex_idx: uint32;
    tex_a: uint8;
    row_start: uint32;
begin
    if RenderBufPtr = 0 then exit;

    { Clip to clip rect }
    if rx0 < cx0 then rx0 := cx0;
    if ry0 < cy0 then ry0 := cy0;
    if rx1 > cx1 then rx1 := cx1;
    if ry1 > cy1 then ry1 := cy1;

    ix0 := ftrunc(rx0); iy0 := ftrunc(ry0);
    ix1 := ftrunc(rx1); iy1 := ftrunc(ry1);

    { Clamp to screen }
    if ix0 < 0 then ix0 := 0;
    if iy0 < 0 then iy0 := 0;
    if ix1 > sint32(RenderBufStride) then ix1 := sint32(RenderBufStride);
    if iy1 > sint32(ScreenHeight) then iy1 := sint32(ScreenHeight);
    if (ix0 >= ix1) or (iy0 >= iy1) then exit;

    w := uint32(ix1 - ix0);

    { Unpack ImU32 (R=byte0, G=byte1, B=byte2, A=byte3) }
    cr := col AND $FF;
    cg := (col SHR 8) AND $FF;
    cb := (col SHR 16) AND $FF;

    { Sample texture once at the given UV and modulate }
    if (FontTexture <> nil) and (FontTexWidth > 0) and (FontTexHeight > 0) then begin
        tx := ftrunc(tex_u * Single(FontTexWidth));
        ty := ftrunc(tex_v * Single(FontTexHeight));
        if tx < 0 then tx := 0;
        if ty < 0 then ty := 0;
        if tx >= sint32(FontTexWidth) then tx := sint32(FontTexWidth) - 1;
        if ty >= sint32(FontTexHeight) then ty := sint32(FontTexHeight) - 1;
        tex_idx := uint32(ty * sint32(FontTexWidth) + tx) * 4;
        tex_a := FontTexture[tex_idx + 3];
        if tex_a < 128 then exit;
        cr := (cr * uint32(FontTexture[tex_idx    ])) SHR 8;
        cg := (cg * uint32(FontTexture[tex_idx + 1])) SHR 8;
        cb := (cb * uint32(FontTexture[tex_idx + 2])) SHR 8;
    end;

    { Pack as TRGB32: B=byte0, G=byte1, R=byte2, A=byte3 }
    fill_color := cb OR (cg SHL 8) OR (cr SHL 16);

    { Fill each scanline with REP STOSD }
    for y := iy0 to iy1 - 1 do begin
        row_start := RenderBufPtr + uint32(y * sint32(RenderBufStride) + ix0) * 4;
        asm
            PUSHAD
            MOV EDI, row_start
            MOV ECX, w
            MOV EAX, fill_color
            CLD
            REP STOSD
            POPAD
        end;
    end;
end;

{ ============================================================
  Fast axis-aligned rect fill  (gradient variant)

  Handles AddRectFilledMultiColor and similar quads where the
  four corner colors differ.  Uses integer fixed-point interpolation
  per scanline/pixel — dramatically faster than FP barycentric math.
  For vertical gradients (left==right per row) it falls back to REP STOSD.
  ============================================================ }
procedure imgui_pascal_fill_rect_gradient(
    rx0, ry0, rx1, ry1: Single;
    col_tl, col_tr, col_br, col_bl: uint32;
    tex_u, tex_v: Single;
    cx0, cy0, cx1, cy1: Single);
    cdecl; public name 'imgui_pascal_fill_rect_gradient';
var
    ix0, iy0, ix1, iy1, y, x, h, w: sint32;
    tl_r, tl_g, tl_b, tr_r, tr_g, tr_b: sint32;
    bl_r, bl_g, bl_b, br_r, br_g, br_b: sint32;
    lr, lg, lb, rr, rg, rb: sint32;
    dr, dg, db: sint32;
    ar, ag, ab: sint32;
    pixel_val: uint32;
    fr, fg, fb: uint32;
    row_ptr: PUint32;
    tx, ty: sint32;
    tex_idx: uint32;
    tex_a: uint8;
    tmr, tmg, tmb: uint32;
    t_y: sint32;
    row_start: uint32;
begin
    if RenderBufPtr = 0 then exit;

    { Clip }
    if rx0 < cx0 then rx0 := cx0;
    if ry0 < cy0 then ry0 := cy0;
    if rx1 > cx1 then rx1 := cx1;
    if ry1 > cy1 then ry1 := cy1;

    ix0 := ftrunc(rx0); iy0 := ftrunc(ry0);
    ix1 := ftrunc(rx1); iy1 := ftrunc(ry1);
    if ix0 < 0 then ix0 := 0;
    if iy0 < 0 then iy0 := 0;
    if ix1 > sint32(RenderBufStride) then ix1 := sint32(RenderBufStride);
    if iy1 > sint32(ScreenHeight) then iy1 := sint32(ScreenHeight);
    if (ix0 >= ix1) or (iy0 >= iy1) then exit;

    h := iy1 - iy0;
    w := ix1 - ix0;

    { Sample texture once }
    tmr := 256; tmg := 256; tmb := 256;
    if (FontTexture <> nil) and (FontTexWidth > 0) and (FontTexHeight > 0) then begin
        tx := ftrunc(tex_u * Single(FontTexWidth));
        ty := ftrunc(tex_v * Single(FontTexHeight));
        if tx < 0 then tx := 0;
        if ty < 0 then ty := 0;
        if tx >= sint32(FontTexWidth) then tx := sint32(FontTexWidth) - 1;
        if ty >= sint32(FontTexHeight) then ty := sint32(FontTexHeight) - 1;
        tex_idx := uint32(ty * sint32(FontTexWidth) + tx) * 4;
        tex_a := FontTexture[tex_idx + 3];
        if tex_a < 128 then exit;
        tmr := uint32(FontTexture[tex_idx    ]) + 1;
        tmg := uint32(FontTexture[tex_idx + 1]) + 1;
        tmb := uint32(FontTexture[tex_idx + 2]) + 1;
    end;

    { Unpack corner colors (ImU32: R=byte0, G=byte1, B=byte2) }
    tl_r := sint32(col_tl AND $FF);        tl_g := sint32((col_tl SHR 8) AND $FF);
    tl_b := sint32((col_tl SHR 16) AND $FF);
    tr_r := sint32(col_tr AND $FF);        tr_g := sint32((col_tr SHR 8) AND $FF);
    tr_b := sint32((col_tr SHR 16) AND $FF);
    bl_r := sint32(col_bl AND $FF);        bl_g := sint32((col_bl SHR 8) AND $FF);
    bl_b := sint32((col_bl SHR 16) AND $FF);
    br_r := sint32(col_br AND $FF);        br_g := sint32((col_br SHR 8) AND $FF);
    br_b := sint32((col_br SHR 16) AND $FF);

    for y := 0 to h - 1 do begin
        { Vertical lerp factor 0..65536 }
        if h > 1 then t_y := (y * 65536) div (h - 1) else t_y := 0;
        if t_y > 65536 then t_y := 65536;

        { Left and right edge colors for this scanline (0..255) }
        lr := tl_r + ((bl_r - tl_r) * t_y) div 65536;
        lg := tl_g + ((bl_g - tl_g) * t_y) div 65536;
        lb := tl_b + ((bl_b - tl_b) * t_y) div 65536;
        rr := tr_r + ((br_r - tr_r) * t_y) div 65536;
        rg := tr_g + ((br_g - tr_g) * t_y) div 65536;
        rb := tr_b + ((br_b - tr_b) * t_y) div 65536;

        { If left==right, uniform scanline → REP STOSD }
        if (lr = rr) and (lg = rg) and (lb = rb) then begin
            fr := (uint32(lr) * tmr) SHR 8;
            fg := (uint32(lg) * tmg) SHR 8;
            fb := (uint32(lb) * tmb) SHR 8;
            pixel_val := fb OR (fg SHL 8) OR (fr SHL 16);
            row_start := RenderBufPtr + uint32((iy0 + y) * sint32(RenderBufStride) + ix0) * 4;
            asm
                PUSHAD
                MOV EDI, row_start
                MOV ECX, w
                MOV EAX, pixel_val
                CLD
                REP STOSD
                POPAD
            end;
        end else begin
            { Horizontal interpolation with 8.8 fixed-point stepping }
            row_ptr := @PUint32(RenderBufPtr)[(iy0 + y) * sint32(RenderBufStride)];
            ar := lr SHL 8;
            ag := lg SHL 8;
            ab := lb SHL 8;
            if w > 1 then begin
                dr := ((rr - lr) SHL 8) div (w - 1);
                dg := ((rg - lg) SHL 8) div (w - 1);
                db := ((rb - lb) SHL 8) div (w - 1);
            end else begin
                dr := 0; dg := 0; db := 0;
            end;
            for x := ix0 to ix1 - 1 do begin
                fr := (uint32(ar SHR 8) * tmr) SHR 8;
                fg := (uint32(ag SHR 8) * tmg) SHR 8;
                fb := (uint32(ab SHR 8) * tmb) SHR 8;
                row_ptr[x] := fb OR (fg SHL 8) OR (fr SHL 16);
                ar := ar + dr;
                ag := ag + dg;
                ab := ab + db;
            end;
        end;
    end;
end;

{ ============================================================
  Fast textured axis-aligned rect fill  (text glyphs, icons)

  For axis-aligned quads where UVs vary (texture-mapped) but vertex
  color is uniform.  Uses 16.16 fixed-point UV stepping — pure integer
  inner loop, no FP barycentric math.  Massively faster than the
  general triangle rasterizer for text rendering (~90% of non-solid draws).
  ============================================================ }
procedure imgui_pascal_fill_rect_textured(
    rx0, ry0, rx1, ry1: Single;
    u_left, v_top, u_right, v_bottom: Single;
    col: uint32;
    cx0, cy0, cx1, cy1: Single);
    cdecl; public name 'imgui_pascal_fill_rect_textured';
var
    ix0, iy0, ix1, iy1, y, x, w, h: sint32;
    cr, cg, cb: uint32;
    col_a: uint32;
    u_step_fp, v_step_fp: sint32;
    u_start_fp, v_fp: sint32;
    u_fp_val: sint32;
    tx, ty: sint32;
    tex_idx: uint32;
    tex_a: uint8;
    fr, fg, fb: uint32;
    pixel_val: uint32;
    row_ptr: PUint32;
    fbuf: PUint32;
    fstride: sint32;
    u_per_px, v_per_px: Single;
begin
    if RenderBufPtr = 0 then exit;
    if (FontTexture = nil) or (FontTexWidth = 0) or (FontTexHeight = 0) then exit;

    fbuf := PUint32(RenderBufPtr);
    fstride := sint32(RenderBufStride);

    { Early out on fully transparent vertex color }
    col_a := (col SHR 24) AND $FF;
    if col_a < 128 then exit;

    { Clip to clip rect }
    if rx0 < cx0 then rx0 := cx0;
    if ry0 < cy0 then ry0 := cy0;
    if rx1 > cx1 then rx1 := cx1;
    if ry1 > cy1 then ry1 := cy1;

    ix0 := ftrunc(rx0); iy0 := ftrunc(ry0);
    ix1 := ftrunc(rx1); iy1 := ftrunc(ry1);

    { Clamp to screen }
    if ix0 < 0 then ix0 := 0;
    if iy0 < 0 then iy0 := 0;
    if ix1 > fstride then ix1 := fstride;
    if iy1 > sint32(ScreenHeight) then iy1 := sint32(ScreenHeight);
    if (ix0 >= ix1) or (iy0 >= iy1) then exit;

    w := ix1 - ix0;
    h := iy1 - iy0;

    { Unpack ImU32 vertex color (R=byte0, G=byte1, B=byte2) }
    cr := col AND $FF;
    cg := (col SHR 8) AND $FF;
    cb := (col SHR 16) AND $FF;

    { Compute UV step per pixel as 16.16 fixed-point in texel space.
      We compute FP per-pixel UV step (2 divides per rect, not per pixel),
      then convert to 16.16 for pure-integer inner loop. }
    if w > 1 then
        u_per_px := (u_right - u_left) / (rx1 - rx0)
    else
        u_per_px := 0.0;
    if h > 1 then
        v_per_px := (v_bottom - v_top) / (ry1 - ry0)
    else
        v_per_px := 0.0;

    { Convert to 16.16 texel-space fixed point }
    u_start_fp := ftrunc((u_left + u_per_px * (Single(ix0) + 0.5 - rx0)) * Single(FontTexWidth) * 65536.0);
    v_fp       := ftrunc((v_top  + v_per_px * (Single(iy0) + 0.5 - ry0)) * Single(FontTexHeight) * 65536.0);
    u_step_fp  := ftrunc(u_per_px * Single(FontTexWidth) * 65536.0);
    v_step_fp  := ftrunc(v_per_px * Single(FontTexHeight) * 65536.0);

    { Rasterize with pure-integer inner loop }
    for y := iy0 to iy1 - 1 do begin
        ty := v_fp SHR 16;
        if ty < 0 then ty := 0;
        if ty >= sint32(FontTexHeight) then ty := sint32(FontTexHeight) - 1;

        row_ptr := @fbuf[y * fstride];
        u_fp_val := u_start_fp;

        for x := ix0 to ix1 - 1 do begin
            tx := u_fp_val SHR 16;
            if tx < 0 then tx := 0;
            if tx >= sint32(FontTexWidth) then tx := sint32(FontTexWidth) - 1;

            tex_idx := uint32(ty * sint32(FontTexWidth) + tx) * 4;
            tex_a := FontTexture[tex_idx + 3];

            if tex_a >= 128 then begin
                { Modulate vertex color with texel color }
                fr := (cr * uint32(FontTexture[tex_idx    ])) SHR 8;
                fg := (cg * uint32(FontTexture[tex_idx + 1])) SHR 8;
                fb := (cb * uint32(FontTexture[tex_idx + 2])) SHR 8;

                { TRGB32: B=byte0, G=byte1, R=byte2 }
                row_ptr[x] := fb OR (fg SHL 8) OR (fr SHL 16);
            end;

            u_fp_val := u_fp_val + u_step_fp;
        end;

        v_fp := v_fp + v_step_fp;
    end;
end;

{ ============================================================
  Software triangle rasterizer  (called from imgbridge per triangle)

  Fixed-point integer inner loop — NO floating point per pixel.
  Setup uses FP to compute 16.16 edge function increments, then the
  per-scanline / per-pixel work is pure integer: 2 ADDs for edge step,
  integer CMP, integer MUL+SHR for color/UV interpolation.

  Handles two cases:
   1) Uniform UV (all 3 verts same UV) — samples texture once, fast
      integer color interpolation per pixel.  Covers ~95% of fallback
      triangles (rounded corners, AA fringes).
   2) Varying UV — falls back to per-pixel UV interpolation (still
      fixed-point where possible).

  ImU32 color packing: R=byte0, G=byte1, B=byte2, A=byte3
  Font texture: RGBA32, column-major rows, width * height * 4 bytes
  ============================================================ }
procedure imgui_pascal_render_triangle(
    x0, y0, u0, v0: Single; c0: uint32;
    x1, y1, u1, v1: Single; c1: uint32;
    x2, y2, u2, v2: Single; c2: uint32;
    clip_x0, clip_y0, clip_x1, clip_y1: Single);
    cdecl; public name 'imgui_pascal_render_triangle';
const
    FP_SHIFT = 16;
    FP_ONE   = 1 SHL FP_SHIFT; { 65536 }
var
    minx, miny, maxx, maxy, px, py: sint32;
    denom: Single;
    inv_denom_f: Single;
    { 16.16 fixed-point edge functions and increments }
    w0_fp, w1_fp, w2_fp: sint32;
    w0_row, w1_row: sint32;
    dw0_dx, dw0_dy, dw1_dx, dw1_dy: sint32;
    { Integer vertex colors 0..255 }
    ir0, ig0, ib0, ia0: sint32;
    ir1, ig1, ib1, ia1: sint32;
    ir2, ig2, ib2, ia2: sint32;
    { Per-pixel interpolated values }
    pix_r, pix_g, pix_b, pix_a: sint32;
    { Texture }
    tex_a, tex_r, tex_g, tex_b: uint8;
    tex_idx: uint32;
    tx, ty: sint32;
    pixel_val: uint32;
    row_ptr: PUint32;
    fbuf: PUint32;
    fstride: uint32;
    fr, fg, fb: uint32;
    startx_f, fpy: Single;
    { UV handling }
    uniform_uv: boolean;
    tex_once_r, tex_once_g, tex_once_b: uint32;
    tex_once_valid: boolean;
    { For varying UV case }
    u_val, v_val: Single;
    w0_f, w1_f, w2_f: Single;
    dw0_dx_f, dw0_dy_f, dw1_dx_f, dw1_dy_f: Single;
    w0_row_f, w1_row_f: Single;

    function fmin2(a, b: Single): Single; inline;
    begin if a < b then fmin2 := a else fmin2 := b; end;
    function fmax2(a, b: Single): Single; inline;
    begin if a > b then fmax2 := a else fmax2 := b; end;

begin
    if RenderBufPtr = 0 then exit;
    fbuf := PUint32(RenderBufPtr);
    fstride := RenderBufStride;

    { Bounding box clipped to the clip rect }
    minx := ftrunc(fmax2(fmin2(fmin2(x0, x1), x2), clip_x0));
    miny := ftrunc(fmax2(fmin2(fmin2(y0, y1), y2), clip_y0));
    maxx := ftrunc(fmin2(fmax2(fmax2(x0, x1), x2) + 1.0, clip_x1));
    maxy := ftrunc(fmin2(fmax2(fmax2(y0, y1), y2) + 1.0, clip_y1));
    if (minx >= maxx) or (miny >= maxy) then exit;
    if minx < 0 then minx := 0;
    if miny < 0 then miny := 0;
    if maxx > sint32(fstride) then maxx := sint32(fstride);
    if maxy > sint32(ScreenHeight) then maxy := sint32(ScreenHeight);

    { Signed area — skip degenerate triangles }
    denom := (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
    if (denom > -0.5) and (denom < 0.5) then exit;
    inv_denom_f := 1.0 / denom;

    { For very thin triangles (area < some threshold relative to bounding box),
      force the FP path. The integer path has precision issues when the triangle
      is much thinner than its bounding box — edge function steps are too small
      relative to 16.16 fixed point, causing stray pixel acceptance.
      Threshold: if area < max(bbox_w, bbox_h), the triangle is degenerate-ish. }
    if denom < 0 then begin
        if (-denom) < Single(maxx - minx + maxy - miny) then
            uniform_uv := false;
    end else begin
        if denom < Single(maxx - minx + maxy - miny) then
            uniform_uv := false;
    end;

    { Unpack integer vertex colors }
    ir0 := sint32(c0 AND $FF);        ig0 := sint32((c0 SHR 8) AND $FF);
    ib0 := sint32((c0 SHR 16) AND $FF); ia0 := sint32((c0 SHR 24) AND $FF);
    ir1 := sint32(c1 AND $FF);        ig1 := sint32((c1 SHR 8) AND $FF);
    ib1 := sint32((c1 SHR 16) AND $FF); ia1 := sint32((c1 SHR 24) AND $FF);
    ir2 := sint32(c2 AND $FF);        ig2 := sint32((c2 SHR 8) AND $FF);
    ib2 := sint32((c2 SHR 16) AND $FF); ia2 := sint32((c2 SHR 24) AND $FF);

    { Check for uniform UV (all 3 verts same UV — very common for non-textured tris) }
    uniform_uv := (u0 = u1) and (u1 = u2) and (v0 = v1) and (v1 = v2);

    { Pre-sample texture once for uniform UV case }
    tex_once_r := 256; tex_once_g := 256; tex_once_b := 256;
    tex_once_valid := true;
    if uniform_uv then begin
        if (FontTexture <> nil) and (FontTexWidth > 0) and (FontTexHeight > 0) then begin
            tx := ftrunc(u0 * Single(FontTexWidth));
            ty := ftrunc(v0 * Single(FontTexHeight));
            if tx < 0 then tx := 0;
            if ty < 0 then ty := 0;
            if tx >= sint32(FontTexWidth)  then tx := sint32(FontTexWidth)  - 1;
            if ty >= sint32(FontTexHeight) then ty := sint32(FontTexHeight) - 1;
            tex_idx := uint32(ty * sint32(FontTexWidth) + tx) * 4;
            if FontTexture[tex_idx + 3] < 128 then begin tex_once_valid := false; exit; end;
            tex_once_r := uint32(FontTexture[tex_idx    ]) + 1;
            tex_once_g := uint32(FontTexture[tex_idx + 1]) + 1;
            tex_once_b := uint32(FontTexture[tex_idx + 2]) + 1;
        end;
    end;

    { Compute 16.16 fixed-point edge function increments.
      FP is used only here (setup), not in the per-pixel loop. }
    dw0_dx := ftrunc((y1 - y2) * inv_denom_f * Single(FP_ONE));
    dw0_dy := ftrunc(-(x1 - x2) * inv_denom_f * Single(FP_ONE));
    dw1_dx := ftrunc((y2 - y0) * inv_denom_f * Single(FP_ONE));
    dw1_dy := ftrunc(-(x2 - x0) * inv_denom_f * Single(FP_ONE));

    { Guard against fixed-point overflow: if any step is large enough to
      risk sint32 wrap during scanline traversal, use the FP path. }
    if (dw0_dx > 262144) or (dw0_dx < -262144) or
       (dw0_dy > 262144) or (dw0_dy < -262144) or
       (dw1_dx > 262144) or (dw1_dx < -262144) or
       (dw1_dy > 262144) or (dw1_dy < -262144) then
        uniform_uv := false;

    { Edge functions at the starting corner (minx+0.5, miny+0.5) }
    startx_f := Single(minx) + 0.5;
    fpy      := Single(miny) + 0.5;
    w0_row := ftrunc(((y1 - y2) * (startx_f - x2) - (x1 - x2) * (fpy - y2)) * inv_denom_f * Single(FP_ONE));
    w1_row := ftrunc(((y2 - y0) * (startx_f - x0) - (x2 - x0) * (fpy - y0)) * inv_denom_f * Single(FP_ONE));

    { ---- Uniform UV path: pure integer inner loop ---- }
    if uniform_uv then begin
        for py := miny to maxy - 1 do begin
            w0_fp := w0_row;
            w1_fp := w1_row;
            row_ptr := @fbuf[py * sint32(fstride)];

            for px := minx to maxx - 1 do begin
                { Conservative rasterisation: -32 in 16.16 is ~0.0005,
                  prevents 1-pixel gaps at shared triangle edges }
                if (w0_fp >= -32) and (w1_fp >= -32) then begin
                    w2_fp := FP_ONE - w0_fp - w1_fp;
                    if w2_fp >= -32 then begin
                        { Interpolate alpha: (w0*a0 + w1*a1 + w2*a2) >> 16 }
                        pix_a := (w0_fp * ia0 + w1_fp * ia1 + w2_fp * ia2) SHR FP_SHIFT;
                        if pix_a >= 128 then begin
                            { Interpolate color: integer only }
                            pix_r := (w0_fp * ir0 + w1_fp * ir1 + w2_fp * ir2) SHR FP_SHIFT;
                            pix_g := (w0_fp * ig0 + w1_fp * ig1 + w2_fp * ig2) SHR FP_SHIFT;
                            pix_b := (w0_fp * ib0 + w1_fp * ib1 + w2_fp * ib2) SHR FP_SHIFT;

                            { Clamp to valid range (guards against FP rounding overshoot) }
                            if pix_r < 0 then pix_r := 0 else if pix_r > 255 then pix_r := 255;
                            if pix_g < 0 then pix_g := 0 else if pix_g > 255 then pix_g := 255;
                            if pix_b < 0 then pix_b := 0 else if pix_b > 255 then pix_b := 255;

                            { Modulate by pre-sampled texture (256 = white = no-op) }
                            fr := (uint32(pix_r) * tex_once_r) SHR 8;
                            fg := (uint32(pix_g) * tex_once_g) SHR 8;
                            fb := (uint32(pix_b) * tex_once_b) SHR 8;

                            row_ptr[px] := fb OR (fg SHL 8) OR (fr SHL 16);
                        end;
                    end;
                end;
                w0_fp := w0_fp + dw0_dx;
                w1_fp := w1_fp + dw1_dx;
            end;

            w0_row := w0_row + dw0_dy;
            w1_row := w1_row + dw1_dy;
        end;
    end else begin
        { ---- Varying UV path: floating-point UV interpolation per pixel ---- }
        dw0_dx_f := (y1 - y2) * inv_denom_f;
        dw0_dy_f := -(x1 - x2) * inv_denom_f;
        dw1_dx_f := (y2 - y0) * inv_denom_f;
        dw1_dy_f := -(x2 - x0) * inv_denom_f;
        w0_row_f := ((y1 - y2) * (startx_f - x2) - (x1 - x2) * (fpy - y2)) * inv_denom_f;
        w1_row_f := ((y2 - y0) * (startx_f - x0) - (x2 - x0) * (fpy - y0)) * inv_denom_f;

        for py := miny to maxy - 1 do begin
            w0_f := w0_row_f;
            w1_f := w1_row_f;
            row_ptr := @fbuf[py * sint32(fstride)];

            for px := minx to maxx - 1 do begin
                { Conservative rasterisation: small epsilon prevents
                  1-pixel gaps at shared triangle edges }
                if (w0_f >= -0.001) and (w1_f >= -0.001) then begin
                    w2_f := 1.0 - w0_f - w1_f;
                    if w2_f >= -0.001 then begin
                        pix_a := ftrunc(w0_f * Single(ia0) + w1_f * Single(ia1) + w2_f * Single(ia2));
                        if pix_a >= 128 then begin
                            u_val := w0_f * u0 + w1_f * u1 + w2_f * u2;
                            v_val := w0_f * v0 + w1_f * v1 + w2_f * v2;
                            if u_val < 0.0 then u_val := 0.0 else if u_val > 1.0 then u_val := 1.0;
                            if v_val < 0.0 then v_val := 0.0 else if v_val > 1.0 then v_val := 1.0;
                            tex_r := 255; tex_g := 255; tex_b := 255; tex_a := 255;
                            if (FontTexture <> nil) and (FontTexWidth > 0) and (FontTexHeight > 0) then begin
                                tx := ftrunc(u_val * Single(FontTexWidth));
                                ty := ftrunc(v_val * Single(FontTexHeight));
                                if tx >= sint32(FontTexWidth)  then tx := sint32(FontTexWidth)  - 1;
                                if ty >= sint32(FontTexHeight) then ty := sint32(FontTexHeight) - 1;
                                tex_idx := uint32(ty * sint32(FontTexWidth) + tx) * 4;
                                tex_r := FontTexture[tex_idx];
                                tex_g := FontTexture[tex_idx + 1];
                                tex_b := FontTexture[tex_idx + 2];
                                tex_a := FontTexture[tex_idx + 3];
                            end;
                            if tex_a >= 128 then begin
                                pix_r := ftrunc(w0_f * Single(ir0) + w1_f * Single(ir1) + w2_f * Single(ir2));
                                pix_g := ftrunc(w0_f * Single(ig0) + w1_f * Single(ig1) + w2_f * Single(ig2));
                                pix_b := ftrunc(w0_f * Single(ib0) + w1_f * Single(ib1) + w2_f * Single(ib2));
                                fr := (uint32(pix_r) * uint32(tex_r)) SHR 8;
                                fg := (uint32(pix_g) * uint32(tex_g)) SHR 8;
                                fb := (uint32(pix_b) * uint32(tex_b)) SHR 8;
                                row_ptr[px] := fb OR (fg SHL 8) OR (fr SHL 16);
                            end;
                        end;
                    end;
                end;
                w0_f := w0_f + dw0_dx_f;
                w1_f := w1_f + dw1_dx_f;
            end;
            w0_row_f := w0_row_f + dw0_dy_f;
            w1_row_f := w1_row_f + dw1_dy_f;
        end;
    end;
end;

{ ============================================================
  High-level API
  ============================================================ }
procedure imgui_init(display_w, display_h: uint32);
var
    ctx: PImGuiContext;
begin
    tracer.push_trace('imgui.init.enter');
    console.outputln('IMGUI', 'INIT BEGIN.');

    ScreenWidth  := display_w;
    ScreenHeight := display_h;

    ctx := igCreateContext(nil);
    if ctx = nil then begin
        console.outputln('IMGUI', 'ERROR: igCreateContext returned nil.');
        tracer.push_trace('imgui.init.exit');
        exit;
    end;

    igStyleColorsDark(nil);

    { Tell ImGui about the screen – must happen before the first igNewFrame }
    imgui_set_display_size(Single(display_w), Single(display_h));
    imgui_set_delta_time(0.016);
    imgui_set_config_flags(ImGuiConfigFlags_NavEnableKeyboard);

    { Disable INI file persistence (no filesystem in bare-metal) }
    { We can't write to IO.IniFilename directly here without struct layout,
      so we rely on imgbridge setting this via igGetIO().IniFilename = NULL.
      For now ImGui will just use an in-memory state that's lost on reboot. }

    ContextCreated := true;
    console.outputln('IMGUI', 'INIT END.');
    tracer.push_trace('imgui.init.exit');
end;

procedure imgui_shutdown;
begin
    tracer.push_trace('imgui.shutdown.enter');
    if ContextCreated then begin
        igDestroyContext(nil);
        ContextCreated := false;
        FontTexture    := nil;
        FontTexWidth   := 0;
        FontTexHeight  := 0;
    end;
    tracer.push_trace('imgui.shutdown.exit');
end;

procedure imgui_new_frame_impl; cdecl; external;

procedure imgui_new_frame;
begin
    imgui_new_frame_impl;
end;

procedure imgui_render;
var
    buf: uint32;
    count: uint32;
    clear_color: uint32;
begin
    dbg_pixels_drawn := 0;

    { Fast clear: REP STOSD fills entire back buffer in ~1ms vs ~200ms with DrawPixel loop }
    buf := video.backBufferLocation;
    if buf <> 0 then begin
        count := ScreenWidth * ScreenHeight;
        clear_color := $00282828;  { TRGB32: B=28 G=28 R=28 A=00 }
        asm
            PUSHAD
            MOV EDI, buf
            MOV ECX, count
            MOV EAX, clear_color
            CLD
            REP STOSD
            POPAD
        end;
    end;

    { Cache buffer pointer and stride for the rasterizer's direct writes }
    RenderBufPtr   := buf;
    RenderBufStride := ScreenWidth;

    { imgui_render_frame calls igRender() internally, then walks the draw data }
    imgui_render_frame;

    { Flush the back buffer to the screen }
    video.Flush;
end;

{ ============================================================
  Input wrappers
  ============================================================ }
procedure imgui_feed_mouse_pos(x, y: single);
begin imgui_add_mouse_pos(x, y); end;

procedure imgui_feed_mouse_button(button: sint32; down: boolean);
begin imgui_add_mouse_button(button, sint32(down)); end;

procedure imgui_feed_mouse_wheel(dy: single);
begin imgui_add_mouse_wheel(0.0, dy); end;

procedure imgui_feed_key(imgui_key: sint32; down: boolean);
begin imgui_add_key_event(imgui_key, sint32(down)); end;

procedure imgui_feed_char(codepoint: uint32);
begin imgui_add_input_char(codepoint); end;

procedure imgui_feed_delta_time(dt: single);
begin imgui_set_delta_time(dt); end;

procedure imgui_process_input;
begin imgui_drain_input; end;

end.
