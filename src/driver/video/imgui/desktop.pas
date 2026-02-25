{
    Driver->Video->Imgui->Desktop
    Full desktop environment built with Dear ImGui.

    Provides:
      - Gradient wallpaper background
      - Polished taskbar with app buttons, system tray and clock
      - Start menu with categorized launcher
      - Custom-drawn desktop icons via ImDrawList
      - Draggable windowed apps:
          * System Info (tabbed)
          * Terminal / Console (dark themed)
          * File Browser (tree-style)
          * Task Manager (with live stats)

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit desktop;

interface

uses
    imgui, imguitypes,
    RTC, cpu, multiboot,
    vfs, hashmap, strings, lmemorymanager,
    scheduler, pmemorymanager,
    video, console, tracer, terminal;

{ Call once per frame from the kernel render loop (between new_frame and render) }
procedure desktop_frame;

{ Initialise desktop state }
procedure desktop_init;

implementation

{ ============================================================
  Constants
  ============================================================ }
const
    TASKBAR_HEIGHT   = 36;
    STARTMENU_W      = 260;
    STARTMENU_H      = 340;

    { Terminal ring-buffer }
    TERM_MAX_LINES   = 256;
    TERM_LINE_LEN    = 128;
    TERM_INPUT_LEN   = 256;

    { File browser }
    FB_PATH_LEN      = 512;

    { Icon layout }
    ICON_GRID_X      = 80;
    ICON_GRID_Y      = 90;
    ICON_START_X     = 32;
    ICON_START_Y     = 20;

{ ============================================================
  App visibility state
  ============================================================ }
var
    show_sysinfo    : boolean = false;
    show_terminal   : boolean = false;
    show_filebrowser: boolean = false;
    show_taskmgr    : boolean = false;
    show_demo       : boolean = false;
    show_start_menu : boolean = false;

    screen_w        : single = 0;
    screen_h        : single = 0;

    { ---- Terminal state ---- }
    term_lines      : array[0..TERM_MAX_LINES-1] of array[0..TERM_LINE_LEN-1] of char;
    term_line_count : uint32 = 0;
    term_input      : array[0..TERM_INPUT_LEN-1] of char;
    term_scroll_bottom : boolean = true;

    { ---- File browser state ---- }
    fb_path         : array[0..FB_PATH_LEN-1] of char;
    fb_path_inited  : boolean = false;

    { ---- Animation frame counter ---- }
    frame_count     : uint32 = 0;

{ ============================================================
  Helpers
  ============================================================ }
function ImVec2(x, y: single): TImVec2;
begin
    ImVec2.x := x;
    ImVec2.y := y;
end;

function ImVec4(x, y, z, w: single): TImVec4;
begin
    ImVec4.x := x;
    ImVec4.y := y;
    ImVec4.z := z;
    ImVec4.w := w;
end;

{ Quick float-to-int truncation (x87 FISTTP) }
function ftrunc(f: Single): sint32;
var r: sint32;
begin
    asm
        FLD    DWORD [f]
        FISTTP DWORD [r]
    end;
    ftrunc := r;
end;

{ Pack RGBA into ImU32 (ABGR byte order for ImGui) }
function IM_COL32(r, g, b, a: uint8): ImU32;
begin
    IM_COL32 := uint32(a) SHL 24 or uint32(b) SHL 16 or uint32(g) SHL 8 or uint32(r);
end;

{ Quick integer-to-string into a stack buffer.  Returns pointer into buf. }
function i2s(val: uint32; var buf: array of char): pchar;
var
    i, d: uint32;
    tmp: array[0..11] of char;
begin
    if val = 0 then begin
        buf[0] := '0'; buf[1] := #0;
        i2s := @buf[0];
        exit;
    end;
    i := 0;
    while val > 0 do begin
        tmp[i] := char(ord('0') + (val mod 10));
        val := val div 10;
        inc(i);
    end;
    for d := 0 to i - 1 do
        buf[d] := tmp[i - 1 - d];
    buf[i] := #0;
    i2s := @buf[0];
end;

{ Two-digit zero-padded }
procedure pad2(val: uint8; var buf: array of char; offset: uint32);
begin
    buf[offset]     := char(ord('0') + (val div 10));
    buf[offset + 1] := char(ord('0') + (val mod 10));
end;

{ Simple pchar copy into fixed buffer }
procedure pcopy(src: pchar; var dst: array of char; max: uint32);
var i: uint32;
begin
    i := 0;
    while (src[i] <> #0) and (i < max - 1) do begin
        dst[i] := src[i];
        inc(i);
    end;
    dst[i] := #0;
end;

{ Simple pchar length }
function plen(s: pchar): uint32;
var i: uint32;
begin
    i := 0;
    while s[i] <> #0 do inc(i);
    plen := i;
end;

{ Simple string compare }
function pstreq(a, b: pchar): boolean;
var i: uint32;
begin
    i := 0;
    while (a[i] <> #0) and (b[i] <> #0) and (a[i] = b[i]) do inc(i);
    pstreq := (a[i] = b[i]);
end;

{ ============================================================
  Terminal
  ============================================================ }

{ Append a line to the terminal ring buffer }
procedure term_add_line(s: pchar);
var
    i, len: uint32;
begin
    if term_line_count < TERM_MAX_LINES then begin
        len := plen(s);
        if len >= TERM_LINE_LEN then len := TERM_LINE_LEN - 1;
        if len > 0 then
            for i := 0 to len - 1 do
                term_lines[term_line_count][i] := s[i];
        term_lines[term_line_count][len] := #0;
        inc(term_line_count);
    end;
end;

{ Execute a terminal command - dispatches to registered terminal commands }
procedure term_exec(cmd: pchar);
var
    buf: array[0..TERM_LINE_LEN-1] of char;
    cmdbuf: TCommandBuffer;
    params: PParamList;
    i, j: uint32;
    found: boolean;
    uppera, upperb: pchar;
begin
    { Echo the command with prompt }
    buf[0] := '~'; buf[1] := ' ';
    pcopy(cmd, buf[2], TERM_LINE_LEN - 3);
    i := 2;
    while buf[i] <> #0 do inc(i);
    buf[i] := #0;
    term_add_line(@buf[0]);

    if (cmd[0] = #0) then exit;

    { Built-in: clear - must be special since clearWND is a no-op in capture }
    uppera := stringToUpper(cmd);
    if stringEquals(uppera, 'CLEAR') then begin
        kfree(void(uppera));
        term_line_count := 0;
        exit;
    end;
    kfree(void(uppera));

    { Convert input string to TCommandBuffer format }
    for i := 0 to 1023 do cmdbuf[i] := 0;
    i := 0;
    while (cmd[i] <> #0) and (i < 1023) do begin
        cmdbuf[i] := byte(cmd[i]);
        inc(i);
    end;

    { Parse into param list }
    params := terminal.getParams(cmdbuf);
    found := false;

    if params^.param <> nil then begin
        uppera := stringToUpper(params^.param);

        { Look up in registered commands (case-insensitive) }
        for i := 0 to 65534 do begin
            if terminal.Commands[i].registered then begin
                upperb := stringToUpper(terminal.Commands[i].command);
                if stringEquals(uppera, upperb) then begin
                    { Set up output capture to redirect console writes to ImGui terminal }
                    console.WND_CaptureActive := true;
                    console.WND_CaptureHWND := terminal.getTerminalHWND;
                    console.WND_CaptureCallback := @term_add_line;
                    console.WND_CaptureBufIdx := 0;
                    console.WND_CaptureBuf[0] := #0;

                    { Execute the registered command }
                    terminal.Commands[i].method(params);

                    { Flush remaining output and disable capture }
                    console.flushCapture;
                    console.WND_CaptureActive := false;

                    found := true;
                end;
                kfree(void(upperb));
                if found then break;
            end;
        end;

        kfree(void(uppera));
    end;

    { Free the param list }
    terminal.freeParams(params);

    { Command not found }
    if not found then
        term_add_line('  Command not found. Type "help" for commands.');
end;

{ ============================================================
  Style - applied once via C bridge
  ============================================================ }
procedure imgui_apply_desktop_style; cdecl; external;

{ ============================================================
  Background - gradient wallpaper
  ============================================================ }
procedure draw_wallpaper;
var
    dl: PImDrawList;
    col_top, col_mid, col_bot: ImU32;
    mid_y: single;
begin
    dl := igGetBackgroundDrawList(nil);
    if dl = nil then exit;

    { Three-band gradient: deep navy -> dark indigo -> near black }
    col_top := IM_COL32(12, 18, 40, 255);
    col_mid := IM_COL32(18, 14, 36, 255);
    col_bot := IM_COL32(8, 8, 16, 255);

    mid_y := screen_h * 0.45;

    { Top half }
    ImDrawList_AddRectFilledMultiColor(dl,
        ImVec2(0, 0), ImVec2(screen_w, mid_y),
        col_top, col_top, col_mid, col_mid);

    { Bottom half }
    ImDrawList_AddRectFilledMultiColor(dl,
        ImVec2(0, mid_y), ImVec2(screen_w, screen_h - TASKBAR_HEIGHT),
        col_mid, col_mid, col_bot, col_bot);

end;

{ ============================================================
  Desktop Icons - custom drawn with DrawList
  ============================================================ }
procedure draw_desktop_icon(dl: PImDrawList; cx, cy: single; label_text: pchar;
    icon_r, icon_g, icon_b: uint8; glyph: char; var target: boolean);
var
    icon_id: array[0..31] of char;
    hovered: boolean;
    bg_col, glyph_col, label_col: ImU32;
    glyph_str: array[0..1] of char;
begin
    { Invisible button for click/hover detection }
    igSetCursorScreenPos(ImVec2(cx - 36, cy - 36));

    { Unique ID from label }
    icon_id[0] := '#'; icon_id[1] := '#'; icon_id[2] := 'I';
    pcopy(label_text, icon_id[3], 28);

    if igInvisibleButton(@icon_id[0], ImVec2(72, 72 + 16), 0) then
        target := true;

    hovered := igIsItemHovered(0);

    { Background rounded rect - glass effect }
    if hovered then
        bg_col := IM_COL32(icon_r, icon_g, icon_b, 60)
    else
        bg_col := IM_COL32(icon_r, icon_g, icon_b, 25);

    ImDrawList_AddRectFilled(dl,
        ImVec2(cx - 30, cy - 30),
        ImVec2(cx + 30, cy + 30),
        bg_col, 12.0, 0);

    { Border on hover }
    if hovered then
        ImDrawList_AddRect(dl,
            ImVec2(cx - 30, cy - 30),
            ImVec2(cx + 30, cy + 30),
            IM_COL32(icon_r, icon_g, icon_b, 120), 12.0, 0, 1.0);

    { Icon glyph (centered single char) }
    glyph_str[0] := glyph;
    glyph_str[1] := #0;
    if hovered then
        glyph_col := IM_COL32(255, 255, 255, 240)
    else
        glyph_col := IM_COL32(icon_r, icon_g, icon_b, 200);
    ImDrawList_AddText_Vec2(dl, ImVec2(cx - 3, cy - 6), glyph_col, @glyph_str[0], nil);

    { Label below }
    if hovered then
        label_col := IM_COL32(255, 255, 255, 230)
    else
        label_col := IM_COL32(200, 210, 230, 180);
    ImDrawList_AddText_Vec2(dl, ImVec2(cx - 20, cy + 34), label_col, label_text, nil);
end;

procedure draw_desktop_icons;
var
    flags: ImGuiWindowFlags;
    dl: PImDrawList;
    base_x, base_y: single;
begin
    flags := ImGuiWindowFlags_NoTitleBar or ImGuiWindowFlags_NoResize or
             ImGuiWindowFlags_NoMove or ImGuiWindowFlags_NoScrollbar or
             ImGuiWindowFlags_NoBackground or ImGuiWindowFlags_NoCollapse or
             ImGuiWindowFlags_NoNav or
             ImGuiWindowFlags_NoBringToDisplayOnFocus or
             ImGuiWindowFlags_NoFocusOnAppearing;

    igSetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always, ImVec2(0, 0));
    igSetNextWindowSize(ImVec2(screen_w, screen_h - TASKBAR_HEIGHT), ImGuiCond_Always);

    if igBegin('##Desktop', nil, flags) then begin
        dl := igGetWindowDrawList;
        base_x := ICON_START_X + 36;
        base_y := ICON_START_Y + 36;

        { Column 1 }
        draw_desktop_icon(dl, base_x, base_y,
            'System', 100, 160, 255, 'i', show_sysinfo);

        draw_desktop_icon(dl, base_x, base_y + ICON_GRID_Y,
            'Terminal', 120, 220, 140, '>', show_terminal);

        draw_desktop_icon(dl, base_x, base_y + ICON_GRID_Y * 2,
            'Files', 220, 180, 100, 'F', show_filebrowser);

        draw_desktop_icon(dl, base_x, base_y + ICON_GRID_Y * 3,
            'Tasks', 220, 120, 120, 'T', show_taskmgr);
    end;
    igEnd;
end;

{ ============================================================
  Taskbar - gradient bar with centered clock
  ============================================================ }
procedure draw_taskbar_button(label_text: pchar; is_active: boolean; window_name: pchar);
var
    col_btn, col_hover, col_active_c: TImVec4;
begin
    if is_active then begin
        col_btn     := ImVec4(0.18, 0.28, 0.52, 0.95);
        col_hover   := ImVec4(0.24, 0.38, 0.65, 1.0);
        col_active_c:= ImVec4(0.14, 0.22, 0.42, 1.0);
    end else begin
        col_btn     := ImVec4(0.10, 0.12, 0.20, 0.60);
        col_hover   := ImVec4(0.18, 0.24, 0.40, 0.80);
        col_active_c:= ImVec4(0.12, 0.16, 0.30, 0.90);
    end;

    igPushStyleColor_Vec4(ImGuiCol_Button, col_btn);
    igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, col_hover);
    igPushStyleColor_Vec4(ImGuiCol_ButtonActive, col_active_c);
    igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 4.0);

    if igButton(label_text, ImVec2(72, 26)) then begin
        if window_name <> nil then
            igSetWindowFocus_Str(window_name);
    end;

    igPopStyleVar(1);
    igPopStyleColor(3);
    igSameLine(0, 3);
end;

procedure draw_taskbar;
var
    dt: TDateTime;
    clock_buf: array[0..31] of char;
    date_buf: array[0..31] of char;
    flags: ImGuiWindowFlags;
    dl: PImDrawList;
    tb_y: single;
begin
    flags := ImGuiWindowFlags_NoTitleBar or ImGuiWindowFlags_NoResize or
             ImGuiWindowFlags_NoMove or ImGuiWindowFlags_NoScrollbar or
             ImGuiWindowFlags_NoScrollWithMouse or ImGuiWindowFlags_NoCollapse or
             ImGuiWindowFlags_NoBringToDisplayOnFocus or ImGuiWindowFlags_NoFocusOnAppearing;

    tb_y := screen_h - TASKBAR_HEIGHT;
    igSetNextWindowPos(ImVec2(0, tb_y), ImGuiCond_Always, ImVec2(0, 0));
    igSetNextWindowSize(ImVec2(screen_w, TASKBAR_HEIGHT), ImGuiCond_Always);
    igPushStyleVar_Float(ImGuiStyleVar_WindowRounding, 0.0);
    igPushStyleVar_Vec2(ImGuiStyleVar_WindowPadding, ImVec2(8, 5));
    igPushStyleColor_Vec4(ImGuiCol_WindowBg, ImVec4(0.0, 0.0, 0.0, 0.0));
    igPushStyleColor_Vec4(ImGuiCol_Border, ImVec4(0.0, 0.0, 0.0, 0.0));

    if igBegin('##Taskbar', nil, flags) then begin
        dl := igGetWindowDrawList;

        { Gradient taskbar background }
        ImDrawList_AddRectFilledMultiColor(dl,
            ImVec2(0, tb_y),
            ImVec2(screen_w, screen_h),
            IM_COL32(16, 18, 28, 240),
            IM_COL32(16, 18, 28, 240),
            IM_COL32(10, 12, 22, 250),
            IM_COL32(10, 12, 22, 250));

        { Top highlight line }
        ImDrawList_AddLine(dl,
            ImVec2(0, tb_y),
            ImVec2(screen_w, tb_y),
            IM_COL32(60, 80, 140, 80), 1.0);

        { Start / Menu button }
        igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.14, 0.32, 0.68, 1.0));
        igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, ImVec4(0.22, 0.44, 0.82, 1.0));
        igPushStyleColor_Vec4(ImGuiCol_ButtonActive, ImVec4(0.10, 0.24, 0.54, 1.0));
        igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 4.0);
        if igButton(' Asuro ', ImVec2(70, 26)) then
            show_start_menu := not show_start_menu;
        igPopStyleVar(1);
        igPopStyleColor(3);

        igSameLine(0, 10);

        { Separator }
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.30, 0.36, 0.55, 0.50));
        igTextUnformatted('|', nil);
        igPopStyleColor(1);
        igSameLine(0, 10);

        { Running app buttons }
        if show_sysinfo then
            draw_taskbar_button(' System ', true, 'System Information');
        if show_terminal then
            draw_taskbar_button('Terminal', true, 'Terminal');
        if show_filebrowser then
            draw_taskbar_button(' Files  ', true, 'File Browser');
        if show_taskmgr then
            draw_taskbar_button(' Tasks  ', true, 'Task Manager');

        { Clock - right aligned }
        dt := RTC.getDateTime;
        pad2(dt.Hours,   clock_buf, 0);
        clock_buf[2] := ':';
        pad2(dt.Minutes, clock_buf, 3);
        clock_buf[5] := ':';
        pad2(dt.Seconds, clock_buf, 6);
        clock_buf[8] := #0;

        { Date string }
        pad2(dt.Day,   date_buf, 0);
        date_buf[2] := '/';
        pad2(dt.Month, date_buf, 3);
        date_buf[5] := #0;

        { Right-aligned clock area }
        igSameLine(screen_w - 120, 0);

        { Clock background pill }
        ImDrawList_AddRectFilled(dl,
            ImVec2(screen_w - 125, tb_y + 4),
            ImVec2(screen_w - 5, tb_y + TASKBAR_HEIGHT - 4),
            IM_COL32(20, 24, 40, 180), 6.0, 0);

        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.72, 0.80, 0.95, 1.0));
        igTextUnformatted(@clock_buf[0], nil);
        igPopStyleColor(1);

        igSameLine(0, 8);
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.48, 0.54, 0.70, 0.8));
        igTextUnformatted(@date_buf[0], nil);
        igPopStyleColor(1);
    end;
    igEnd;
    igPopStyleColor(2);
    igPopStyleVar(2);
