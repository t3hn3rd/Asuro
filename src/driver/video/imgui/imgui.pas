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
function  igGetFramerate            : single; cdecl; external;
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
procedure imgui_render_frame        ; cdecl; external;
procedure imgui_test_window         ; cdecl; external;

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

{ Debug counters from imgbridge.c }
var
    imgui_dbg_valid    : sint32; external name 'imgui_dbg_valid';
    imgui_dbg_cmdlists : sint32; external name 'imgui_dbg_cmdlists';
    imgui_dbg_triangles: sint32; external name 'imgui_dbg_triangles';
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
  Software triangle rasterizer  (called from imgbridge per triangle)

  ImU32 color packing: R=byte0, G=byte1, B=byte2, A=byte3
  Font texture: RGBA32, column-major rows, width * height * 4 bytes
  Alpha threshold: >= 128 = opaque (works perfectly for ProggyClean)
  ============================================================ }
procedure imgui_pascal_render_triangle(
    x0, y0, u0, v0: Single; c0: uint32;
    x1, y1, u1, v1: Single; c1: uint32;
    x2, y2, u2, v2: Single; c2: uint32;
    clip_x0, clip_y0, clip_x1, clip_y1: Single);
    cdecl; public name 'imgui_pascal_render_triangle';
var
    minx, miny, maxx, maxy, px, py: sint32;
    fpx, fpy: Single;
    denom, w0, w1, w2: Single;
    u, v, vr, vg, vb, va: Single;
    r0, g0, b0, a0: Single;
    r1, g1, b1, a1: Single;
    r2, g2, b2, a2: Single;
    tex_a, tex_r, tex_g, tex_b: uint8;
    tex_idx: uint32;
    tx, ty: sint32;
    pix: TRGB32;

    { Inline min/max to avoid external calls in the hot path }
    function fmin2(a, b: Single): Single; inline;
    begin if a < b then fmin2 := a else fmin2 := b; end;
    function fmax2(a, b: Single): Single; inline;
    begin if a > b then fmax2 := a else fmax2 := b; end;

begin
    { Unpack ImU32 vertex colors: R in LSB }
    r0 := Single(c0 AND $FF);        g0 := Single((c0 SHR 8) AND $FF);
    b0 := Single((c0 SHR 16) AND $FF); a0 := Single((c0 SHR 24) AND $FF);
    r1 := Single(c1 AND $FF);        g1 := Single((c1 SHR 8) AND $FF);
    b1 := Single((c1 SHR 16) AND $FF); a1 := Single((c1 SHR 24) AND $FF);
    r2 := Single(c2 AND $FF);        g2 := Single((c2 SHR 8) AND $FF);
    b2 := Single((c2 SHR 16) AND $FF); a2 := Single((c2 SHR 24) AND $FF);

    { Bounding box clipped to the clip rect }
    minx := ftrunc(fmax2(fmin2(fmin2(x0, x1), x2), clip_x0));
    miny := ftrunc(fmax2(fmin2(fmin2(y0, y1), y2), clip_y0));
    maxx := ftrunc(fmin2(fmax2(fmax2(x0, x1), x2) + 1.0, clip_x1));
    maxy := ftrunc(fmin2(fmax2(fmax2(y0, y1), y2) + 1.0, clip_y1));

    if (minx >= maxx) or (miny >= maxy) then exit;

    { Signed area – skip degenerate triangles }
    denom := (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
    if (denom > -0.5) and (denom < 0.5) then exit;

    for py := miny to maxy - 1 do begin
        fpy := Single(py) + 0.5;
        for px := minx to maxx - 1 do begin
            fpx := Single(px) + 0.5;

            { Barycentric weights via edge functions
              Correct form: w_i = [(y_j - y_k)*(px - x_k) - (x_j - x_k)*(py - y_k)] / denom }
            w0 := ((y1 - y2) * (fpx - x2) - (x1 - x2) * (fpy - y2)) / denom;
            if w0 < 0.0 then continue;
            w1 := ((y2 - y0) * (fpx - x0) - (x2 - x0) * (fpy - y0)) / denom;
            if w1 < 0.0 then continue;
            w2 := 1.0 - w0 - w1;
            if w2 < 0.0 then continue;

            { Early-out on interpolated alpha before doing the texture lookup }
            va := w0 * a0 + w1 * a1 + w2 * a2;
            if va < 128.0 then continue;

            { Interpolate UV, clamp to [0,1] }
            u := w0 * u0 + w1 * u1 + w2 * u2;
            v := w0 * v0 + w1 * v1 + w2 * v2;
            if u < 0.0 then u := 0.0 else if u > 1.0 then u := 1.0;
            if v < 0.0 then v := 0.0 else if v > 1.0 then v := 1.0;

            { Sample RGBA32 font atlas
              ImGui UV convention: u = pixel_x / atlas_width, so the
              correct nearest-filter lookup is floor(u * Width) clamped
              to [0, Width-1].  Using (Width-1) instead of Width
              causes a cumulative 1-texel shift that garbles glyphs. }
            if (FontTexture <> nil) and (FontTexWidth > 0) and (FontTexHeight > 0) then begin
                tx := ftrunc(u * Single(FontTexWidth));
                ty := ftrunc(v * Single(FontTexHeight));
                if tx >= sint32(FontTexWidth)  then tx := sint32(FontTexWidth)  - 1;
                if ty >= sint32(FontTexHeight) then ty := sint32(FontTexHeight) - 1;
                tex_idx := uint32(ty * sint32(FontTexWidth) + tx) * 4;
                tex_r := FontTexture[tex_idx];
                tex_g := FontTexture[tex_idx + 1];
                tex_b := FontTexture[tex_idx + 2];
                tex_a := FontTexture[tex_idx + 3];
            end else begin
                tex_r := 255; tex_g := 255; tex_b := 255; tex_a := 255;
            end;

            if tex_a < 128 then continue;

            { Modulate vertex color × texel color (0–255 range, shift-8 multiply) }
            vr := w0 * r0 + w1 * r1 + w2 * r2;
            vg := w0 * g0 + w1 * g1 + w2 * g2;
            vb := w0 * b0 + w1 * b1 + w2 * b2;

            pix.R := uint8( (uint32(ftrunc(vr)) * uint32(tex_r)) SHR 8 );
            pix.G := uint8( (uint32(ftrunc(vg)) * uint32(tex_g)) SHR 8 );
            pix.B := uint8( (uint32(ftrunc(vb)) * uint32(tex_b)) SHR 8 );
            pix.A := 0;

            dbg_pixels_drawn := dbg_pixels_drawn + 1;
            video.DrawPixel(uint32(px), uint32(py), pix);
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
    bg: TRGB32;
    i, j: uint32;
begin
    dbg_pixels_drawn := 0;

    { Clear back buffer to dark grey before rasterizing }
    bg.R := 40; bg.G := 40; bg.B := 40; bg.A := 0;
    for j := 0 to ScreenHeight - 1 do
        for i := 0 to ScreenWidth - 1 do
            video.DrawPixel(i, j, bg);

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

end.
