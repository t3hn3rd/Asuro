{
    Driver->Video->Desktop - LVGL-based Desktop Environment.

    Provides a modern desktop with:
      - Gradient background
      - macOS-style floating dock/taskbar with search box
      - Program launcher with search & slide animation
      - RTC clock
      - Mouse cursor

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit desktop;

interface

uses
    lvgl, video, gpu, RTC, strings, util, tracer, multiboot, cpu, serial, windows, asuro;

type
    TProgLaunchProc = procedure;

{ Register a program so it appears in the search results. }
procedure registerProgram(name: pchar; launcher: TProgLaunchProc);

procedure init;
procedure update;
procedure relayout;

implementation

uses
    syslog;

const
    DOCK_HEIGHT   = 48;
    DOCK_MARGIN   = 8;
    DOCK_HPAD     = 120;
    DOCK_RADIUS   = 16;
    DOCK_ITEM_H   = 36;

    SEARCH_W      = 220;
    SEARCH_RADIUS = 16;

    RESULTS_W     = SEARCH_W;
    RESULTS_ROW_H = 36;
    RESULTS_MAX_VISIBLE = 6;
    RESULTS_PAD   = 6;

    SYSINFO_W     = 480;
    SYSINFO_H     = 560;

    MAX_PROGRAMS  = 16;

    { Animation }
    ANIM_SPEED    = 12;      { pixels per frame to slide }

{ ---- Program registry ---- }
type
    TProgEntry = record
        name    : pchar;
        launch  : TProgLaunchProc;
        active  : boolean;
    end;

var
    programs      : array[0..MAX_PROGRAMS-1] of TProgEntry;
    prog_count    : uint32;

{ ---- Desktop UI elements ---- }
var
    dock          : Plv_obj;
    search_ta     : Plv_obj;    { LVGL textarea widget }
    clock_label   : Plv_obj;
    cursor_obj    : Plv_obj;
    desktop_label : Plv_obj;

    { Results popup }
    results_panel : Plv_obj;
    result_btns   : array[0..RESULTS_MAX_VISIBLE-1] of Plv_obj;
    result_lbls   : array[0..RESULTS_MAX_VISIBLE-1] of Plv_obj;
    result_prog   : array[0..RESULTS_MAX_VISIBLE-1] of uint32;
    results_visible : uint32;
    results_open  : boolean;

    { System Info window }
    sysinfo_win_id : uint32;

    { Clock }
    last_minute   : uint8;

    { Slide animation state }
    anim_target_y : sint32;
    anim_current_y: sint32;
    anim_closing  : boolean;
    anim_hidden_y : sint32;

    { Search active state }
    search_active : boolean;

{ ============================================================
  Program Registry
  ============================================================ }
procedure registerProgram(name: pchar; launcher: TProgLaunchProc);
begin
    if prog_count >= MAX_PROGRAMS then exit;
    programs[prog_count].name   := name;
    programs[prog_count].launch := launcher;
    programs[prog_count].active := true;
    inc(prog_count);
end;

{ ============================================================
  Case-insensitive substring match (no allocation)
  ============================================================ }
function toLowerC(c: char): char;
begin
    if (c >= 'A') and (c <= 'Z') then
        toLowerC := char(ord(c) + 32)
    else
        toLowerC := c;
end;

function ciContains(haystack, needle: pchar): boolean;
var
    h, hs, ns : pchar;
begin
    ciContains := false;
    if needle^ = #0 then begin ciContains := true; exit; end;
    h := haystack;
    while h^ <> #0 do begin
        hs := h;
        ns := needle;
        while (hs^ <> #0) and (ns^ <> #0) and (toLowerC(hs^) = toLowerC(ns^)) do begin
            inc(hs);
            inc(ns);
        end;
        if ns^ = #0 then begin ciContains := true; exit; end;
        inc(h);
    end;
end;

{ ============================================================
  Build HH:MM string from RTC
  ============================================================ }
procedure updateClockText;
var
    dt     : TDateTime;
    h_str  : pchar;
    m_str  : pchar;
    txt    : pchar;
begin
    dt := RTC.getDateTime;
    if dt.Minutes = last_minute then exit;
    last_minute := dt.Minutes;

    if dt.Hours < 10 then
        h_str := stringConcat('0', intToString(dt.Hours))
    else
        h_str := intToString(dt.Hours);

    if dt.Minutes < 10 then
        m_str := stringConcat('0', intToString(dt.Minutes))
    else
        m_str := intToString(dt.Minutes);

    txt := stringConcat(h_str, stringConcat(':', m_str));
    lv_label_set_text(clock_label, txt);
end;

{ ============================================================
  Close the system info window
  ============================================================ }
procedure sysinfo_close_handler(win_id: uint32);
begin
    tracer.push_trace('desktop.sysinfo_close');
    windows.destroyWindow(win_id);
    sysinfo_win_id := 0;
    tracer.pop_trace;
end;

{ ============================================================
  Add a row: "LABEL: VALUE" to a parent container
  ============================================================ }
procedure addInfoRow(parent: Plv_obj; row_w: sint32; key: pchar; value: pchar);
var
    row      : Plv_obj;
    lbl_key  : Plv_obj;
    lbl_val  : Plv_obj;
begin
    row := lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, row_w - 40, 22);
    lv_obj_set_style_pad_all(row, 0, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lbl_key := lv_label_create(row);
    lv_label_set_text(lbl_key, key);
    lv_obj_set_style_text_color(lbl_key, lv_color_make(160, 170, 190), 0);
    lv_obj_set_style_text_font(lbl_key, @lv_font_montserrat_14, 0);

    lbl_val := lv_label_create(row);
    lv_label_set_text(lbl_val, value);
    lv_obj_set_style_text_color(lbl_val, lv_color_make(230, 235, 245), 0);
    lv_obj_set_style_text_font(lbl_val, @lv_font_montserrat_14, 0);
end;

{ ============================================================
  Section header label (blue accent, all-caps feel)
  ============================================================ }
procedure addSectionHeader(parent: Plv_obj; title: pchar);
var
    lbl : Plv_obj;
begin
    lbl := lv_label_create(parent);
    lv_label_set_text(lbl, title);
    lv_obj_set_style_text_color(lbl, lv_color_make(100, 160, 255), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
end;

{ ============================================================
  Thin horizontal separator line
  ============================================================ }
procedure addSeparator(parent: Plv_obj; row_w: sint32);
var
    sep : Plv_obj;
begin
    sep := lv_obj_create(parent);
    lv_obj_remove_style_all(sep);
    lv_obj_set_size(sep, row_w - 40, 1);
    lv_obj_set_style_bg_color(sep, lv_color_make(60, 65, 85), 0);
    lv_obj_set_style_bg_opa(sep, LV_OPA_COVER, 0);
    lv_obj_remove_flag(sep, LV_OBJ_FLAG_SCROLLABLE);
end;

{ ============================================================
  CPU instruction badge (small chip in a flex-wrap container)
  ============================================================ }
procedure addBadge(parent: Plv_obj; name: pchar);
var
    badge : Plv_obj;
    lbl   : Plv_obj;
begin
    badge := lv_obj_create(parent);
    lv_obj_remove_style_all(badge);
    lv_obj_set_size(badge, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(badge, lv_color_make(50, 55, 75), 0);
    lv_obj_set_style_bg_opa(badge, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(badge, 4, 0);
    lv_obj_set_style_pad_left(badge, 8, 0);
    lv_obj_set_style_pad_right(badge, 8, 0);
    lv_obj_set_style_pad_top(badge, 3, 0);
    lv_obj_set_style_pad_bottom(badge, 3, 0);
    lv_obj_remove_flag(badge, LV_OBJ_FLAG_SCROLLABLE);

    lbl := lv_label_create(badge);
    lv_label_set_text(lbl, name);
    lv_obj_set_style_text_color(lbl, lv_color_make(170, 210, 255), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
end;

{ ============================================================
  Open system info window (registered as a program)
  ============================================================ }
procedure openSysInfo;
var
    scr_w, scr_h : sint32;
    wx, wy       : sint32;
    content      : Plv_obj;
    instr_box    : Plv_obj;
    mem_str, res_str, cpu_str, clk_str : pchar;
    cw           : sint32;
    badge_h      : sint32;
begin
    if windows.isWindowOpen(sysinfo_win_id) then exit;

    scr_w := sint32(video.frontBufferWidth);
    scr_h := sint32(video.frontBufferHeight);
    wx := (scr_w - SYSINFO_W) div 2;
    wy := (scr_h - SYSINFO_H) div 2 - 30;

    sysinfo_win_id := windows.createWindow(
        'System Information',
        wx, wy, SYSINFO_W, SYSINFO_H,
        @sysinfo_close_handler,
        cursor_obj
    );
    if sysinfo_win_id = 0 then exit;
    content := windows.getWindowContent(sysinfo_win_id);
    if content = nil then exit;

    cw := SYSINFO_W;

    { ---- System Information ---- }
    addSectionHeader(content, 'System Information');

    cpu_str := @cpu.CPUID.Identifier[0];
    addInfoRow(content, cw, 'CPU Vendor', cpu_str);
    clk_str := stringConcat(intToString(cpu.CPUID.ClockSpeed.MHz), ' MHz');
    addInfoRow(content, cw, 'CPU Clock', clk_str);
    mem_str := stringConcat(intToString(((multibootinfo^.mem_upper + 1000) div 1024) + 1), ' MB');
    addInfoRow(content, cw, 'Memory', mem_str);
    res_str := stringConcat(intToString(video.frontBufferWidth), 'x');
    res_str := stringConcat(res_str, intToString(video.frontBufferHeight));
    res_str := stringConcat(res_str, 'x');
    res_str := stringConcat(res_str, intToString(video.frontBufferBpp));
    addInfoRow(content, cw, 'Resolution', res_str);
    addInfoRow(content, cw, 'Graphics', gpu.activeDriverName);

    addSeparator(content, cw);

    { ---- OS Information ---- }
    addSectionHeader(content, 'OS Information');

    addInfoRow(content, cw, 'Kernel Version', asuro.VERSION);
    addInfoRow(content, cw, 'Line Count', intToString(asuro.LINE_COUNT));
    addInfoRow(content, cw, 'File Count', intToString(asuro.FILE_COUNT));
    addInfoRow(content, cw, 'Driver Count', intToString(asuro.DRIVER_COUNT));
    addInfoRow(content, cw, 'FPC Version', asuro.FPC_VERSION);
    addInfoRow(content, cw, 'NASM Version', asuro.NASM_VERSION);
    addInfoRow(content, cw, 'Make Version', asuro.MAKE_VERSION);
    addInfoRow(content, cw, 'GUI Toolkit', 'LVGL 9.2.2');
    addInfoRow(content, cw, 'Compilation Time', asuro.COMPILE_TIME);
    addInfoRow(content, cw, 'Compilation Date', asuro.COMPILE_DATE);

    addSeparator(content, cw);

    { ---- Supported CPU Instructions ---- }
    addSectionHeader(content, 'Supported CPU Instructions');

    instr_box := lv_obj_create(content);
    lv_obj_remove_style_all(instr_box);
    lv_obj_set_width(instr_box, cw - 40);
    lv_obj_set_height(instr_box, 800);  { temporary large height for wrapping }
    lv_obj_set_style_layout(instr_box, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(instr_box, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_row(instr_box, 4, 0);
    lv_obj_set_style_pad_column(instr_box, 4, 0);
    lv_obj_remove_flag(instr_box, LV_OBJ_FLAG_SCROLLABLE);

    { Old capabilities (EDX) }
    if cpu.CPUID.Capabilities0^.FPU     then addBadge(instr_box, 'FPU');
    if cpu.CPUID.Capabilities0^.VME     then addBadge(instr_box, 'VME');
    if cpu.CPUID.Capabilities0^.DE      then addBadge(instr_box, 'DE');
    if cpu.CPUID.Capabilities0^.PSE     then addBadge(instr_box, 'PSE');
    if cpu.CPUID.Capabilities0^.TSC     then addBadge(instr_box, 'TSC');
    if cpu.CPUID.Capabilities0^.MSR     then addBadge(instr_box, 'MSR');
    if cpu.CPUID.Capabilities0^.PAE     then addBadge(instr_box, 'PAE');
    if cpu.CPUID.Capabilities0^.MCE     then addBadge(instr_box, 'MCE');
    if cpu.CPUID.Capabilities0^.CX8     then addBadge(instr_box, 'CX8');
    if cpu.CPUID.Capabilities0^.APIC    then addBadge(instr_box, 'APIC');
    if cpu.CPUID.Capabilities0^.SEP     then addBadge(instr_box, 'SEP');
    if cpu.CPUID.Capabilities0^.MTRR    then addBadge(instr_box, 'MTRR');
    if cpu.CPUID.Capabilities0^.PGE     then addBadge(instr_box, 'PGE');
    if cpu.CPUID.Capabilities0^.MCA     then addBadge(instr_box, 'MCA');
    if cpu.CPUID.Capabilities0^.CMOV    then addBadge(instr_box, 'CMOV');
    if cpu.CPUID.Capabilities0^.PAT     then addBadge(instr_box, 'PAT');
    if cpu.CPUID.Capabilities0^.PSE36   then addBadge(instr_box, 'PSE36');
    if cpu.CPUID.Capabilities0^.PSN     then addBadge(instr_box, 'PSN');
    if cpu.CPUID.Capabilities0^.CLF     then addBadge(instr_box, 'CLF');
    if cpu.CPUID.Capabilities0^.DTES    then addBadge(instr_box, 'DTES');
    if cpu.CPUID.Capabilities0^.ACPI    then addBadge(instr_box, 'ACPI');
    if cpu.CPUID.Capabilities0^.MMX     then addBadge(instr_box, 'MMX');
    if cpu.CPUID.Capabilities0^.FXSR    then addBadge(instr_box, 'FXSR');
    if cpu.CPUID.Capabilities0^.SSE     then addBadge(instr_box, 'SSE');
    if cpu.CPUID.Capabilities0^.SSE2    then addBadge(instr_box, 'SSE2');
    if cpu.CPUID.Capabilities0^.SS      then addBadge(instr_box, 'SS');
    if cpu.CPUID.Capabilities0^.HTT     then addBadge(instr_box, 'HTT');
    if cpu.CPUID.Capabilities0^.TM1     then addBadge(instr_box, 'TM1');
    if cpu.CPUID.Capabilities0^.IA64    then addBadge(instr_box, 'IA64');
    if cpu.CPUID.Capabilities0^.PBE     then addBadge(instr_box, 'PBE');

    { New capabilities (ECX) }
    if cpu.CPUID.Capabilities1^.SSE3    then addBadge(instr_box, 'SSE3');
    if cpu.CPUID.Capabilities1^.PCLMUL  then addBadge(instr_box, 'PCLMUL');
    if cpu.CPUID.Capabilities1^.DTES64  then addBadge(instr_box, 'DTES64');
    if cpu.CPUID.Capabilities1^.MONITOR then addBadge(instr_box, 'MONITOR');
    if cpu.CPUID.Capabilities1^.DS_CPL  then addBadge(instr_box, 'DS_CPL');
    if cpu.CPUID.Capabilities1^.VMX     then addBadge(instr_box, 'VMX');
    if cpu.CPUID.Capabilities1^.SMX     then addBadge(instr_box, 'SMX');
    if cpu.CPUID.Capabilities1^.EST     then addBadge(instr_box, 'EST');
    if cpu.CPUID.Capabilities1^.TM2     then addBadge(instr_box, 'TM2');
    if cpu.CPUID.Capabilities1^.SSSE3   then addBadge(instr_box, 'SSSE3');
    if cpu.CPUID.Capabilities1^.CID     then addBadge(instr_box, 'CID');
    if cpu.CPUID.Capabilities1^.FMA     then addBadge(instr_box, 'FMA');
    if cpu.CPUID.Capabilities1^.CX16    then addBadge(instr_box, 'CX16');
    if cpu.CPUID.Capabilities1^.ETPRD   then addBadge(instr_box, 'ETPRD');
    if cpu.CPUID.Capabilities1^.PDCM    then addBadge(instr_box, 'PDCM');
    if cpu.CPUID.Capabilities1^.PCIDE   then addBadge(instr_box, 'PCIDE');
    if cpu.CPUID.Capabilities1^.DCA     then addBadge(instr_box, 'DCA');
    if cpu.CPUID.Capabilities1^.SSE4_1  then addBadge(instr_box, 'SSE4.1');
    if cpu.CPUID.Capabilities1^.SSE4_2  then addBadge(instr_box, 'SSE4.2');
    if cpu.CPUID.Capabilities1^.x2APIC  then addBadge(instr_box, 'x2APIC');
    if cpu.CPUID.Capabilities1^.MOVBE   then addBadge(instr_box, 'MOVBE');
    if cpu.CPUID.Capabilities1^.POPCNT  then addBadge(instr_box, 'POPCNT');
    if cpu.CPUID.Capabilities1^.AES     then addBadge(instr_box, 'AES');
    if cpu.CPUID.Capabilities1^.XSAVE   then addBadge(instr_box, 'XSAVE');
    if cpu.CPUID.Capabilities1^.OSXSAVE then addBadge(instr_box, 'OSXSAVE');
    if cpu.CPUID.Capabilities1^.AVX     then addBadge(instr_box, 'AVX');
    if cpu.CPUID.Capabilities1^.RDRAND  then addBadge(instr_box, 'RDRAND');

    { Force layout so wrapped row heights are resolved,
      then set instr_box to its actual content height. }
    lv_obj_update_layout(lv_screen_active);
    badge_h := lv_obj_get_self_height(instr_box);

    if badge_h > 0 then
        lv_obj_set_height(instr_box, badge_h);
end;

{ ============================================================
  Clear search and close results (with animation)
  ============================================================ }
procedure clearAndClose;
begin
    search_active := false;
    { Stop cursor blink and hide cursor }
    lv_obj_set_style_anim_duration(search_ta, 0, LV_PART_CURSOR);
    lv_textarea_set_cursor_pos(search_ta, 0);
    lv_obj_set_style_bg_opa(search_ta, 0, LV_PART_CURSOR);
    { Remove from keyboard group so it stops receiving key input }
    lv_group_remove_obj(search_ta);
    lv_textarea_set_text(search_ta, '');
    if results_open and not anim_closing then
        anim_closing := true;
end;

{ ============================================================
  Results popup — create / destroy / filter
  ============================================================ }
procedure destroyResultsPanel; forward;

procedure result_btn_cb(e: Plv_event); cdecl;
var
    code   : uint32;
    target : Plv_obj;
    i, pi  : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    target := lv_event_get_target(e);

    for i := 0 to RESULTS_MAX_VISIBLE - 1 do begin
        if result_btns[i] = target then begin
            pi := result_prog[i];
            if (pi < prog_count) and programs[pi].active then begin
                syslog.logln('Desktop', 'Launching program');
                clearAndClose;
                programs[pi].launch;
            end;
            exit;
        end;
    end;
end;

procedure createResultsPanel;
var
    scr      : Plv_obj;
    dock_x   : sint32;
    panel_h  : sint32;
    i        : uint32;
begin
    if results_open then exit;

    scr := lv_screen_active;
    dock_x := lv_obj_get_x(dock);
    panel_h := sint32(RESULTS_MAX_VISIBLE) * RESULTS_ROW_H + RESULTS_PAD * 2;

    anim_hidden_y := lv_obj_get_y(dock);
    anim_target_y := lv_obj_get_y(dock) - panel_h - 6;
    anim_current_y := anim_hidden_y;
    anim_closing := false;

    results_panel := lv_obj_create(scr);
    lv_obj_remove_style_all(results_panel);
    lv_obj_set_size(results_panel, RESULTS_W, panel_h);
    { Align results panel with the search textarea }
    lv_obj_set_pos(results_panel, dock_x + 12, anim_current_y);
    lv_obj_set_style_bg_color(results_panel, lv_color_make(30, 33, 45), 0);
    lv_obj_set_style_bg_opa(results_panel, 240, 0);
    lv_obj_set_style_radius(results_panel, 12, 0);
    lv_obj_set_style_border_width(results_panel, 1, 0);
    lv_obj_set_style_border_color(results_panel, lv_color_make(70, 75, 100), 0);
    lv_obj_set_style_border_opa(results_panel, 160, 0);
    lv_obj_set_style_shadow_width(results_panel, 12, 0);
    lv_obj_set_style_shadow_color(results_panel, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_shadow_opa(results_panel, 140, 0);
    lv_obj_set_style_shadow_offset_y(results_panel, -2, 0);
    lv_obj_set_style_pad_left(results_panel, RESULTS_PAD, 0);
    lv_obj_set_style_pad_right(results_panel, RESULTS_PAD, 0);
    lv_obj_set_style_pad_top(results_panel, RESULTS_PAD, 0);
    lv_obj_set_style_pad_bottom(results_panel, RESULTS_PAD, 0);
    lv_obj_set_style_layout(results_panel, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(results_panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(results_panel, 2, 0);
    lv_obj_remove_flag(results_panel, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(results_panel, LV_SCROLLBAR_MODE_OFF);
    lv_obj_remove_flag(results_panel, LV_OBJ_FLAG_CLICKABLE);

    for i := 0 to RESULTS_MAX_VISIBLE - 1 do begin
        result_btns[i] := lv_button_create(results_panel);
        lv_obj_remove_style_all(result_btns[i]);
        lv_obj_set_size(result_btns[i], RESULTS_W - RESULTS_PAD * 2, RESULTS_ROW_H);
        lv_obj_set_style_bg_color(result_btns[i], lv_color_make(45, 50, 70), 0);
        lv_obj_set_style_bg_opa(result_btns[i], 0, 0);
        lv_obj_set_style_radius(result_btns[i], 8, 0);
        lv_obj_set_style_pad_left(result_btns[i], 12, 0);
        lv_obj_set_style_border_width(result_btns[i], 0, 0);
        lv_obj_set_style_shadow_width(result_btns[i], 0, 0);
        lv_obj_add_flag(result_btns[i], LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_layout(result_btns[i], LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(result_btns[i], LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(result_btns[i], LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

        result_lbls[i] := lv_label_create(result_btns[i]);
        lv_label_set_text(result_lbls[i], '');
        lv_obj_set_style_text_color(result_lbls[i], lv_color_make(210, 215, 235), 0);
        lv_obj_set_style_text_font(result_lbls[i], @lv_font_montserrat_14, 0);

        result_prog[i] := $FFFFFFFF;

        lv_obj_add_event_cb(result_btns[i], @result_btn_cb, LV_EVENT_CLICKED, nil);

        lv_obj_add_flag(result_btns[i], LV_OBJ_FLAG_HIDDEN);
    end;

    results_visible := 0;
    results_open := true;
end;

procedure destroyResultsPanel;
begin
    if not results_open then exit;
    if results_panel <> nil then begin
        lv_obj_delete(results_panel);
        results_panel := nil;
    end;
    results_open := false;
    results_visible := 0;
end;

{ ============================================================
  Filter results based on current textarea text
  ============================================================ }
procedure filterResults;
var
    query   : pchar;
    i, vis  : uint32;
    panel_h : sint32;
begin
    if not results_open then exit;
    if results_panel = nil then exit;

    query := lv_textarea_get_text(search_ta);

    vis := 0;
    for i := 0 to prog_count - 1 do begin
        if vis >= RESULTS_MAX_VISIBLE then break;
        if not programs[i].active then continue;

        if (query = nil) or (query^ = #0) or ciContains(programs[i].name, query) then begin
            lv_label_set_text(result_lbls[vis], programs[i].name);
            result_prog[vis] := i;
            lv_obj_remove_flag(result_btns[vis], LV_OBJ_FLAG_HIDDEN);
            inc(vis);
        end;
    end;

    results_visible := vis;

    { Hide remaining slots }
    while vis < RESULTS_MAX_VISIBLE do begin
        lv_obj_add_flag(result_btns[vis], LV_OBJ_FLAG_HIDDEN);
        result_prog[vis] := $FFFFFFFF;
        inc(vis);
    end;

    { Resize panel to fit visible results }
    if results_visible > 0 then begin
        panel_h := sint32(results_visible) * RESULTS_ROW_H + RESULTS_PAD * 2;
        lv_obj_set_height(results_panel, panel_h);
        anim_target_y := lv_obj_get_y(dock) - panel_h - 6;
    end;
end;

{ ============================================================
  Search textarea event handler
  ============================================================ }
procedure search_event_cb(e: Plv_event); cdecl;
var
    code : uint32;
begin
    code := lv_event_get_code(e);

    if code = LV_EVENT_CLICKED then begin
        { User clicked the search box — activate search }
        if not search_active then begin
            search_active := true;
            { Enable cursor blink, show cursor, and keyboard input }
            lv_obj_set_style_bg_opa(search_ta, LV_OPA_COVER, LV_PART_CURSOR);
            lv_obj_set_style_anim_duration(search_ta, 400, LV_PART_CURSOR);
            lv_group_add_obj(lvgl_get_kb_group, search_ta);
            lv_group_focus_obj(search_ta);
            if not results_open and not anim_closing then begin
                createResultsPanel;
                filterResults;
            end;
        end;
    end
    else if code = LV_EVENT_VALUE_CHANGED then begin
        { Text changed — only filter if search is active }
        if search_active then begin
            if not results_open and not anim_closing then
                createResultsPanel;
            filterResults;
        end;
    end
    else if code = LV_EVENT_READY then begin
        { Enter pressed (one-line textarea) — launch first result }
        if results_visible > 0 then begin
            if result_prog[0] < prog_count then begin
                clearAndClose;
                programs[result_prog[0]].launch;
            end;
        end;
    end;
end;

{ ============================================================
  Screen click handler — clear search when clicking elsewhere
  ============================================================ }
procedure screen_click_cb(e: Plv_event); cdecl;
var
    code   : uint32;
    target : Plv_obj;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    target := lv_event_get_target(e);
    { Only clear if the screen background was clicked directly }
    if target = lv_screen_active then
        clearAndClose;
end;

{ ============================================================
  Animate the results panel — slide in/out
  ============================================================ }
procedure animateResultsPanel;
var
    target_y : sint32;
begin
    if results_panel = nil then exit;

    if anim_closing then begin
        target_y := anim_hidden_y;
        if anim_current_y < target_y then begin
            anim_current_y := anim_current_y + ANIM_SPEED;
            if anim_current_y >= target_y then begin
                anim_current_y := target_y;
                destroyResultsPanel;
                anim_closing := false;
                exit;
            end;
        end else begin
            destroyResultsPanel;
            anim_closing := false;
            exit;
        end;
    end else begin
        if anim_current_y > anim_target_y then begin
            anim_current_y := anim_current_y - ANIM_SPEED;
            if anim_current_y < anim_target_y then
                anim_current_y := anim_target_y;
        end;
    end;

    if results_panel <> nil then
        lv_obj_set_pos(results_panel, lv_obj_get_x(results_panel), anim_current_y);
end;

{ ============================================================
  Mode-change callback — fired by GPU framework after setMode
  ============================================================ }
procedure desktopModeChanged(const info : TGPUModeInfo);
begin
    relayout;
end;

{ ============================================================
  Init — create the desktop UI
  ============================================================ }
procedure init;
var
    scr       : Plv_obj;
    scr_w     : sint32;
    scr_h     : sint32;
    dock_w    : sint32;
    dock_x    : sint32;
    dock_y    : sint32;
begin
    tracer.push_trace('desktop.init.enter');

    sysinfo_win_id := 0;
    prog_count     := 0;
    results_open   := false;
    results_panel  := nil;
    anim_closing   := false;
    search_active  := false;

    scr := lv_screen_active;
    scr_w := sint32(video.frontBufferWidth);
    scr_h := sint32(video.frontBufferHeight);

    { ---- Screen background ---- }
    lv_obj_remove_style_all(scr);
    lv_obj_set_style_bg_color(scr, lv_color_make(20, 25, 45), 0);
    lv_obj_set_style_bg_grad_color(scr, lv_color_make(40, 50, 80), 0);
    lv_obj_set_style_bg_grad_dir(scr, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(scr, LV_SCROLLBAR_MODE_OFF);
    { Click on background to dismiss search }
    lv_obj_add_flag(scr, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(scr, @screen_click_cb, LV_EVENT_CLICKED, nil);

    { ---- Subtle centered Asuro watermark ---- }
    desktop_label := lv_label_create(scr);
    lv_label_set_text(desktop_label, 'Asuro');
    lv_obj_set_style_text_color(desktop_label, lv_color_make(50, 58, 85), 0);
    lv_obj_set_style_text_font(desktop_label, @lv_font_montserrat_14, 0);
    lv_obj_align(desktop_label, LV_ALIGN_CENTER, 0, -30);

    { ---- Floating Dock (macOS-style) ---- }
    dock_w := scr_w - (DOCK_HPAD * 2);
    dock_x := DOCK_HPAD;
    dock_y := scr_h - DOCK_HEIGHT - DOCK_MARGIN;

    dock := lv_obj_create(scr);
    lv_obj_remove_style_all(dock);
    lv_obj_set_size(dock, dock_w, DOCK_HEIGHT);
    lv_obj_set_pos(dock, dock_x, dock_y);

    lv_obj_set_style_bg_color(dock, lv_color_make(25, 28, 38), 0);
    lv_obj_set_style_bg_opa(dock, 220, 0);
    lv_obj_set_style_radius(dock, DOCK_RADIUS, 0);
    lv_obj_set_style_border_width(dock, 1, 0);
    lv_obj_set_style_border_color(dock, lv_color_make(70, 75, 95), 0);
    lv_obj_set_style_border_opa(dock, 160, 0);
    lv_obj_set_style_shadow_width(dock, 16, 0);
    lv_obj_set_style_shadow_color(dock, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_shadow_opa(dock, 120, 0);
    lv_obj_set_style_shadow_offset_y(dock, 4, 0);
    lv_obj_remove_flag(dock, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(dock, LV_SCROLLBAR_MODE_OFF);

    { Flex row: search left, clock right }
    lv_obj_set_style_pad_left(dock, 12, 0);
    lv_obj_set_style_pad_right(dock, 16, 0);
    lv_obj_set_style_pad_top(dock, 0, 0);
    lv_obj_set_style_pad_bottom(dock, 0, 0);
    lv_obj_set_style_layout(dock, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(dock, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(dock, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    { ---- Search textarea (LVGL widget, not manual) ---- }
    search_ta := lv_textarea_create(dock);
    lv_obj_remove_style_all(search_ta);
    lv_obj_set_size(search_ta, SEARCH_W, DOCK_ITEM_H);
    lv_textarea_set_one_line(search_ta, true);
    lv_textarea_set_placeholder_text(search_ta, 'Search programs...');
    lv_textarea_set_text(search_ta, '');
    lv_textarea_set_cursor_click_pos(search_ta, true);

    { Main part style — dark rounded input }
    lv_obj_set_style_bg_color(search_ta, lv_color_make(40, 44, 58), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(search_ta, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(search_ta, SEARCH_RADIUS, LV_PART_MAIN);
    lv_obj_set_style_border_width(search_ta, 1, LV_PART_MAIN);
    lv_obj_set_style_border_color(search_ta, lv_color_make(80, 85, 110), LV_PART_MAIN);
    lv_obj_set_style_border_opa(search_ta, 140, LV_PART_MAIN);
    lv_obj_set_style_text_color(search_ta, lv_color_make(220, 225, 240), LV_PART_MAIN);
    lv_obj_set_style_text_font(search_ta, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_pad_left(search_ta, 14, LV_PART_MAIN);
    lv_obj_set_style_pad_right(search_ta, 14, LV_PART_MAIN);
    lv_obj_set_style_pad_top(search_ta, 8, LV_PART_MAIN);
    lv_obj_set_style_pad_bottom(search_ta, 8, LV_PART_MAIN);
    lv_obj_remove_flag(search_ta, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(search_ta, LV_SCROLLBAR_MODE_OFF);

    { Cursor part style — starts inactive (no blink) }
    lv_obj_set_style_bg_color(search_ta, lv_color_make(180, 190, 220), LV_PART_CURSOR);
    lv_obj_set_style_bg_opa(search_ta, LV_OPA_COVER, LV_PART_CURSOR);
    lv_obj_set_style_anim_duration(search_ta, 0, LV_PART_CURSOR);

    { Cancel the blink animation that lv_textarea_create started, hide cursor }
    lv_textarea_set_cursor_pos(search_ta, 0);
    lv_obj_set_style_bg_opa(search_ta, 0, LV_PART_CURSOR);

    { Don't add to keyboard group yet — user must click to activate }

    { Event handlers }
    lv_obj_add_event_cb(search_ta, @search_event_cb, LV_EVENT_CLICKED, nil);
    lv_obj_add_event_cb(search_ta, @search_event_cb, LV_EVENT_VALUE_CHANGED, nil);
    lv_obj_add_event_cb(search_ta, @search_event_cb, LV_EVENT_READY, nil);

    { ---- Clock label (right side of dock) ---- }
    clock_label := lv_label_create(dock);
    lv_label_set_text(clock_label, '00:00');
    lv_obj_set_style_text_color(clock_label, lv_color_make(200, 205, 220), 0);
    lv_obj_set_style_text_font(clock_label, @lv_font_montserrat_14, 0);

    { ---- Mouse cursor (FontAwesome arrow-pointer U+F245) ---- }
    cursor_obj := lv_label_create(scr);
    lv_obj_remove_style_all(cursor_obj);
    lv_label_set_text(cursor_obj, #$EF#$89#$85);  { UTF-8 for U+F245 }
    lv_obj_set_style_text_font(cursor_obj, @lv_font_fa_solid_16, 0);
    lv_obj_set_style_text_color(cursor_obj, lv_color_make(255, 255, 255), 0);
    lv_obj_set_style_text_opa(cursor_obj, LV_OPA_COVER, 0);
    lv_obj_remove_flag(cursor_obj, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(cursor_obj, LV_OBJ_FLAG_SCROLLABLE);

    lvgl_set_mouse_cursor(cursor_obj);

    { Force initial clock update }
    last_minute := 255;
    updateClockText;

    { ---- Register built-in programs ---- }
    registerProgram('System Information', @openSysInfo);

    { Register for resolution-change notifications from GPU framework }
    gpu.registerModeChangeCallback(@desktopModeChanged);

    tracer.pop_trace;
end;

{ ============================================================
  Relayout — reposition all desktop UI after resolution change
  ============================================================ }
procedure relayout;
var
    scr_w, scr_h : sint32;
    dock_w       : sint32;
    dock_x       : sint32;
    dock_y       : sint32;
begin
    tracer.push_trace('desktop.relayout');

    scr_w := sint32(video.frontBufferWidth);
    scr_h := sint32(video.frontBufferHeight);

    { Close any open search/results first }
    clearAndClose;

    { Reposition dock }
    dock_w := scr_w - (DOCK_HPAD * 2);
    dock_x := DOCK_HPAD;
    dock_y := scr_h - DOCK_HEIGHT - DOCK_MARGIN;
    lv_obj_set_size(dock, dock_w, DOCK_HEIGHT);
    lv_obj_set_pos(dock, dock_x, dock_y);

    { Watermark stays centered (LV_ALIGN_CENTER is relative to parent) }
    lv_obj_align(desktop_label, LV_ALIGN_CENTER, 0, -30);

    { Force layout recalculation }
    lv_obj_update_layout(lv_screen_active);

    tracer.pop_trace;
end;

{ ============================================================
  Update — called each frame from main loop
  ============================================================ }
procedure update;
begin
    updateClockText;
    animateResultsPanel;
end;

end.