end;

{ ============================================================
  Start Menu - glass panel with grouped items
  ============================================================ }
procedure draw_start_menu_item(label_text: pchar; var target: boolean);
begin
    igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.0, 0.0, 0.0, 0.0));
    igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, ImVec4(0.20, 0.30, 0.55, 0.50));
    igPushStyleColor_Vec4(ImGuiCol_ButtonActive, ImVec4(0.16, 0.24, 0.46, 0.70));
    igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 6.0);
    igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, ImVec2(12, 6));

    if igButton(label_text, ImVec2(STARTMENU_W - 28, 0)) then begin
        target := true;
        show_start_menu := false;
    end;

    igPopStyleVar(2);
    igPopStyleColor(3);
end;

procedure draw_start_menu;
var
    flags: ImGuiWindowFlags;
    dl: PImDrawList;
    menu_x, menu_y: single;
    menu_hovered: boolean;
begin
    if not show_start_menu then exit;

    menu_hovered := false;

    flags := ImGuiWindowFlags_NoTitleBar or ImGuiWindowFlags_NoResize or
             ImGuiWindowFlags_NoMove or ImGuiWindowFlags_NoScrollbar or
             ImGuiWindowFlags_NoCollapse or ImGuiWindowFlags_NoFocusOnAppearing;

    menu_x := 4;
    menu_y := screen_h - TASKBAR_HEIGHT - STARTMENU_H - 4;

    igSetNextWindowPos(ImVec2(menu_x, menu_y), ImGuiCond_Always, ImVec2(0, 0));
    igSetNextWindowSize(ImVec2(STARTMENU_W, STARTMENU_H), ImGuiCond_Always);
    igPushStyleVar_Float(ImGuiStyleVar_WindowRounding, 10.0);
    igPushStyleVar_Vec2(ImGuiStyleVar_WindowPadding, ImVec2(14, 14));
    igPushStyleColor_Vec4(ImGuiCol_WindowBg, ImVec4(0.06, 0.07, 0.12, 0.95));
    igPushStyleColor_Vec4(ImGuiCol_Border, ImVec4(0.25, 0.32, 0.55, 0.35));

    if igBegin('##StartMenu', nil, flags) then begin
        menu_hovered := igIsWindowHovered(ImGuiHoveredFlags_AllowWhenBlockedByActiveItem);
        dl := igGetWindowDrawList;

        { Header area with accent }
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.55, 0.75, 1.0, 1.0));
        igText('  Asuro Desktop');
        igPopStyleColor(1);

        igSpacing;

        { Accent line }
        ImDrawList_AddLine(dl,
            ImVec2(menu_x + 14, menu_y + 38),
            ImVec2(menu_x + STARTMENU_W - 14, menu_y + 38),
            IM_COL32(60, 90, 160, 80), 1.0);

        igSpacing;
        igSpacing;

        { Section: Applications }
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.45, 0.52, 0.70, 0.80));
        igText('   APPLICATIONS');
        igPopStyleColor(1);
        igSpacing;

        draw_start_menu_item('   System Info', show_sysinfo);
        draw_start_menu_item('   Terminal', show_terminal);
        draw_start_menu_item('   File Browser', show_filebrowser);
        draw_start_menu_item('   Task Manager', show_taskmgr);

        igSpacing;
        igSpacing;

        { Accent line }
        ImDrawList_AddLine(dl,
            ImVec2(menu_x + 14, menu_y + STARTMENU_H - 72),
            ImVec2(menu_x + STARTMENU_W - 14, menu_y + STARTMENU_H - 72),
            IM_COL32(60, 90, 160, 50), 1.0);

        igSpacing;

        { Section: Tools }
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.45, 0.52, 0.70, 0.80));
        igText('   TOOLS');
        igPopStyleColor(1);
        igSpacing;

        draw_start_menu_item('   ImGui Demo', show_demo);
    end;
    igEnd;
    igPopStyleColor(2);
    igPopStyleVar(2);

    { Close when clicking outside the start menu }
    if igIsMouseClicked_Bool(0, false) and not menu_hovered then
        show_start_menu := false;
