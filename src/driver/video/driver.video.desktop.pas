{
    Driver->Video->Desktop - LVGL-based Desktop Environment.

    Provides a modern driver.video.desktop with:
      - Gradient background
      - macOS-style floating dock/taskbar with search box
      - Program launcher with search
      - driver.timer.rtc clock
      - Mouse cursor

    @author(Kieron Morris <kjm@kieronmorris.me>)
    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.video.desktop;

interface

uses
    driver.video.lvgl, driver.video, driver.video.gpu, driver.timer.rtc, core.strings, core.util, arch.platform.cpu, debug.tracer, arch.platform.memory, driver.io.serial, driver.video.windows, core.version;

type
    TProgLaunchProc = procedure;

{ Register a program so it appears in the search results. }
procedure registerProgram(name: pchar; launcher: TProgLaunchProc);

procedure init;
procedure update;
procedure relayout;

implementation

uses
    io.syslog, core.ds.lists, memory.heap, driver.hid.keyboard, app.tasks;

const
    DOCK_HEIGHT   = 48;
    DOCK_MARGIN   = 8;
    DOCK_HPAD     = 120;
    DOCK_RADIUS   = 16;
    DOCK_ITEM_H   = 36;

    SEARCH_RADIUS = 16;

    RESULTS_W     = 280;
    RESULTS_H     = 296;
    RESULTS_ROW_H = 38;
    RESULTS_PAD   = 8;
    RESULTS_SCROLLBAR_W = 4;
    RESULTS_BORDER = 1;
    RESULTS_DOCK_GAP = 6;
    RESULTS_FOOTER_H = 44;

    MENU_SHUTDOWN = 1;
    MENU_RESTART  = 2;
    MENU_CONSOLE  = 3;

    SYSINFO_W     = 480;
    SYSINFO_PAD   = 20;
    SYSINFO_SCROLLBAR_W = 6;
    SYSINFO_SCROLLBAR_INSET = 2;

{ ---- Program registry ---- }
type
    TProgEntry = record
        name    : pchar;
        launch  : TProgLaunchProc;
        active  : boolean;
    end;
    PProgEntry = ^TProgEntry;

var
    programs : PLinkedListBase;

{ ---- Desktop UI elements ---- }
var
    dock          : Plv_obj;
    search_ta     : Plv_obj;    { LVGL textarea widget }
    clock_label   : Plv_obj;
    cursor_obj    : Plv_obj;
    desktop_label : Plv_obj;

    { Results popup }
    results_panel : Plv_obj;
    results_list  : Plv_obj;
    empty_label   : Plv_obj;
    first_result  : PProgEntry;
    console_launch: TProgLaunchProc;

    { System Info window }
    sysinfo_win_id : uint32;

    { Clock }
    last_minute   : uint8;
    last_clock_poll: uint32;
    clock_polled: boolean;

    { Search active state }
    search_active : boolean;

{ ============================================================
  Program Registry
  ============================================================ }
procedure registerProgram(name: pchar; launcher: TProgLaunchProc);
var
    entry : PProgEntry;
begin
    if programs = nil then
        programs := LL_New(sizeof(TProgEntry));
    entry := PProgEntry(LL_Add(programs));
    entry^.name   := name;
    entry^.launch := launcher;
    entry^.active := true;
    if stringEqualsCI(name, 'Terminal') then
        console_launch := launcher;
end;

{ ============================================================
  Build HH:MM string from driver.timer.rtc
  ============================================================ }
procedure updateClockText;
var
    dt: TDateTime;
    now_ms: uint32;
    txt: array[0..5] of char;
begin
    now_ms := lvgl_get_ticks;
    if clock_polled and (uint32(now_ms - last_clock_poll) < 1000) then exit;
    last_clock_poll := now_ms;
    dt := driver.timer.rtc.getDateTime;
    if clock_polled and (dt.Minutes = last_minute) then exit;
    clock_polled := true;
    last_minute := dt.Minutes;

    txt[0] := char(ord('0') + dt.Hours div 10);
    txt[1] := char(ord('0') + dt.Hours mod 10);
    txt[2] := ':';
    txt[3] := char(ord('0') + dt.Minutes div 10);
    txt[4] := char(ord('0') + dt.Minutes mod 10);
    txt[5] := #0;
    lv_label_set_text(clock_label, @txt[0]);
end;

{ ============================================================
  Close the system info window
  ============================================================ }
procedure sysinfo_close_handler(win_id: uint32);
begin
    debug.tracer.push_trace('driver.video.desktop.sysinfo_close');
    driver.video.windows.destroyWindow(win_id);
    sysinfo_win_id := 0;
    debug.tracer.pop_trace;
end;

{ ============================================================
  Add a row: "LABEL: VALUE" to a parent container
  ============================================================ }
procedure addInfoRow(parent: Plv_obj; key: pchar; value: pchar);
var
    row      : Plv_obj;
    lbl_key  : Plv_obj;
    lbl_val  : Plv_obj;
begin
    row := lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, lv_pct(100), 22);
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
procedure addSeparator(parent: Plv_obj);
var
    sep : Plv_obj;
