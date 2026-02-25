{ 
    Driver->Video->Imgui->ImguiTypes
    Pascal type and constant definitions mirroring Dear ImGui / cimgui.
    All integral flag typedefs map to sint32 to match C's int ABI.
    
    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit imguitypes;

interface

{ ============================================================
  Primitive aliases
  ============================================================ }
type
    ImGuiID             = uint32;
    ImGuiWindowFlags    = sint32;
    ImGuiChildFlags     = sint32;
    ImGuiInputTextFlags = sint32;
    ImGuiTreeNodeFlags  = sint32;
    ImGuiPopupFlags     = sint32;
    ImGuiSelectableFlags= sint32;
    ImGuiComboFlags     = sint32;
    ImGuiTabBarFlags    = sint32;
    ImGuiTabItemFlags   = sint32;
    ImGuiTableFlags     = sint32;
    ImGuiTableColumnFlags = sint32;
    ImGuiTableRowFlags  = sint32;
    ImGuiTableBgTarget  = sint32;
    ImGuiColorEditFlags = sint32;
    ImGuiSliderFlags    = sint32;
    ImGuiMouseButton_t  = sint32;
    ImGuiMouseCursor_t  = sint32;
    ImGuiCond_t         = sint32;
    ImGuiDataType_t     = sint32;
    ImGuiDir_t          = sint32;
    ImGuiKeyType        = sint32;
    ImGuiConfigFlags    = sint32;
    ImGuiBackendFlags   = sint32;
    ImGuiFocusedFlags   = sint32;
    ImGuiHoveredFlags   = sint32;
    ImGuiDragDropFlags  = sint32;
    ImGuiCol_t          = sint32;
    ImGuiStyleVar_t     = sint32;
    ImGuiSortDirection_t= sint32;
    ImGuiNavInput_t     = sint32;
    ImU32               = uint32;
    ImTextureID         = uint64;   { ImU64 in cimgui 1.91+ }
    ImDrawIdx           = uint16;

    { Vector types: must exactly match C layout (packed floats) }
    TImVec2 = packed record
        x, y : Single;
    end;
    PImVec2 = ^TImVec2;

    TImVec4 = packed record
        x, y, z, w : Single;
    end;
    PImVec4 = ^TImVec4;

    { Texture reference (ImGui 1.91+) }
    TImTextureRef = packed record
        _TexData : pointer;  { PImTextureData }
        _TexID   : ImTextureID;
    end;
    PImTextureRef = ^TImTextureRef;

    { Opaque handles - passed as pointers to cimgui }
    PImGuiContext  = pointer;
    PImGuiIO       = pointer;
    PImGuiStyle    = pointer;
    PImDrawData    = pointer;
    PImDrawList    = pointer;
    PImFont        = pointer;
    PImFontAtlas   = pointer;
    PImGuiViewport = pointer;
    PImGuiPayload  = pointer;
    PPImVec4       = ^PImVec4;
    PSingle        = ^Single;
    PDouble        = ^Double;
    PBoolean       = ^Boolean;
    ppchar         = ^pchar;

    { InputText callback data }
    PImGuiInputTextCallbackData = pointer;
    ImGuiInputTextCallback = function(data : PImGuiInputTextCallbackData) : sint32; cdecl;

    { Size callback }
    PImGuiSizeCallbackData = pointer;
    ImGuiSizeCallback = procedure(data : PImGuiSizeCallbackData); cdecl;

{ ============================================================
  ImGuiWindowFlags
  ============================================================ }
const
    ImGuiWindowFlags_None                      = 0;
    ImGuiWindowFlags_NoTitleBar                = 1 SHL 0;
    ImGuiWindowFlags_NoResize                  = 1 SHL 1;
    ImGuiWindowFlags_NoMove                    = 1 SHL 2;
    ImGuiWindowFlags_NoScrollbar               = 1 SHL 3;
    ImGuiWindowFlags_NoScrollWithMouse         = 1 SHL 4;
    ImGuiWindowFlags_NoCollapse                = 1 SHL 5;
    ImGuiWindowFlags_AlwaysAutoResize          = 1 SHL 6;
    ImGuiWindowFlags_NoBackground              = 1 SHL 7;
    ImGuiWindowFlags_NoSavedSettings           = 1 SHL 8;
    ImGuiWindowFlags_NoMouseInputs             = 1 SHL 9;
    ImGuiWindowFlags_MenuBar                   = 1 SHL 10;
    ImGuiWindowFlags_HorizontalScrollbar       = 1 SHL 11;
    ImGuiWindowFlags_NoFocusOnAppearing        = 1 SHL 12;
    ImGuiWindowFlags_NoBringToDisplayOnFocus   = 1 SHL 13;
    ImGuiWindowFlags_AlwaysVerticalScrollbar   = 1 SHL 14;
    ImGuiWindowFlags_AlwaysHorizontalScrollbar = 1 SHL 15;
    ImGuiWindowFlags_NoNavInputs               = 1 SHL 16;
    ImGuiWindowFlags_NoNavFocus                = 1 SHL 17;
    ImGuiWindowFlags_UnsavedDocument           = 1 SHL 18;
    ImGuiWindowFlags_NoNav                     = ImGuiWindowFlags_NoNavInputs OR ImGuiWindowFlags_NoNavFocus;
    ImGuiWindowFlags_NoDecoration              = ImGuiWindowFlags_NoTitleBar OR ImGuiWindowFlags_NoResize OR ImGuiWindowFlags_NoScrollbar OR ImGuiWindowFlags_NoCollapse;
    ImGuiWindowFlags_NoInputs                  = ImGuiWindowFlags_NoMouseInputs OR ImGuiWindowFlags_NoNav;

{ ============================================================
  ImGuiChildFlags
  ============================================================ }
const
    ImGuiChildFlags_None            = 0;
    ImGuiChildFlags_Border          = 1 SHL 0;
    ImGuiChildFlags_AlwaysUseWindowPadding = 1 SHL 1;
    ImGuiChildFlags_ResizeX         = 1 SHL 2;
    ImGuiChildFlags_ResizeY         = 1 SHL 3;
    ImGuiChildFlags_AutoResizeX     = 1 SHL 4;
    ImGuiChildFlags_AutoResizeY     = 1 SHL 5;
    ImGuiChildFlags_AlwaysAutoResize= 1 SHL 6;
    ImGuiChildFlags_FrameStyle      = 1 SHL 7;

{ ============================================================
  ImGuiInputTextFlags
  ============================================================ }
const
    ImGuiInputTextFlags_None                = 0;
    { Character filters }
    ImGuiInputTextFlags_CharsDecimal        = 1 SHL 0;
    ImGuiInputTextFlags_CharsHexadecimal    = 1 SHL 1;
    ImGuiInputTextFlags_CharsScientific     = 1 SHL 2;
    ImGuiInputTextFlags_CharsUppercase      = 1 SHL 3;
    ImGuiInputTextFlags_CharsNoBlank        = 1 SHL 4;
    { Inputs }
    ImGuiInputTextFlags_AllowTabInput       = 1 SHL 5;
    ImGuiInputTextFlags_EnterReturnsTrue    = 1 SHL 6;
    ImGuiInputTextFlags_EscapeClearsAll     = 1 SHL 7;
    ImGuiInputTextFlags_CtrlEnterForNewLine = 1 SHL 8;
    { Other options }
    ImGuiInputTextFlags_ReadOnly            = 1 SHL 9;
    ImGuiInputTextFlags_Password            = 1 SHL 10;
    ImGuiInputTextFlags_AlwaysOverwrite     = 1 SHL 11;
    ImGuiInputTextFlags_AutoSelectAll       = 1 SHL 12;
    ImGuiInputTextFlags_ParseEmptyRefVal    = 1 SHL 13;
    ImGuiInputTextFlags_DisplayEmptyRefVal  = 1 SHL 14;
    ImGuiInputTextFlags_NoHorizontalScroll  = 1 SHL 15;
    ImGuiInputTextFlags_NoUndoRedo          = 1 SHL 16;
    { Callback features }
    ImGuiInputTextFlags_CallbackCompletion  = 1 SHL 17;
    ImGuiInputTextFlags_CallbackHistory     = 1 SHL 18;
    ImGuiInputTextFlags_CallbackAlways      = 1 SHL 19;
    ImGuiInputTextFlags_CallbackCharFilter  = 1 SHL 20;
    ImGuiInputTextFlags_CallbackResize      = 1 SHL 21;
    ImGuiInputTextFlags_CallbackEdit        = 1 SHL 22;

{ ============================================================
  ImGuiTreeNodeFlags
  ============================================================ }
const
    ImGuiTreeNodeFlags_None             = 0;
    ImGuiTreeNodeFlags_Selected         = 1 SHL 0;
    ImGuiTreeNodeFlags_Framed           = 1 SHL 1;
    ImGuiTreeNodeFlags_AllowOverlap     = 1 SHL 2;
    ImGuiTreeNodeFlags_NoTreePushOnOpen = 1 SHL 3;
    ImGuiTreeNodeFlags_NoAutoOpenOnLog  = 1 SHL 4;
    ImGuiTreeNodeFlags_DefaultOpen      = 1 SHL 5;
    ImGuiTreeNodeFlags_OpenOnDoubleClick= 1 SHL 6;
    ImGuiTreeNodeFlags_OpenOnArrow      = 1 SHL 7;
    ImGuiTreeNodeFlags_Leaf             = 1 SHL 8;
    ImGuiTreeNodeFlags_Bullet           = 1 SHL 9;
    ImGuiTreeNodeFlags_FramePadding     = 1 SHL 10;
    ImGuiTreeNodeFlags_SpanAvailWidth   = 1 SHL 11;
    ImGuiTreeNodeFlags_SpanFullWidth    = 1 SHL 12;
    ImGuiTreeNodeFlags_SpanAllColumns   = 1 SHL 13;
    ImGuiTreeNodeFlags_NavLeftJumpsBackHere = 1 SHL 14;
    ImGuiTreeNodeFlags_CollapsingHeader = ImGuiTreeNodeFlags_Framed OR ImGuiTreeNodeFlags_NoTreePushOnOpen OR ImGuiTreeNodeFlags_NoAutoOpenOnLog;

{ ============================================================
  ImGuiPopupFlags
  ============================================================ }
const
    ImGuiPopupFlags_None                    = 0;
    ImGuiPopupFlags_MouseButtonLeft         = 0;
    ImGuiPopupFlags_MouseButtonRight        = 1;
    ImGuiPopupFlags_MouseButtonMiddle       = 2;
    ImGuiPopupFlags_NoOpenOverExistingPopup = 1 SHL 5;
    ImGuiPopupFlags_NoOpenOverItems         = 1 SHL 6;
    ImGuiPopupFlags_AnyPopupId              = 1 SHL 7;
    ImGuiPopupFlags_AnyPopupLevel           = 1 SHL 8;
    ImGuiPopupFlags_AnyPopup                = ImGuiPopupFlags_AnyPopupId OR ImGuiPopupFlags_AnyPopupLevel;

{ ============================================================
  ImGuiSelectableFlags
  ============================================================ }
const
    ImGuiSelectableFlags_None             = 0;
    ImGuiSelectableFlags_DontClosePopups  = 1 SHL 0;
    ImGuiSelectableFlags_SpanAllColumns   = 1 SHL 1;
    ImGuiSelectableFlags_AllowDoubleClick = 1 SHL 2;
    ImGuiSelectableFlags_Disabled         = 1 SHL 3;
    ImGuiSelectableFlags_AllowOverlap     = 1 SHL 4;

{ ============================================================
  ImGuiComboFlags
  ============================================================ }
const
    ImGuiComboFlags_None            = 0;
    ImGuiComboFlags_PopupAlignLeft  = 1 SHL 0;
    ImGuiComboFlags_HeightSmall     = 1 SHL 1;
    ImGuiComboFlags_HeightRegular   = 1 SHL 2;
    ImGuiComboFlags_HeightLarge     = 1 SHL 3;
    ImGuiComboFlags_HeightLargest   = 1 SHL 4;
    ImGuiComboFlags_NoArrowButton   = 1 SHL 5;
    ImGuiComboFlags_NoPreview       = 1 SHL 6;
    ImGuiComboFlags_WidthFitPreview = 1 SHL 7;
    ImGuiComboFlags_HeightMask      = ImGuiComboFlags_HeightSmall OR ImGuiComboFlags_HeightRegular OR ImGuiComboFlags_HeightLarge OR ImGuiComboFlags_HeightLargest;

{ ============================================================
  ImGuiTabBarFlags / ImGuiTabItemFlags
  ============================================================ }
const
    ImGuiTabBarFlags_None                          = 0;
    ImGuiTabBarFlags_Reorderable                   = 1 SHL 0;
    ImGuiTabBarFlags_AutoSelectNewTabs             = 1 SHL 1;
    ImGuiTabBarFlags_TabListPopupButton            = 1 SHL 2;
    ImGuiTabBarFlags_NoCloseWithMiddleMouseButton  = 1 SHL 3;
    ImGuiTabBarFlags_NoTabListScrollingButtons     = 1 SHL 4;
    ImGuiTabBarFlags_NoTooltip                     = 1 SHL 5;
    ImGuiTabBarFlags_DrawSelectedOverline          = 1 SHL 6;
    ImGuiTabBarFlags_FittingPolicyResizeDown       = 1 SHL 7;
    ImGuiTabBarFlags_FittingPolicyScroll           = 1 SHL 8;

    ImGuiTabItemFlags_None                         = 0;
    ImGuiTabItemFlags_UnsavedDocument              = 1 SHL 0;
    ImGuiTabItemFlags_SetSelected                  = 1 SHL 1;
    ImGuiTabItemFlags_NoCloseWithMiddleMouseButton = 1 SHL 2;
    ImGuiTabItemFlags_NoPushId                     = 1 SHL 3;
    ImGuiTabItemFlags_NoTooltip                    = 1 SHL 4;
    ImGuiTabItemFlags_NoReorder                    = 1 SHL 5;
    ImGuiTabItemFlags_Leading                      = 1 SHL 6;
    ImGuiTabItemFlags_Trailing                     = 1 SHL 7;
    ImGuiTabItemFlags_NoAssumedClosure             = 1 SHL 8;

{ ============================================================
  ImGuiTableFlags
  ============================================================ }
const
    ImGuiTableFlags_None                  = 0;
    ImGuiTableFlags_Resizable             = 1 SHL 0;
    ImGuiTableFlags_Reorderable           = 1 SHL 1;
    ImGuiTableFlags_Hideable              = 1 SHL 2;
    ImGuiTableFlags_Sortable              = 1 SHL 3;
    ImGuiTableFlags_NoSavedSettings       = 1 SHL 4;
    ImGuiTableFlags_ContextMenuInBody     = 1 SHL 5;
    ImGuiTableFlags_RowBg                 = 1 SHL 6;
    ImGuiTableFlags_BordersInnerH         = 1 SHL 7;
    ImGuiTableFlags_BordersOuterH         = 1 SHL 8;
    ImGuiTableFlags_BordersInnerV         = 1 SHL 9;
    ImGuiTableFlags_BordersOuterV         = 1 SHL 10;
    ImGuiTableFlags_BordersH              = ImGuiTableFlags_BordersInnerH OR ImGuiTableFlags_BordersOuterH;
    ImGuiTableFlags_BordersV              = ImGuiTableFlags_BordersInnerV OR ImGuiTableFlags_BordersOuterV;
    ImGuiTableFlags_BordersInner          = ImGuiTableFlags_BordersInnerH OR ImGuiTableFlags_BordersInnerV;
    ImGuiTableFlags_BordersOuter          = ImGuiTableFlags_BordersOuterH OR ImGuiTableFlags_BordersOuterV;
    ImGuiTableFlags_Borders               = ImGuiTableFlags_BordersInner OR ImGuiTableFlags_BordersOuter;
    ImGuiTableFlags_NoBordersInBody       = 1 SHL 11;
    ImGuiTableFlags_NoBordersInBodyUntilResize = 1 SHL 12;
    ImGuiTableFlags_SizingFixedFit        = 1 SHL 13;
    ImGuiTableFlags_SizingFixedSame       = 2 SHL 13;
    ImGuiTableFlags_SizingStretchProp     = 3 SHL 13;
    ImGuiTableFlags_SizingStretchSame     = 4 SHL 13;
    ImGuiTableFlags_NoHostExtendX         = 1 SHL 16;
    ImGuiTableFlags_NoHostExtendY         = 1 SHL 17;
    ImGuiTableFlags_NoKeepColumnsVisible  = 1 SHL 18;
    ImGuiTableFlags_PreciseWidths         = 1 SHL 19;
    ImGuiTableFlags_NoClip                = 1 SHL 20;
    ImGuiTableFlags_PadOuterX             = 1 SHL 21;
    ImGuiTableFlags_NoPadOuterX           = 1 SHL 22;
    ImGuiTableFlags_NoPadInnerX           = 1 SHL 23;
    ImGuiTableFlags_ScrollX               = 1 SHL 24;
    ImGuiTableFlags_ScrollY               = 1 SHL 25;
    ImGuiTableFlags_SortMulti             = 1 SHL 26;
    ImGuiTableFlags_SortTristate          = 1 SHL 27;
    ImGuiTableFlags_HighlightHoveredColumn= 1 SHL 28;

    ImGuiTableColumnFlags_None            = 0;
    ImGuiTableColumnFlags_Disabled        = 1 SHL 0;
    ImGuiTableColumnFlags_DefaultHide     = 1 SHL 1;
    ImGuiTableColumnFlags_DefaultSort     = 1 SHL 2;
    ImGuiTableColumnFlags_WidthStretch    = 1 SHL 3;
    ImGuiTableColumnFlags_WidthFixed      = 1 SHL 4;
    ImGuiTableColumnFlags_NoResize        = 1 SHL 5;
    ImGuiTableColumnFlags_NoReorder       = 1 SHL 6;
    ImGuiTableColumnFlags_NoHide          = 1 SHL 7;
    ImGuiTableColumnFlags_NoClip          = 1 SHL 8;
    ImGuiTableColumnFlags_NoSort          = 1 SHL 9;
    ImGuiTableColumnFlags_NoSortAscending = 1 SHL 10;
    ImGuiTableColumnFlags_NoSortDescending= 1 SHL 11;
    ImGuiTableColumnFlags_NoHeaderLabel   = 1 SHL 12;
    ImGuiTableColumnFlags_NoHeaderWidth   = 1 SHL 13;
    ImGuiTableColumnFlags_PreferSortAscending  = 1 SHL 14;
    ImGuiTableColumnFlags_PreferSortDescending = 1 SHL 15;
    ImGuiTableColumnFlags_IndentEnable    = 1 SHL 16;
    ImGuiTableColumnFlags_IndentDisable   = 1 SHL 17;
    ImGuiTableColumnFlags_AngledHeader    = 1 SHL 18;

    ImGuiTableRowFlags_None               = 0;
    ImGuiTableRowFlags_Headers            = 1 SHL 0;

    ImGuiTableBgTarget_None               = 0;
    ImGuiTableBgTarget_RowBg0             = 1;
    ImGuiTableBgTarget_RowBg1             = 2;
    ImGuiTableBgTarget_CellBg             = 3;

{ ============================================================
  ImGuiColorEditFlags
  ============================================================ }
const
    ImGuiColorEditFlags_None           = 0;
    ImGuiColorEditFlags_NoAlpha        = 1 SHL 1;
    ImGuiColorEditFlags_NoPicker       = 1 SHL 2;
    ImGuiColorEditFlags_NoOptions      = 1 SHL 3;
    ImGuiColorEditFlags_NoSmallPreview = 1 SHL 4;
    ImGuiColorEditFlags_NoInputs       = 1 SHL 5;
    ImGuiColorEditFlags_NoTooltip      = 1 SHL 6;
    ImGuiColorEditFlags_NoLabel        = 1 SHL 7;
    ImGuiColorEditFlags_NoSidePreview  = 1 SHL 8;
    ImGuiColorEditFlags_NoDragDrop     = 1 SHL 9;
    ImGuiColorEditFlags_NoBorder       = 1 SHL 10;
    ImGuiColorEditFlags_AlphaBar       = 1 SHL 16;
    ImGuiColorEditFlags_AlphaPreview   = 1 SHL 17;
    ImGuiColorEditFlags_AlphaPreviewHalf = 1 SHL 18;
    ImGuiColorEditFlags_HDR            = 1 SHL 19;
    ImGuiColorEditFlags_DisplayRGB     = 1 SHL 20;
    ImGuiColorEditFlags_DisplayHSV     = 1 SHL 21;
    ImGuiColorEditFlags_DisplayHex     = 1 SHL 22;
    ImGuiColorEditFlags_Uint8          = 1 SHL 23;
    ImGuiColorEditFlags_Float          = 1 SHL 24;
    ImGuiColorEditFlags_PickerHueBar   = 1 SHL 25;
    ImGuiColorEditFlags_PickerHueWheel = 1 SHL 26;
    ImGuiColorEditFlags_InputRGB       = 1 SHL 27;
    ImGuiColorEditFlags_InputHSV       = 1 SHL 28;

{ ============================================================
  ImGuiSliderFlags
  ============================================================ }
const
    ImGuiSliderFlags_None            = 0;
    ImGuiSliderFlags_AlwaysClamp     = 1 SHL 4;
    ImGuiSliderFlags_Logarithmic     = 1 SHL 5;
    ImGuiSliderFlags_NoRoundToFormat = 1 SHL 6;
    ImGuiSliderFlags_NoInput         = 1 SHL 7;
    ImGuiSliderFlags_WrapAround      = 1 SHL 8;

{ ============================================================
  ImGuiMouseButton / ImGuiMouseCursor
  ============================================================ }
const
    ImGuiMouseButton_Left   = 0;
    ImGuiMouseButton_Right  = 1;
    ImGuiMouseButton_Middle = 2;

    ImGuiMouseCursor_None       = -1;
    ImGuiMouseCursor_Arrow      = 0;
    ImGuiMouseCursor_TextInput  = 1;
    ImGuiMouseCursor_ResizeAll  = 2;
    ImGuiMouseCursor_ResizeNS   = 3;
    ImGuiMouseCursor_ResizeEW   = 4;
    ImGuiMouseCursor_ResizeNESW = 5;
    ImGuiMouseCursor_ResizeNWSE = 6;
    ImGuiMouseCursor_Hand       = 7;
    ImGuiMouseCursor_NotAllowed = 8;

{ ============================================================
  ImGuiCond
  ============================================================ }
const
    ImGuiCond_None        = 0;
    ImGuiCond_Always      = 1 SHL 0;
    ImGuiCond_Once        = 1 SHL 1;
    ImGuiCond_FirstUseEver= 1 SHL 2;
    ImGuiCond_Appearing   = 1 SHL 3;

{ ============================================================
  ImGuiDir
  ============================================================ }
const
    ImGuiDir_None  = -1;
    ImGuiDir_Left  = 0;
    ImGuiDir_Right = 1;
    ImGuiDir_Up    = 2;
    ImGuiDir_Down  = 3;

{ ============================================================
  ImGuiCol (style colors)
  ============================================================ }
const
    ImGuiCol_Text                  = 0;
    ImGuiCol_TextDisabled          = 1;
    ImGuiCol_WindowBg              = 2;
    ImGuiCol_ChildBg               = 3;
    ImGuiCol_PopupBg               = 4;
    ImGuiCol_Border                = 5;
    ImGuiCol_BorderShadow          = 6;
    ImGuiCol_FrameBg               = 7;
    ImGuiCol_FrameBgHovered        = 8;
    ImGuiCol_FrameBgActive         = 9;
    ImGuiCol_TitleBg               = 10;
    ImGuiCol_TitleBgActive         = 11;
    ImGuiCol_TitleBgCollapsed      = 12;
    ImGuiCol_MenuBarBg             = 13;
    ImGuiCol_ScrollbarBg           = 14;
    ImGuiCol_ScrollbarGrab         = 15;
    ImGuiCol_ScrollbarGrabHovered  = 16;
    ImGuiCol_ScrollbarGrabActive   = 17;
    ImGuiCol_CheckMark             = 18;
    ImGuiCol_SliderGrab            = 19;
    ImGuiCol_SliderGrabActive      = 20;
    ImGuiCol_Button                = 21;
    ImGuiCol_ButtonHovered         = 22;
    ImGuiCol_ButtonActive          = 23;
    ImGuiCol_Header                = 24;
    ImGuiCol_HeaderHovered         = 25;
    ImGuiCol_HeaderActive          = 26;
    ImGuiCol_Separator             = 27;
    ImGuiCol_SeparatorHovered      = 28;
    ImGuiCol_SeparatorActive       = 29;
    ImGuiCol_ResizeGrip            = 30;
    ImGuiCol_ResizeGripHovered     = 31;
    ImGuiCol_ResizeGripActive      = 32;
    ImGuiCol_Tab                   = 33;
    ImGuiCol_TabHovered            = 34;
    ImGuiCol_TabSelected           = 35;
    ImGuiCol_TabSelectedOverline   = 36;
    ImGuiCol_TabDimmed             = 37;
    ImGuiCol_TabDimmedSelected     = 38;
    ImGuiCol_TabDimmedSelectedOverline = 39;
    ImGuiCol_PlotLines             = 40;
    ImGuiCol_PlotLinesHovered      = 41;
    ImGuiCol_PlotHistogram         = 42;
    ImGuiCol_PlotHistogramHovered  = 43;
    ImGuiCol_TableHeaderBg         = 44;
    ImGuiCol_TableBorderStrong     = 45;
    ImGuiCol_TableBorderLight      = 46;
    ImGuiCol_TableRowBg            = 47;
    ImGuiCol_TableRowBgAlt         = 48;
    ImGuiCol_TextLink              = 49;
    ImGuiCol_TextSelectedBg        = 50;
    ImGuiCol_DragDropTarget        = 51;
    ImGuiCol_NavHighlight          = 52;
    ImGuiCol_NavWindowingHighlight = 53;
    ImGuiCol_NavWindowingDimBg     = 54;
    ImGuiCol_ModalWindowDimBg      = 55;
    ImGuiCol_COUNT                 = 56;

{ ============================================================
  ImGuiStyleVar
  ============================================================ }
const
    ImGuiStyleVar_Alpha                  = 0;
    ImGuiStyleVar_DisabledAlpha          = 1;
    ImGuiStyleVar_WindowPadding          = 2;
    ImGuiStyleVar_WindowRounding         = 3;
    ImGuiStyleVar_WindowBorderSize       = 4;
    ImGuiStyleVar_WindowMinSize          = 5;
    ImGuiStyleVar_WindowTitleAlign       = 6;
    ImGuiStyleVar_ChildRounding          = 7;
    ImGuiStyleVar_ChildBorderSize        = 8;
    ImGuiStyleVar_PopupRounding          = 9;
    ImGuiStyleVar_PopupBorderSize        = 10;
    ImGuiStyleVar_FramePadding           = 11;
    ImGuiStyleVar_FrameRounding          = 12;
    ImGuiStyleVar_FrameBorderSize        = 13;
    ImGuiStyleVar_ItemSpacing            = 14;
    ImGuiStyleVar_ItemInnerSpacing       = 15;
    ImGuiStyleVar_IndentSpacing          = 16;
    ImGuiStyleVar_CellPadding            = 17;
    ImGuiStyleVar_ScrollbarSize          = 18;
    ImGuiStyleVar_ScrollbarRounding      = 19;
    ImGuiStyleVar_GrabMinSize            = 20;
    ImGuiStyleVar_GrabRounding           = 21;
    ImGuiStyleVar_TabRounding            = 22;
    ImGuiStyleVar_TabBorderSize          = 23;
    ImGuiStyleVar_ButtonTextAlign        = 24;
    ImGuiStyleVar_SelectableTextAlign    = 25;
    ImGuiStyleVar_SeparatorTextBorderSize= 26;
    ImGuiStyleVar_SeparatorTextAlign     = 27;
    ImGuiStyleVar_SeparatorTextPadding   = 28;

{ ============================================================
  ImGuiFocusedFlags / ImGuiHoveredFlags
  ============================================================ }
const
    ImGuiFocusedFlags_None                = 0;
    ImGuiFocusedFlags_ChildWindows        = 1 SHL 0;
    ImGuiFocusedFlags_RootWindow          = 1 SHL 1;
    ImGuiFocusedFlags_AnyWindow           = 1 SHL 2;
    ImGuiFocusedFlags_NoPopupHierarchy    = 1 SHL 3;
    ImGuiFocusedFlags_RootAndChildWindows = ImGuiFocusedFlags_RootWindow OR ImGuiFocusedFlags_ChildWindows;

    ImGuiHoveredFlags_None                         = 0;
    ImGuiHoveredFlags_ChildWindows                 = 1 SHL 0;
    ImGuiHoveredFlags_RootWindow                   = 1 SHL 1;
    ImGuiHoveredFlags_AnyWindow                    = 1 SHL 2;
    ImGuiHoveredFlags_NoPopupHierarchy             = 1 SHL 3;
    ImGuiHoveredFlags_AllowWhenBlockedByPopup      = 1 SHL 5;
    ImGuiHoveredFlags_AllowWhenBlockedByActiveItem = 1 SHL 7;
    ImGuiHoveredFlags_AllowWhenOverlappedByItem    = 1 SHL 8;
    ImGuiHoveredFlags_AllowWhenOverlappedByWindow  = 1 SHL 9;
    ImGuiHoveredFlags_AllowWhenDisabled            = 1 SHL 10;
    ImGuiHoveredFlags_NoNavOverride                = 1 SHL 11;
    ImGuiHoveredFlags_AllowWhenOverlapped          = ImGuiHoveredFlags_AllowWhenOverlappedByItem OR ImGuiHoveredFlags_AllowWhenOverlappedByWindow;
    ImGuiHoveredFlags_RectOnly                     = ImGuiHoveredFlags_AllowWhenBlockedByPopup OR ImGuiHoveredFlags_AllowWhenBlockedByActiveItem OR ImGuiHoveredFlags_AllowWhenOverlapped;
    ImGuiHoveredFlags_RootAndChildWindows          = ImGuiHoveredFlags_RootWindow OR ImGuiHoveredFlags_ChildWindows;
    ImGuiHoveredFlags_ForTooltip                   = 1 SHL 12;
    ImGuiHoveredFlags_Stationary                   = 1 SHL 13;
    ImGuiHoveredFlags_DelayNone                    = 1 SHL 14;
    ImGuiHoveredFlags_DelayShort                   = 1 SHL 15;
    ImGuiHoveredFlags_DelayNormal                  = 1 SHL 16;
    ImGuiHoveredFlags_NoSharedDelay                = 1 SHL 17;

{ ============================================================
  ImGuiDragDropFlags
  ============================================================ }
const
    ImGuiDragDropFlags_None                     = 0;
    ImGuiDragDropFlags_SourceNoPreviewTooltip   = 1 SHL 0;
    ImGuiDragDropFlags_SourceNoDisableHover     = 1 SHL 1;
    ImGuiDragDropFlags_SourceNoHoldToOpenOthers = 1 SHL 2;
    ImGuiDragDropFlags_SourceAllowNullID        = 1 SHL 3;
    ImGuiDragDropFlags_SourceExtern             = 1 SHL 4;
    ImGuiDragDropFlags_PayloadAutoExpire        = 1 SHL 5;
    ImGuiDragDropFlags_PayloadNoCrossContext    = 1 SHL 6;
    ImGuiDragDropFlags_PayloadNoCrossProcess    = 1 SHL 7;
    ImGuiDragDropFlags_AcceptBeforeDelivery     = 1 SHL 10;
    ImGuiDragDropFlags_AcceptNoDrawDefaultRect  = 1 SHL 11;
    ImGuiDragDropFlags_AcceptNoPreviewTooltip   = 1 SHL 12;
    ImGuiDragDropFlags_AcceptPeekOnly           = ImGuiDragDropFlags_AcceptBeforeDelivery OR ImGuiDragDropFlags_AcceptNoDrawDefaultRect;

{ ============================================================
  ImGuiDataType
  ============================================================ }
const
    ImGuiDataType_S8     = 0;
    ImGuiDataType_U8     = 1;
    ImGuiDataType_S16    = 2;
    ImGuiDataType_U16    = 3;
    ImGuiDataType_S32    = 4;
    ImGuiDataType_U32    = 5;
    ImGuiDataType_S64    = 6;
    ImGuiDataType_U64    = 7;
    ImGuiDataType_Float  = 8;
    ImGuiDataType_Double = 9;

{ ============================================================
  ImGuiSortDirection
  ============================================================ }
const
    ImGuiSortDirection_None       = 0;
    ImGuiSortDirection_Ascending  = 1;
    ImGuiSortDirection_Descending = 2;

{ ============================================================
  ImGuiKey (common physical keys)
  ============================================================ }
const
    ImGuiKey_None           = 0;
    ImGuiKey_Tab            = 512;
    ImGuiKey_LeftArrow      = 513;
    ImGuiKey_RightArrow     = 514;
    ImGuiKey_UpArrow        = 515;
    ImGuiKey_DownArrow      = 516;
    ImGuiKey_PageUp         = 517;
    ImGuiKey_PageDown       = 518;
    ImGuiKey_Home           = 519;
    ImGuiKey_End            = 520;
    ImGuiKey_Insert         = 521;
    ImGuiKey_Delete         = 522;
    ImGuiKey_Backspace      = 523;
    ImGuiKey_Space          = 524;
    ImGuiKey_Enter          = 525;
    ImGuiKey_Escape         = 526;
    ImGuiKey_LeftCtrl       = 527;
    ImGuiKey_LeftShift      = 528;
    ImGuiKey_LeftAlt        = 529;
    ImGuiKey_LeftSuper      = 530;
    ImGuiKey_RightCtrl      = 531;
    ImGuiKey_RightShift     = 532;
    ImGuiKey_RightAlt       = 533;
    ImGuiKey_RightSuper     = 534;
    ImGuiKey_Menu           = 535;
    ImGuiKey_0 = 536; ImGuiKey_1 = 537; ImGuiKey_2 = 538; ImGuiKey_3 = 539;
    ImGuiKey_4 = 540; ImGuiKey_5 = 541; ImGuiKey_6 = 542; ImGuiKey_7 = 543;
    ImGuiKey_8 = 544; ImGuiKey_9 = 545;
    ImGuiKey_A = 546; ImGuiKey_B = 547; ImGuiKey_C = 548; ImGuiKey_D = 549;
    ImGuiKey_E = 550; ImGuiKey_F = 551; ImGuiKey_G = 552; ImGuiKey_H = 553;
    ImGuiKey_I = 554; ImGuiKey_J = 555; ImGuiKey_K = 556; ImGuiKey_L = 557;
    ImGuiKey_M = 558; ImGuiKey_N = 559; ImGuiKey_O = 560; ImGuiKey_P = 561;
    ImGuiKey_Q = 562; ImGuiKey_R = 563; ImGuiKey_S = 564; ImGuiKey_T = 565;
    ImGuiKey_U = 566; ImGuiKey_V = 567; ImGuiKey_W = 568; ImGuiKey_X = 569;
    ImGuiKey_Y = 570; ImGuiKey_Z = 571;
    ImGuiKey_F1  = 572; ImGuiKey_F2  = 573; ImGuiKey_F3  = 574; ImGuiKey_F4  = 575;
    ImGuiKey_F5  = 576; ImGuiKey_F6  = 577; ImGuiKey_F7  = 578; ImGuiKey_F8  = 579;
    ImGuiKey_F9  = 580; ImGuiKey_F10 = 581; ImGuiKey_F11 = 582; ImGuiKey_F12 = 583;
    ImGuiKey_ModCtrl  = 641;
    ImGuiKey_ModShift = 642;
    ImGuiKey_ModAlt   = 643;
    ImGuiKey_ModSuper = 644;

{ ============================================================
  ImGuiConfigFlags / ImGuiBackendFlags
  ============================================================ }
const
    ImGuiConfigFlags_None                 = 0;
    ImGuiConfigFlags_NavEnableKeyboard    = 1 SHL 0;
    ImGuiConfigFlags_NavEnableGamepad     = 1 SHL 1;
    ImGuiConfigFlags_NavEnableSetMousePos = 1 SHL 2;
    ImGuiConfigFlags_NavNoCaptureKeyboard = 1 SHL 3;
    ImGuiConfigFlags_NoMouse              = 1 SHL 4;
    ImGuiConfigFlags_NoMouseCursorChange  = 1 SHL 5;
    ImGuiConfigFlags_IsSRGB               = 1 SHL 20;
    ImGuiConfigFlags_IsTouchScreen        = 1 SHL 21;

    ImGuiBackendFlags_None               = 0;
    ImGuiBackendFlags_HasGamepad         = 1 SHL 0;
    ImGuiBackendFlags_HasMouseCursors    = 1 SHL 1;
    ImGuiBackendFlags_HasSetMousePos     = 1 SHL 2;
    ImGuiBackendFlags_RendererHasVtxOffset = 1 SHL 3;
    ImGuiBackendFlags_RendererHasTextures  = 1 SHL 4;

implementation
end.