end;

{ ============================================================
  App: System Info - tabbed layout
  ============================================================ }
procedure draw_sysinfo;
var
    buf: array[0..63] of char;
    dt: TDateTime;
    total_mem: uint32;
begin
    if not show_sysinfo then exit;

    igSetNextWindowSize(ImVec2(440, 420), ImGuiCond_FirstUseEver);
    igSetNextWindowPos(ImVec2(200, 60), ImGuiCond_FirstUseEver, ImVec2(0, 0));

    if igBegin('System Information', @show_sysinfo, 0) then begin
        if igBeginTabBar('##sysinfo_tabs', 0) then begin

            { Tab: Overview }
            if igBeginTabItem('Overview', nil, 0) then begin
                igSpacing;

                { OS Section }
                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('SYSTEM');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                igText('  OS');
                igSameLine(120, 0);
                igTextColored(ImVec4(0.50, 0.80, 1.0, 1.0), 'Asuro');

                igText('  Architecture');
                igSameLine(120, 0);
                igTextColored(ImVec4(0.50, 0.80, 1.0, 1.0), 'i386');

                igText('  CPU');
                igSameLine(120, 0);
                igTextColored(ImVec4(0.50, 0.80, 1.0, 1.0), @cpu.CPUID.Identifier[0]);

                igText('  Framerate');
                igSameLine(120, 0);
                igText(i2s(uint32(ftrunc(imgui_get_framerate)), buf));
                igSameLine(0, 4);
                igTextColored(ImVec4(0.50, 0.80, 1.0, 1.0), 'FPS');

                igSpacing;
                igSpacing;

                { Memory section }
                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('MEMORY');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                total_mem := ((multibootinfo^.mem_upper + 1000) div 1024) + 1;

                igText('  Total');
                igSameLine(120, 0);
                igTextColored(ImVec4(0.40, 1.0, 0.40, 1.0), i2s(total_mem, buf));
                igSameLine(0, 4);
                igText('MB');

                igText('  Lower');
                igSameLine(120, 0);
                igText(i2s(multibootinfo^.mem_lower, buf));
                igSameLine(0, 4);
                igText('KB');

                igText('  Upper');
                igSameLine(120, 0);
                igText(i2s(multibootinfo^.mem_upper, buf));
                igSameLine(0, 4);
                igText('KB');

                igEndTabItem;
            end;

            { Tab: CPU }
            if igBeginTabItem('CPU', nil, 0) then begin
                igSpacing;

                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('CAPABILITIES');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                if igBeginTable('##cpufeatures', 4,
                    ImGuiTableFlags_Borders or ImGuiTableFlags_RowBg or ImGuiTableFlags_PadOuterX,
                    ImVec2(0, 0), 0) then begin

                    igTableSetupColumn('Feature', 0, 0, 0);
                    igTableSetupColumn('Status', 0, 0, 0);
                    igTableSetupColumn('Feature', 0, 0, 0);
                    igTableSetupColumn('Status', 0, 0, 0);
                    igTableHeadersRow;

                    { Row 1 }
                    igTableNextRow(0, 0);
                    igTableNextColumn; igText('FPU');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.FPU then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');
                    igTableNextColumn; igText('SSE');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.SSE then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');

                    { Row 2 }
                    igTableNextRow(0, 0);
                    igTableNextColumn; igText('SSE2');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.SSE2 then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');
                    igTableNextColumn; igText('MMX');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.MMX then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');

                    { Row 3 }
                    igTableNextRow(0, 0);
                    igTableNextColumn; igText('APIC');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.APIC then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');
                    igTableNextColumn; igText('PSE');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.PSE then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');

                    { Row 4 }
                    igTableNextRow(0, 0);
                    igTableNextColumn; igText('TSC');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.TSC then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');
                    igTableNextColumn; igText('PAE');
                    igTableNextColumn;
                    if cpu.CPUID.Capabilities0^.PAE then
                        igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Yes')
                    else igTextColored(ImVec4(1.0, 0.3, 0.3, 1.0), 'No');

                    igEndTable;
                end;

                igEndTabItem;
            end;

            { Tab: Display }
            if igBeginTabItem('Display', nil, 0) then begin
                igSpacing;

                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('VIDEO');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                igText('  Resolution');
                igSameLine(120, 0);
                igText(i2s(video.frontBufferWidth, buf));
                igSameLine(0, 0);
                igText(' x ');
                igSameLine(0, 0);
                igText(i2s(video.frontBufferHeight, buf));

                igText('  Color depth');
                igSameLine(120, 0);
                igText(i2s(video.frontBufferBpp, buf));
                igSameLine(0, 4);
                igText('bpp');

                igText('  Framerate');
                igSameLine(120, 0);
                igText(i2s(uint32(ftrunc(imgui_get_framerate)), buf));
                igSameLine(0, 4);
                igText('FPS');

                igSpacing;
                igSpacing;

                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('RENDER STATS');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                igText('  Solid quads');
                igSameLine(140, 0);
                igText(i2s(imgui_dbg_quads_solid, buf));

                igText('  Gradient quads');
                igSameLine(140, 0);
                igText(i2s(imgui_dbg_quads_gradient, buf));

                igText('  Textured quads');
                igSameLine(140, 0);
                igText(i2s(imgui_dbg_quads_textured, buf));

                igText('  Fallback tris');
                igSameLine(140, 0);
                igText(i2s(imgui_dbg_tris_fallback, buf));

                igText('  Total prims');
                igSameLine(140, 0);
                igText(i2s(imgui_dbg_triangles, buf));

                igSpacing;
                igSpacing;

                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('DATE & TIME');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                dt := RTC.getDateTime;
                igText('  Time');
                igSameLine(120, 0);
                pad2(dt.Hours, buf, 0);
                buf[2] := ':';
                pad2(dt.Minutes, buf, 3);
                buf[5] := ':';
                pad2(dt.Seconds, buf, 6);
                buf[8] := #0;
                igTextColored(ImVec4(0.5, 0.8, 1.0, 1.0), @buf[0]);

                igText('  Date');
                igSameLine(120, 0);
                pad2(dt.Day, buf, 0);
                buf[2] := '/';
                pad2(dt.Month, buf, 3);
                buf[5] := '/';
                pad2(dt.Year, buf, 6);
                buf[8] := #0;
                igText(@buf[0]);

                igText('  Day');
                igSameLine(120, 0);
                igText(RTC.weekdayToString(dt.Weekday));

                igEndTabItem;
            end;

            igEndTabBar;
        end;
    end;
    igEnd;