begin
    sep := lv_obj_create(parent);
    lv_obj_remove_style_all(sep);
    lv_obj_set_size(sep, lv_pct(100), 1);
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
    max_h        : sint32;
    content      : Plv_obj;
    instr_box    : Plv_obj;
    mem_str, res_str, cpu_str, clk_str : pchar;
    frame        : Plv_obj;
    registers, features: TCPURegisters;
    vendor: array[0..12] of char;
    maxLeaf: uint32;
begin
    if driver.video.windows.isWindowOpen(sysinfo_win_id) then exit;

    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);
    max_h := scr_h - DOCK_HEIGHT - DOCK_MARGIN * 3;

    sysinfo_win_id := driver.video.windows.createFixedWindow(
        'System Information',
        (scr_w - SYSINFO_W) div 2, DOCK_MARGIN, SYSINFO_W, max_h,
        @sysinfo_close_handler,
        cursor_obj
    );
    if sysinfo_win_id = 0 then exit;
    content := driver.video.windows.getWindowContent(sysinfo_win_id);
    if content = nil then exit;

    lv_obj_set_style_pad_left(content, SYSINFO_PAD, 0);
    lv_obj_set_style_pad_right(content, SYSINFO_PAD + SYSINFO_SCROLLBAR_W + SYSINFO_SCROLLBAR_INSET, 0);
    lv_obj_set_style_width(content, SYSINFO_SCROLLBAR_W, LV_PART_SCROLLBAR);
    lv_obj_set_style_pad_right(content, SYSINFO_SCROLLBAR_INSET, LV_PART_SCROLLBAR);
    lv_obj_set_scroll_dir(content, LV_DIR_VER);

    { ---- System Information ---- }
    addSectionHeader(content, 'System Information');

    queryCPU(0, 0, registers);
    maxLeaf := registers.eax;
    puint32(@vendor[0])^ := registers.ebx;
    puint32(@vendor[4])^ := registers.edx;
    puint32(@vendor[8])^ := registers.ecx;
    vendor[12] := #0;
    cpu_str := @vendor[0];
    queryCPU(1, 0, features);
    addInfoRow(content, 'CPU Vendor', cpu_str);
    clk_str := 'Not reported';
    if maxLeaf >= $16 then begin
        queryCPU($16, 0, registers);
        if registers.eax <> 0 then clk_str := stringConcat(intToString(registers.eax), ' MHz');
    end;
    addInfoRow(content, 'CPU Clock', clk_str);
    mem_str := intToString(arch.platform.memory.totalPhysicalBytes div (1024 * 1024));
    addInfoRow(content, 'Memory (MiB)', mem_str);
    kfree(void(mem_str));
    res_str := stringConcat(intToString(driver.video.frontBufferWidth), 'x');
    res_str := stringConcat(res_str, intToString(driver.video.frontBufferHeight));
    res_str := stringConcat(res_str, 'x');
    res_str := stringConcat(res_str, intToString(driver.video.frontBufferBpp));
    addInfoRow(content, 'Resolution', res_str);
    addInfoRow(content, 'Graphics', driver.video.gpu.activeDriverName);

    addSeparator(content);

    { ---- OS Information ---- }
    addSectionHeader(content, 'OS Information');

    addInfoRow(content, 'Kernel Version', core.version.VERSION);
    addInfoRow(content, 'Line Count', intToString(core.version.LINE_COUNT));
    addInfoRow(content, 'File Count', intToString(core.version.FILE_COUNT));
    addInfoRow(content, 'Driver Count', intToString(core.version.DRIVER_COUNT));
    addInfoRow(content, 'FPC Version', core.version.FPC_VERSION);
    addInfoRow(content, 'NASM Version', core.version.NASM_VERSION);
    addInfoRow(content, 'Make Version', core.version.MAKE_VERSION);
    addInfoRow(content, 'GUI Toolkit', 'LVGL 9.2.2');
    addInfoRow(content, 'Compilation Time', core.version.COMPILE_TIME);
    addInfoRow(content, 'Compilation Date', core.version.COMPILE_DATE);

    addSeparator(content);

    { ---- Supported CPU Instructions ---- }
    addSectionHeader(content, 'Supported CPU Instructions');

    instr_box := lv_obj_create(content);
    lv_obj_remove_style_all(instr_box);
    lv_obj_set_size(instr_box, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_set_style_layout(instr_box, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(instr_box, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_row(instr_box, 4, 0);
    lv_obj_set_style_pad_column(instr_box, 4, 0);
    lv_obj_remove_flag(instr_box, LV_OBJ_FLAG_SCROLLABLE);

    { Old capabilities (EDX) }
    if (features.edx and (uint32(1) shl 0) <> 0)     then addBadge(instr_box, 'FPU');
    if (features.edx and (uint32(1) shl 1) <> 0)     then addBadge(instr_box, 'VME');
    if (features.edx and (uint32(1) shl 2) <> 0)      then addBadge(instr_box, 'DE');
    if (features.edx and (uint32(1) shl 3) <> 0)     then addBadge(instr_box, 'PSE');
    if (features.edx and (uint32(1) shl 4) <> 0)     then addBadge(instr_box, 'TSC');
    if (features.edx and (uint32(1) shl 5) <> 0)     then addBadge(instr_box, 'MSR');
    if (features.edx and (uint32(1) shl 6) <> 0)     then addBadge(instr_box, 'PAE');
    if (features.edx and (uint32(1) shl 7) <> 0)     then addBadge(instr_box, 'arch.x86.fault.mce');
    if (features.edx and (uint32(1) shl 8) <> 0)     then addBadge(instr_box, 'CX8');
    if (features.edx and (uint32(1) shl 9) <> 0)    then addBadge(instr_box, 'APIC');
    if (features.edx and (uint32(1) shl 11) <> 0)     then addBadge(instr_box, 'SEP');
    if (features.edx and (uint32(1) shl 12) <> 0)    then addBadge(instr_box, 'MTRR');
    if (features.edx and (uint32(1) shl 13) <> 0)     then addBadge(instr_box, 'PGE');
    if (features.edx and (uint32(1) shl 14) <> 0)     then addBadge(instr_box, 'MCA');
    if (features.edx and (uint32(1) shl 15) <> 0)    then addBadge(instr_box, 'CMOV');
    if (features.edx and (uint32(1) shl 16) <> 0)     then addBadge(instr_box, 'PAT');
    if (features.edx and (uint32(1) shl 17) <> 0)   then addBadge(instr_box, 'PSE36');
    if (features.edx and (uint32(1) shl 18) <> 0)     then addBadge(instr_box, 'PSN');
    if (features.edx and (uint32(1) shl 19) <> 0)     then addBadge(instr_box, 'CLF');
    if (features.edx and (uint32(1) shl 21) <> 0)    then addBadge(instr_box, 'DTES');
    if (features.edx and (uint32(1) shl 22) <> 0)    then addBadge(instr_box, 'ACPI');
    if (features.edx and (uint32(1) shl 23) <> 0)     then addBadge(instr_box, 'MMX');
    if (features.edx and (uint32(1) shl 24) <> 0)    then addBadge(instr_box, 'FXSR');
    if (features.edx and (uint32(1) shl 25) <> 0)     then addBadge(instr_box, 'SSE');
    if (features.edx and (uint32(1) shl 26) <> 0)    then addBadge(instr_box, 'SSE2');
    if (features.edx and (uint32(1) shl 27) <> 0)      then addBadge(instr_box, 'SS');
    if (features.edx and (uint32(1) shl 28) <> 0)     then addBadge(instr_box, 'HTT');
    if (features.edx and (uint32(1) shl 29) <> 0)     then addBadge(instr_box, 'TM1');
    if (features.edx and (uint32(1) shl 30) <> 0)    then addBadge(instr_box, 'IA64');
    if (features.edx and (uint32(1) shl 31) <> 0)     then addBadge(instr_box, 'PBE');

    { New capabilities (ECX) }
    if (features.ecx and (uint32(1) shl 0) <> 0)    then addBadge(instr_box, 'SSE3');
    if (features.ecx and (uint32(1) shl 1) <> 0)  then addBadge(instr_box, 'PCLMUL');
    if (features.ecx and (uint32(1) shl 2) <> 0)  then addBadge(instr_box, 'DTES64');
    if (features.ecx and (uint32(1) shl 3) <> 0) then addBadge(instr_box, 'MONITOR');
    if (features.ecx and (uint32(1) shl 4) <> 0)  then addBadge(instr_box, 'DS_CPL');
    if (features.ecx and (uint32(1) shl 5) <> 0)     then addBadge(instr_box, 'VMX');
    if (features.ecx and (uint32(1) shl 6) <> 0)     then addBadge(instr_box, 'SMX');
    if (features.ecx and (uint32(1) shl 7) <> 0)     then addBadge(instr_box, 'EST');
    if (features.ecx and (uint32(1) shl 8) <> 0)     then addBadge(instr_box, 'TM2');
    if (features.ecx and (uint32(1) shl 9) <> 0)   then addBadge(instr_box, 'SSSE3');
    if (features.ecx and (uint32(1) shl 10) <> 0)     then addBadge(instr_box, 'CID');
    if (features.ecx and (uint32(1) shl 12) <> 0)     then addBadge(instr_box, 'FMA');
    if (features.ecx and (uint32(1) shl 13) <> 0)    then addBadge(instr_box, 'CX16');
    if (features.ecx and (uint32(1) shl 14) <> 0)   then addBadge(instr_box, 'ETPRD');
    if (features.ecx and (uint32(1) shl 15) <> 0)    then addBadge(instr_box, 'PDCM');
    if (features.ecx and (uint32(1) shl 17) <> 0)   then addBadge(instr_box, 'PCIDE');
    if (features.ecx and (uint32(1) shl 18) <> 0)     then addBadge(instr_box, 'DCA');
    if (features.ecx and (uint32(1) shl 19) <> 0)  then addBadge(instr_box, 'SSE4.1');
    if (features.ecx and (uint32(1) shl 20) <> 0)  then addBadge(instr_box, 'SSE4.2');
    if (features.ecx and (uint32(1) shl 21) <> 0)  then addBadge(instr_box, 'x2APIC');
    if (features.ecx and (uint32(1) shl 22) <> 0)   then addBadge(instr_box, 'MOVBE');
    if (features.ecx and (uint32(1) shl 23) <> 0)  then addBadge(instr_box, 'POPCNT');
    if (features.ecx and (uint32(1) shl 25) <> 0)     then addBadge(instr_box, 'AES');
    if (features.ecx and (uint32(1) shl 26) <> 0)   then addBadge(instr_box, 'XSAVE');
    if (features.ecx and (uint32(1) shl 27) <> 0) then addBadge(instr_box, 'OSXSAVE');
    if (features.ecx and (uint32(1) shl 28) <> 0)     then addBadge(instr_box, 'AVX');
    if (features.ecx and (uint32(1) shl 30) <> 0)  then addBadge(instr_box, 'RDRAND');

    driver.video.windows.fitWindowHeight(sysinfo_win_id, max_h);
    frame := driver.video.windows.getWindowFrame(sysinfo_win_id);
    lv_obj_update_layout(frame);
    lv_obj_set_y(frame, DOCK_MARGIN + (max_h - lv_obj_get_height(frame)) div 2);
end;

{ ============================================================
  Clear search and close results
  ============================================================ }
procedure destroyResultsPanel; forward;

procedure clearAndClose;
begin
    search_active := false;
    { Stop cursor blink and hide cursor }
    lv_obj_set_style_anim_duration(search_ta, 0, LV_PART_CURSOR);
    lv_textarea_set_cursor_pos(search_ta, 0);
    lv_obj_set_style_bg_opa(search_ta, 0, LV_PART_CURSOR);
    { Remove from driver.hid.keyboard group so it stops receiving key input }
    lv_group_remove_obj(search_ta);
    lv_textarea_set_text(search_ta, '');
    destroyResultsPanel;
end;

{ ============================================================
  Results popup — create / destroy / filter
  ============================================================ }
procedure launchResult(entry: PProgEntry);
begin
    if entry = nil then exit;
    if not entry^.active then exit;
    clearAndClose;
    entry^.launch;
end;

procedure result_btn_cb(e: Plv_event); cdecl;
begin
    launchResult(PProgEntry(lv_event_get_user_data(e)));
end;

procedure footer_btn_cb(e: Plv_event); cdecl;
begin
    case uint32(lv_event_get_user_data(e)) of
        MENU_RESTART:
            resetSystem;
        MENU_CONSOLE:
            if Assigned(console_launch) then begin
                clearAndClose;
                console_launch;
            end;
    end;
end;

procedure createFooterButton(footer: Plv_obj; icon: pchar; action: uint32);
var
    btn, lbl: Plv_obj;
begin
    btn := lv_button_create(footer);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, 0, lv_pct(100));
    lv_obj_set_flex_grow(btn, 1);
    lv_obj_set_style_radius(btn, 8, 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(btn, lv_color_make(40, 44, 58), 0);
    lv_obj_set_style_bg_color(btn, lv_color_make(58, 64, 84), LV_STATE_PRESSED);
    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, icon);
    lv_obj_set_style_text_font(lbl, @lv_font_fa_solid_16, 0);
    lv_obj_set_style_text_color(lbl, lv_color_make(190, 201, 230), 0);
    lv_obj_center(lbl);

    if (action = MENU_SHUTDOWN) or ((action = MENU_CONSOLE) and not Assigned(console_launch)) then begin
        lv_obj_add_state(btn, LV_STATE_DISABLED);
        lv_obj_set_style_opa(btn, 110, 0);
    end else
        lv_obj_add_event_cb(btn, @footer_btn_cb, LV_EVENT_CLICKED, pointer(action));
end;

procedure createResultsPanel;
var
    footer, btn, lbl: Plv_obj;
    i, count: uint32;
    entry: PProgEntry;
begin
    if results_panel <> nil then exit;

    results_panel := lv_obj_create(lv_screen_active);
    lv_obj_remove_style_all(results_panel);
    lv_obj_set_size(results_panel, RESULTS_W, RESULTS_H);
    lv_obj_set_pos(results_panel, lv_obj_get_x(dock) + 12,
        lv_obj_get_y(dock) - RESULTS_H - RESULTS_DOCK_GAP);
    lv_obj_set_style_bg_color(results_panel, lv_color_make(30, 33, 45), 0);
    lv_obj_set_style_bg_opa(results_panel, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(results_panel, 14, 0);
    lv_obj_set_style_border_width(results_panel, RESULTS_BORDER, 0);
    lv_obj_set_style_border_color(results_panel, lv_color_make(70, 75, 100), 0);
    lv_obj_set_style_border_opa(results_panel, 160, 0);
    lv_obj_set_style_shadow_width(results_panel, 12, 0);
    lv_obj_set_style_shadow_color(results_panel, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_shadow_opa(results_panel, 140, 0);
    lv_obj_set_style_pad_all(results_panel, RESULTS_PAD, 0);
    lv_obj_set_style_pad_row(results_panel, RESULTS_PAD, 0);
    lv_obj_set_flex_flow(results_panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(results_panel, LV_OBJ_FLAG_SCROLLABLE);

    results_list := lv_obj_create(results_panel);
    lv_obj_remove_style_all(results_list);
    lv_obj_set_size(results_list, lv_pct(100), 0);
    lv_obj_set_flex_grow(results_list, 1);
    lv_obj_set_flex_flow(results_list, LV_FLEX_FLOW_COLUMN);
    { Leave the same gap on either side of the scrollbar. }
    lv_obj_set_style_pad_left(results_list, 5, 0);
    lv_obj_set_style_pad_right(results_list, RESULTS_PAD + RESULTS_SCROLLBAR_W, 0);
    lv_obj_set_scroll_dir(results_list, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(results_list, LV_SCROLLBAR_MODE_ON);
    lv_obj_set_style_width(results_list, RESULTS_SCROLLBAR_W, LV_PART_SCROLLBAR);
    lv_obj_set_style_radius(results_list, 2, LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_color(results_list, lv_color_make(105, 115, 145), LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_opa(results_list, LV_OPA_COVER, LV_PART_SCROLLBAR);

    empty_label := lv_label_create(results_list);
    lv_label_set_text(empty_label, 'No matching applications');
    lv_obj_set_width(empty_label, lv_pct(100));
    lv_obj_set_style_text_align(empty_label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_font(empty_label, @lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(empty_label, lv_color_make(165, 173, 198), 0);
    lv_obj_set_style_pad_all(empty_label, 12, 0);

    if programs <> nil then begin
        count := LL_Size(programs);
        for i := 1 to count do begin
            entry := PProgEntry(LL_Get(programs, i - 1));
            if entry = nil then continue;

            btn := lv_button_create(results_list);
            lv_obj_remove_style_all(btn);
            lv_obj_set_size(btn, lv_pct(100), RESULTS_ROW_H);
            lv_obj_set_style_border_width(btn, 1, 0);
            lv_obj_set_style_border_color(btn, lv_color_make(67, 73, 94), 0);
            lv_obj_set_style_pad_left(btn, 1, 0);
            lv_obj_set_style_pad_right(btn, 1, 0);
            lv_obj_set_user_data(btn, entry);
            lv_obj_add_event_cb(btn, @result_btn_cb, LV_EVENT_CLICKED, entry);

            lbl := lv_label_create(btn);
            lv_label_set_text(lbl, entry^.name);
            lv_obj_set_width(lbl, lv_pct(100));
            lv_label_set_long_mode(lbl, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_color(lbl, lv_color_make(210, 215, 235), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_LEFT, 0);
            lv_obj_center(lbl);
        end;
    end;

    footer := lv_obj_create(results_panel);
    lv_obj_remove_style_all(footer);
    lv_obj_set_size(footer, lv_pct(100), RESULTS_FOOTER_H);
    lv_obj_set_flex_flow(footer, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(footer, 6, 0);
    lv_obj_set_style_pad_top(footer, 6, 0);
    lv_obj_set_style_border_width(footer, 1, 0);
    lv_obj_set_style_border_side(footer, LV_BORDER_SIDE_TOP, 0);
    lv_obj_set_style_border_color(footer, lv_color_make(67, 73, 94), 0);
    lv_obj_remove_flag(footer, LV_OBJ_FLAG_SCROLLABLE);
    createFooterButton(footer, #$EF#$80#$91, MENU_SHUTDOWN);
    createFooterButton(footer, #$EF#$8B#$B9, MENU_RESTART);
    createFooterButton(footer, #$EF#$84#$A0, MENU_CONSOLE);

    lv_obj_move_foreground(cursor_obj);
end;

procedure destroyResultsPanel;
begin
    if results_panel = nil then exit;
    lv_obj_delete(results_panel);
    results_panel := nil;
    results_list := nil;
    empty_label := nil;
    first_result := nil;
end;

procedure filterResults;
var
    query: pchar;
    i, count: sint32;
    btn: Plv_obj;
    entry: PProgEntry;
begin
    if results_panel = nil then exit;
    query := lv_textarea_get_text(search_ta);
    first_result := nil;

    count := sint32(lv_obj_get_child_count(results_list));
    for i := 1 to count - 1 do begin
        btn := lv_obj_get_child(results_list, i);
        entry := PProgEntry(lv_obj_get_user_data(btn));
        if entry^.active and ((query = nil) or (query^ = #0) or
            stringContainsCI(entry^.name, query)) then begin
            lv_obj_remove_flag(btn, LV_OBJ_FLAG_HIDDEN);
            if first_result = nil then begin
                first_result := entry;
                lv_obj_set_style_border_side(btn, LV_BORDER_SIDE_NONE, 0);
            end else
                lv_obj_set_style_border_side(btn, LV_BORDER_SIDE_TOP, 0);
        end else
            lv_obj_add_flag(btn, LV_OBJ_FLAG_HIDDEN);
    end;

    if first_result = nil then
        lv_obj_remove_flag(empty_label, LV_OBJ_FLAG_HIDDEN)
    else
        lv_obj_add_flag(empty_label, LV_OBJ_FLAG_HIDDEN);
    lv_obj_scroll_to_y(results_list, 0, LV_ANIM_OFF);
end;

{ ============================================================
  Search textarea event handler
  ============================================================ }
procedure openAppMenu;
begin
    if not search_active then begin
        search_active := true;
        lv_obj_set_style_bg_opa(search_ta, LV_OPA_COVER, LV_PART_CURSOR);
        lv_obj_set_style_anim_duration(search_ta, 400, LV_PART_CURSOR);
        lv_group_add_obj(lvgl_get_kb_group, search_ta);
        createResultsPanel;
        filterResults;
    end;
    lv_group_focus_obj(search_ta);
end;

procedure search_event_cb(e: Plv_event); cdecl;
var
    code   : uint32;
begin
    code := lv_event_get_code(e);

    if code = LV_EVENT_CLICKED then
        openAppMenu
    else if code = LV_EVENT_VALUE_CHANGED then begin
        { Text changed — only filter if search is active }
        if search_active then begin
            createResultsPanel;
            filterResults;
        end;
    end
    else if code = LV_EVENT_READY then
        launchResult(first_result);
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
  Mode-change callback — fired by GPU framework after setMode
  ============================================================ }
procedure desktopModeChanged(const info : TGPUModeInfo);
begin
    relayout;
end;

{ ============================================================
  Init — create the driver.video.desktop UI
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
    debug.tracer.push_trace('driver.video.desktop.init.enter');

    sysinfo_win_id := 0;
    results_panel  := nil;
    search_active  := false;

    scr := lv_screen_active;
    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);

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
    lv_obj_set_size(search_ta, RESULTS_W, DOCK_ITEM_H);
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

    { Don't add to driver.hid.keyboard group yet — user must click to activate }

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
    registerProgram('Tasks', @openTasks);

    { Register for resolution-change notifications from GPU framework }
    driver.video.gpu.registerModeChangeCallback(@desktopModeChanged);

    debug.tracer.pop_trace;
end;

{ ============================================================
  Relayout — reposition all driver.video.desktop UI after resolution change
  ============================================================ }
procedure relayout;
var
    scr_w, scr_h : sint32;
    dock_w       : sint32;
    dock_x       : sint32;
    dock_y       : sint32;
begin
    debug.tracer.push_trace('driver.video.desktop.relayout');

    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);

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

    debug.tracer.pop_trace;
end;

{ ============================================================
  Update — called each frame from main loop
  ============================================================ }
procedure update;
begin
    if takeWindowsKeyPress then
        openAppMenu;
    if takeTasksShortcut then begin
        if search_active then clearAndClose;
        openTasks;
    end;
    updateClockText;
end;

end.