end;

{ ============================================================
  App: Terminal - dark, monospace feel
  ============================================================ }
procedure draw_terminal;
var
    i: uint32;
    flags: ImGuiWindowFlags;
    enter_pressed: boolean;
begin
    if not show_terminal then exit;

    igSetNextWindowSize(ImVec2(600, 400), ImGuiCond_FirstUseEver);
    igSetNextWindowPos(ImVec2(140, 90), ImGuiCond_FirstUseEver, ImVec2(0, 0));

    igPushStyleColor_Vec4(ImGuiCol_WindowBg, ImVec4(0.04, 0.04, 0.06, 0.98));
    igPushStyleColor_Vec4(ImGuiCol_TitleBg, ImVec4(0.06, 0.08, 0.13, 1.0));
    igPushStyleColor_Vec4(ImGuiCol_TitleBgActive, ImVec4(0.08, 0.14, 0.26, 1.0));

    if igBegin('Terminal', @show_terminal, 0) then begin
        { Output area }
        flags := ImGuiWindowFlags_NoNav;
        igPushStyleColor_Vec4(ImGuiCol_ChildBg, ImVec4(0.02, 0.02, 0.04, 1.0));
        if igBeginChild_Str('##term_output',
            ImVec2(0, -igGetFrameHeightWithSpacing - 6), ImGuiChildFlags_Border, flags) then begin

            igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.60, 0.95, 0.60, 1.0));
            if term_line_count > 0 then
                for i := 0 to term_line_count - 1 do
                    igTextUnformatted(@term_lines[i][0], nil);
            igPopStyleColor(1);

            if term_scroll_bottom then
                igSetScrollHereY(1.0);
            term_scroll_bottom := false;
        end;
        igEndChild;
        igPopStyleColor(1); { ChildBg }

        { Input line with prompt indicator }
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.85, 0.50, 1.0));
        igText('~');
        igPopStyleColor(1);
        igSameLine(0, 6);

        igPushItemWidth(-60);
        igPushStyleColor_Vec4(ImGuiCol_FrameBg, ImVec4(0.06, 0.06, 0.10, 1.0));
        igPushStyleColor_Vec4(ImGuiCol_FrameBgHovered, ImVec4(0.10, 0.10, 0.16, 1.0));
        igPushStyleColor_Vec4(ImGuiCol_FrameBgActive, ImVec4(0.08, 0.08, 0.14, 1.0));
        enter_pressed := igInputText('##term_input', @term_input[0], TERM_INPUT_LEN,
            ImGuiInputTextFlags_EnterReturnsTrue, nil, nil);
        igPopStyleColor(3);
        igPopItemWidth;

        igSameLine(0, 4);
        igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.14, 0.30, 0.20, 0.80));
        igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, ImVec4(0.18, 0.42, 0.28, 1.0));
        igPushStyleColor_Vec4(ImGuiCol_ButtonActive, ImVec4(0.10, 0.24, 0.16, 1.0));
        if igButton('Run', ImVec2(48, 0)) or enter_pressed then begin
            if term_input[0] <> #0 then begin
                term_exec(@term_input[0]);
                term_input[0] := #0;
                term_scroll_bottom := true;
            end;
            igSetKeyboardFocusHere(-1);
        end;
        igPopStyleColor(3);
    end;
    igEnd;
    igPopStyleColor(3);
end;

{ ============================================================
  App: File Browser - clean layout
  ============================================================ }
procedure draw_filebrowser;
var
    listing: PHashMap;
    i: uint32;
    item: PHashItem;
    obj: PVFSObject;
    is_dir: boolean;
    buf: array[0..FB_PATH_LEN-1] of char;
    len: uint32;
begin
    if not show_filebrowser then exit;

    if not fb_path_inited then begin
        fb_path[0] := '/'; fb_path[1] := #0;
        fb_path_inited := true;
    end;

    igSetNextWindowSize(ImVec2(460, 400), ImGuiCond_FirstUseEver);
    igSetNextWindowPos(ImVec2(180, 70), ImGuiCond_FirstUseEver, ImVec2(0, 0));

    if igBegin('File Browser', @show_filebrowser, 0) then begin
        { Navigation bar }
        igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.14, 0.18, 0.30, 0.70));
        igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, ImVec4(0.20, 0.28, 0.46, 0.90));
        igPushStyleColor_Vec4(ImGuiCol_ButtonActive, ImVec4(0.12, 0.16, 0.28, 1.0));
        igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 3.0);

        if igButton(' ^ Up ', ImVec2(50, 22)) then begin
            len := plen(@fb_path[0]);
            if len > 1 then begin
                i := len - 1;
                if (fb_path[i] = '/') and (i > 0) then dec(i);
                while (i > 0) and (fb_path[i] <> '/') do dec(i);
                if i = 0 then begin
                    fb_path[0] := '/'; fb_path[1] := #0;
                end else
                    fb_path[i] := #0;
            end;
        end;
        igSameLine(0, 4);

        if igButton(' / Root ', ImVec2(55, 22)) then begin
            fb_path[0] := '/'; fb_path[1] := #0;
        end;

        igPopStyleVar(1);
        igPopStyleColor(3);

        igSameLine(0, 12);

        { Path display }
        igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.72, 1.0, 1.0));
        igTextUnformatted(@fb_path[0], nil);
        igPopStyleColor(1);

        igSpacing;
        igSeparator;
        igSpacing;

        { File listing in a scrollable child }
        if igBeginChild_Str('##fb_list', ImVec2(0, 0), 0, 0) then begin
            listing := GetDirectoryListing(@fb_path[0]);
            if listing <> nil then begin
                for i := 0 to listing^.Size - 1 do begin
                    item := listing^.Table[i];
                    while item <> nil do begin
                        obj := PVFSObject(item^.Data);
                        is_dir := false;
                        if obj <> nil then begin
                            case obj^.ObjectType of
                                otVDIRECTORY, otDRIVE, otDEVICE, otMOUNT, otDIRECTORY: is_dir := true;
                            end;
                        end;

                        if is_dir then begin
                            buf[0] := '['; buf[1] := 'D'; buf[2] := ']';
                            buf[3] := ' '; buf[4] := ' ';
                            pcopy(item^.Key, buf[5], FB_PATH_LEN - 5);
                        end else begin
                            buf[0] := ' '; buf[1] := ' '; buf[2] := ' ';
                            buf[3] := ' '; buf[4] := ' ';
                            pcopy(item^.Key, buf[5], FB_PATH_LEN - 5);
                        end;

                        if igSelectable_Bool(@buf[0], false, 0, ImVec2(0, 0)) then begin
                            if is_dir then begin
                                len := plen(@fb_path[0]);
                                if (len > 1) then begin
                                    fb_path[len] := '/';
                                    pcopy(item^.Key, fb_path[len + 1], FB_PATH_LEN - len - 1);
                                end else
                                    pcopy(item^.Key, fb_path[1], FB_PATH_LEN - 1);
                            end;
                        end;

                        if igIsItemHovered(0) then begin
                            if igBeginTooltip then begin
                                if is_dir then
                                    igText('Directory')
                                else
                                    igText('File');
                                igEndTooltip;
                            end;
                        end;

                        item := item^.Next;
                    end;
                end;
            end else
                igTextColored(ImVec4(0.50, 0.50, 0.55, 0.80), '  (empty directory)');
        end;
        igEndChild;
    end;
    igEnd;
end;

{ ============================================================
  App: Task Manager - live stats
  ============================================================ }
procedure draw_taskmgr;
var
    buf: array[0..63] of char;
    entry: PScheduler_Entry;
    count: uint32;
    total_mem: uint32;
begin
    if not show_taskmgr then exit;

    igSetNextWindowSize(ImVec2(400, 360), ImGuiCond_FirstUseEver);
    igSetNextWindowPos(ImVec2(260, 110), ImGuiCond_FirstUseEver, ImVec2(0, 0));

    if igBegin('Task Manager', @show_taskmgr, 0) then begin
        if igBeginTabBar('##taskmgr_tabs', 0) then begin

            { Tab: Processes }
            if igBeginTabItem('Processes', nil, 0) then begin
                igSpacing;

                { Status header }
                igText('Scheduler:');
                igSameLine(0, 8);
                if scheduler.Active then
                    igTextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Active')
                else
                    igTextColored(ImVec4(1.0, 0.6, 0.2, 1.0), 'Inactive');

                igSameLine(0, 24);
                igText('FPS:');
                igSameLine(0, 6);
                igTextColored(ImVec4(0.50, 0.80, 1.0, 1.0),
                    i2s(uint32(ftrunc(imgui_get_framerate)), buf));

                igSpacing;

                { Task table }
                if igBeginTable('##tasks', 3,
                    ImGuiTableFlags_Borders or ImGuiTableFlags_RowBg or
                    ImGuiTableFlags_Resizable or ImGuiTableFlags_PadOuterX,
                    ImVec2(0, 0), 0) then begin

                    igTableSetupColumn('TID', ImGuiTableColumnFlags_WidthFixed, 60, 0);
                    igTableSetupColumn('Priority', ImGuiTableColumnFlags_WidthFixed, 80, 0);
                    igTableSetupColumn('Delta', ImGuiTableColumnFlags_WidthStretch, 0, 0);
                    igTableHeadersRow;

                    entry := scheduler.Root_Task;
                    if entry <> nil then begin
                        count := 0;
                        repeat
                            igTableNextRow(0, 0);
                            igTableNextColumn;
                            igText(i2s(entry^.ThreadID, buf));
                            igTableNextColumn;
                            igText(i2s(entry^.Priority, buf));
                            igTableNextColumn;
                            igText(i2s(entry^.Delta, buf));

                            entry := PScheduler_Entry(entry^.Next);
                            inc(count);
                        until (entry = scheduler.Root_Task) or (count > 64);
                    end;

                    igEndTable;
                end;

                igEndTabItem;
            end;

            { Tab: Memory }
            if igBeginTabItem('Memory', nil, 0) then begin
                igSpacing;

                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('PHYSICAL MEMORY');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                total_mem := ((multibootinfo^.mem_upper + 1000) div 1024) + 1;

                igText('  Total');
                igSameLine(140, 0);
                igTextColored(ImVec4(0.40, 1.0, 0.40, 1.0), i2s(total_mem, buf));
                igSameLine(0, 4);
                igText('MB');

                igText('  Lower memory');
                igSameLine(140, 0);
                igText(i2s(multibootinfo^.mem_lower, buf));
                igSameLine(0, 4);
                igText('KB');

                igText('  Upper memory');
                igSameLine(140, 0);
                igText(i2s(multibootinfo^.mem_upper, buf));
                igSameLine(0, 4);
                igText('KB');

                igSpacing;
                igSpacing;

                igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(0.50, 0.65, 0.90, 0.80));
                igText('ALLOCATION');
                igPopStyleColor(1);
                igSeparator;
                igSpacing;

                igText('  Physical blocks');
                igSameLine(140, 0);
                igText('1024 x 4 MB');

                igEndTabItem;
            end;

            igEndTabBar;
        end;
    end;
    igEnd;
end;

{ ============================================================
  Main frame entry
  ============================================================ }
procedure desktop_frame;
begin
    inc(frame_count);

    { Wallpaper (drawn to background draw list) }
    draw_wallpaper;

    { Desktop icons (transparent overlay) }
    draw_desktop_icons;

    { App windows }
    draw_sysinfo;
    draw_terminal;
    draw_filebrowser;
    draw_taskmgr;

    { Demo window }
    if show_demo then
        igShowDemoWindow(@show_demo);

    { Start menu (drawn on top of apps) }
    draw_start_menu;

    { Taskbar (always topmost) }
    draw_taskbar;
end;

{ ============================================================
  Init
  ============================================================ }
procedure desktop_init;
var
    sw, sh: single;
begin
    sw := video.frontBufferWidth;
    sh := video.frontBufferHeight;
    screen_w := sw;
    screen_h := sh;

    { Init terminal }
    term_line_count := 0;
    term_input[0] := #0;
    term_add_line('Asuro Terminal v2.0');
    term_add_line('Type "help" for available commands.');
    term_add_line('');

    { Init file browser }
    fb_path[0] := '/'; fb_path[1] := #0;
    fb_path_inited := true;

    frame_count := 0;

    { Apply custom desktop styling via C bridge }
    imgui_apply_desktop_style;
end;

end.
