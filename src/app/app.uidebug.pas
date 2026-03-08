{
    Driver->Video->UIDebug - Toggleable UI debug overlay.

    Shows real-time diagnostic information:
      - FPS (frames per second)
      - Open driver.video.windows count
      - Total LVGL widget count
      - Mouse position
      - LVGL tick count
      - Total system memory
      - Screen resolution

    Toggle with F12 or programmatically via toggle procedure.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.uidebug;

interface

uses
    driver.video.lvgl, driver.video.windows, driver.hid.mouse, driver.video, arch.x86.multiboot, debug.tracer;

{ Call once per frame from the main loop (before lvgl_handler). }
procedure update;

{ Toggle the debug overlay on/off. }
procedure toggle;

{ Query whether the overlay is currently visible. }
function  isVisible: boolean;

implementation

const
    PANEL_W       = 220;
    PANEL_H       = 280;
    PANEL_PAD     = 8;
    PANEL_MARGIN  = 8;
    ROW_HEIGHT    = 18;
    FPS_INTERVAL  = 1000;    { recalculate FPS every 1000ms }

    GRAPH_W       = 200;     { pixels wide (PANEL_W - 2*PANEL_PAD - 4) }
    GRAPH_H       = 80;      { pixels tall }
    GRAPH_SAMPLES = 60;      { number of FPS history points }
    GRAPH_MAX_FPS = 120;     { Y axis max }

var
    overlay       : Plv_obj;   { semi-transparent panel }
    lbl_fps       : Plv_obj;
    lbl_windows   : Plv_obj;
    lbl_widgets   : Plv_obj;
    lbl_mouse     : Plv_obj;
    lbl_ticks     : Plv_obj;
    lbl_memory    : Plv_obj;
    lbl_resolution: Plv_obj;

    { FPS graph }
    graph_cont    : Plv_obj;   { container with dark bg }
    graph_line    : Plv_obj;   { lv_line widget }
    fps_history   : array[0..GRAPH_SAMPLES-1] of uint32;  { ring buffer }
    graph_points  : array[0..GRAPH_SAMPLES-1] of lv_point_t; { line points }
    hist_index    : uint32;    { next write position in ring }
    hist_count    : uint32;    { samples collected so far }

    visible       : boolean;

    { FPS tracking }
    frame_count   : uint32;
    last_tick     : uint32;
    current_fps   : uint32;

{ ============================================================
  Safe 32-bit division (avoids FPC promoting to int64)
  ============================================================ }
function safeDiv32(a, b: uint32): uint32;
begin
    if b = 0 then
        safeDiv32 := 0
    else
        safeDiv32 := a div b;
end;

{ ============================================================
  Count all LVGL objects recursively from a root
  ============================================================ }
function countChildrenRecursive(obj: Plv_obj): uint32;
var
    i, n   : uint32;
    total  : uint32;
    child  : Plv_obj;
begin
    n := lv_obj_get_child_count(obj);
    total := n;
    { We cannot iterate children without lv_obj_get_child_by_index,
      so we just report the direct child count of screen.
      For a deeper count we'd need that binding. }
    countChildrenRecursive := total;
end;

{ ============================================================
  Create a label row inside the overlay panel
  ============================================================ }
function makeRow(parent: Plv_obj): Plv_obj;
var
    lbl: Plv_obj;
begin
    lbl := lv_label_create(parent);
    lv_label_set_text(lbl, '...');
    lv_obj_set_style_text_color(lbl, lv_color_make(200, 200, 200), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_CLIP);
    makeRow := lbl;
end;

{ ============================================================
  Build the overlay panel
  ============================================================ }
procedure createOverlay;
var
    scr: Plv_obj;
begin
    scr := lv_screen_active;

    overlay := lv_obj_create(scr);
    lv_obj_remove_style_all(overlay);
    lv_obj_set_pos(overlay, PANEL_MARGIN, PANEL_MARGIN);
    lv_obj_set_style_bg_color(overlay, lv_color_make(0, 0, 0), 0);
    lv_obj_set_style_bg_opa(overlay, 180, 0);
    lv_obj_set_style_radius(overlay, 6, 0);
    lv_obj_set_style_border_width(overlay, 1, 0);
    lv_obj_set_style_border_color(overlay, lv_color_make(200, 200, 200), 0);
    lv_obj_set_style_border_opa(overlay, 120, 0);
    lv_obj_set_style_pad_left(overlay, PANEL_PAD, 0);
    lv_obj_set_style_pad_right(overlay, PANEL_PAD, 0);
    lv_obj_set_style_pad_top(overlay, PANEL_PAD, 0);
    lv_obj_set_style_pad_bottom(overlay, PANEL_PAD, 0);
    lv_obj_set_style_layout(overlay, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(overlay, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(overlay, 4, 0);
    lv_obj_remove_flag(overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(overlay, LV_SCROLLBAR_MODE_OFF);
    lv_obj_remove_flag(overlay, LV_OBJ_FLAG_CLICKABLE);

    lbl_fps        := makeRow(overlay);
    lbl_windows    := makeRow(overlay);
    lbl_widgets    := makeRow(overlay);
    lbl_mouse      := makeRow(overlay);
    lbl_ticks      := makeRow(overlay);
    lbl_memory     := makeRow(overlay);
    lbl_resolution := makeRow(overlay);
    lv_obj_set_style_pad_bottom(lbl_resolution, 10, 0);

    { ---- FPS graph container ---- }
    graph_cont := lv_obj_create(overlay);
    lv_obj_remove_style_all(graph_cont);
    lv_obj_set_size(graph_cont, GRAPH_W, GRAPH_H);
    lv_obj_set_style_bg_color(graph_cont, lv_color_make(10, 15, 10), 0);
    lv_obj_set_style_bg_opa(graph_cont, 200, 0);
    lv_obj_set_style_radius(graph_cont, 4, 0);
    lv_obj_set_style_border_width(graph_cont, 1, 0);
    lv_obj_set_style_border_color(graph_cont, lv_color_make(200, 200, 200), 0);
    lv_obj_set_style_border_opa(graph_cont, 100, 0);
    lv_obj_set_style_pad_all(graph_cont, 0, 0);
    lv_obj_remove_flag(graph_cont, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(graph_cont, LV_SCROLLBAR_MODE_OFF);

    { ---- FPS line graph ---- }
    graph_line := lv_line_create(graph_cont);
    lv_obj_remove_style_all(graph_line);
    lv_obj_set_style_line_color(graph_line, lv_color_make(200, 200, 200), 0);
    lv_obj_set_style_line_width(graph_line, 2, 0);
    lv_obj_set_style_line_rounded(graph_line, true, 0);
    lv_obj_set_style_line_opa(graph_line, 220, 0);

    { Auto-size overlay to fit children}
    lv_obj_set_size(overlay, LV_SIZE_CONTENT, LV_SIZE_CONTENT);

    { Always on top }
    lv_obj_move_foreground(overlay);
end;

{ ============================================================
  Destroy the overlay panel
  ============================================================ }
procedure destroyOverlay;
begin
    if overlay <> nil then begin
        lv_obj_delete(overlay);
        overlay        := nil;
        lbl_fps        := nil;
        lbl_windows    := nil;
        lbl_widgets    := nil;
        lbl_mouse      := nil;
        lbl_ticks      := nil;
        lbl_memory     := nil;
        lbl_resolution := nil;
        graph_cont     := nil;
        graph_line     := nil;
    end;
end;

{ ============================================================
  Static scratch buffer — avoids heap allocation every frame
  ============================================================ }
var
    buf : array[0..63] of char;

{ Append a pchar to buf starting at position pos, return new pos }
function bufAppend(src: pchar; pos: uint32): uint32;
begin
    while (src^ <> #0) and (pos < 62) do begin
        buf[pos] := src^;
        inc(pos);
        inc(src);
    end;
    buf[pos] := #0;
    bufAppend := pos;
end;

{ Append a uint32 as decimal digits to buf at pos, return new pos }
function bufAppendInt(val: uint32; pos: uint32): uint32;
var
    tmp   : array[0..11] of char;
    i, j  : uint32;
begin
    if val = 0 then begin
        if pos < 62 then begin
            buf[pos] := '0';
            inc(pos);
            buf[pos] := #0;
        end;
        bufAppendInt := pos;
        exit;
    end;
    i := 0;
    while val > 0 do begin
        tmp[i] := char((val mod 10) + ord('0'));
        val := safeDiv32(val, 10);
        inc(i);
    end;
    { reverse digits into buf }
    for j := 0 to i - 1 do begin
        if pos < 62 then begin
            buf[pos] := tmp[(i - 1) - j];
            inc(pos);
        end;
    end;
    buf[pos] := #0;
    bufAppendInt := pos;
end;

{ Append a sint32 (handles negative) to buf at pos }
function bufAppendSInt(val: sint32; pos: uint32): uint32;
begin
    if val < 0 then begin
        if pos < 62 then begin
            buf[pos] := '-';
            inc(pos);
        end;
        bufAppendSInt := bufAppendInt(uint32(-val), pos);
    end else
        bufAppendSInt := bufAppendInt(uint32(val), pos);
end;

{ ============================================================
  Rebuild graph_points[] from fps_history ring buffer and
  update the lv_line widget — zero heap allocation.
  Auto-scales Y axis to actual min/max FPS range.
  ============================================================ }
procedure updateGraph;
var
    n, i, ri      : uint32;
    fps_val       : uint32;
    fps_min       : uint32;
    fps_max       : uint32;
    fps_range     : uint32;
    x_step        : uint32;   { x spacing in 256ths of a pixel (fixed point) }
    y_scaled      : sint32;
    
begin
    if graph_line = nil then exit;

    n := hist_count;
    if n < 2 then exit;  { need at least 2 points for a line }

    if n > GRAPH_SAMPLES then n := GRAPH_SAMPLES;

    { Find min/max FPS in current history }
    fps_min := $FFFFFFFF;
    fps_max := 0;
    for i := 0 to n - 1 do begin
        if hist_count >= GRAPH_SAMPLES then
            ri := (hist_index + i) mod GRAPH_SAMPLES
        else
            ri := i;
        fps_val := fps_history[ri];
        if fps_val < fps_min then fps_min := fps_val;
        if fps_val > fps_max then fps_max := fps_val;
    end;

    { Add padding: 10% above and below, minimum range of 10 }
    fps_range := fps_max - fps_min;
    if fps_range < 10 then begin
        { Expand range symmetrically }
        if fps_min >= 5 then
            fps_min := fps_min - 5
        else
            fps_min := 0;
        fps_max := fps_min + 10;
    end else begin
        { 10% padding }
        if fps_min >= safeDiv32(fps_range, 10) then
            fps_min := fps_min - safeDiv32(fps_range, 10)
        else
            fps_min := 0;
        fps_max := fps_max + safeDiv32(fps_range, 10);
    end;
    fps_range := fps_max - fps_min;
    if fps_range = 0 then fps_range := 1;

    { Fixed-point x spacing: (GRAPH_W-1)*256 / (n-1) }
    x_step := safeDiv32((GRAPH_W - 1) * 256, n - 1);

    for i := 0 to n - 1 do begin
        { Read from ring buffer oldest first }
        if hist_count >= GRAPH_SAMPLES then
            ri := (hist_index + i) mod GRAPH_SAMPLES
        else
            ri := i;

        fps_val := fps_history[ri];
        if fps_val < fps_min then fps_val := fps_min;
        if fps_val > fps_max then fps_val := fps_max;

        graph_points[i].x := sint32(safeDiv32(i * x_step, 256));

        { Y: 0=top, GRAPH_H-1=bottom. Map fps_val relative to min/max }
        y_scaled := sint32(GRAPH_H - 1) - sint32(safeDiv32((fps_val - fps_min) * uint32(GRAPH_H - 1), fps_range));
        if y_scaled < 0 then y_scaled := 0;
        if y_scaled > sint32(GRAPH_H - 1) then y_scaled := sint32(GRAPH_H - 1);
        graph_points[i].y := y_scaled;
    end;

    lv_line_set_points(graph_line, @graph_points[0], n);
end;

{ ============================================================
  Update label text values — zero heap allocation
  ============================================================ }
procedure refreshLabels;
var
    scr       : Plv_obj;
    now_tick  : uint32;
    wcount    : uint32;
    ocount    : uint32;
    mx, my    : sint32;
    mem_mb    : uint32;
    p         : uint32;
begin
    if overlay = nil then exit;

    { ---- FPS calculation ---- }
    frame_count := frame_count + 1;
    now_tick := lvgl_get_ticks;

    if (now_tick - last_tick) >= FPS_INTERVAL then begin
        current_fps := safeDiv32(frame_count * 8000, now_tick - last_tick);
        frame_count := 0;
        last_tick := now_tick;

        { Record FPS sample in ring buffer }
        fps_history[hist_index] := current_fps;
        hist_index := (hist_index + 1) mod GRAPH_SAMPLES;
        if hist_count < GRAPH_SAMPLES then
            inc(hist_count);

        updateGraph;
    end;

    p := bufAppend('FPS: ', 0);
    p := bufAppendInt(current_fps, p);
    lv_label_set_text(lbl_fps, @buf[0]);

    { ---- Window count ---- }
    wcount := driver.video.windows.getWindowCount;
    p := bufAppend('driver.video.windows: ', 0);
    p := bufAppendInt(wcount, p);
    lv_label_set_text(lbl_windows, @buf[0]);

    { ---- Widget count (screen children) ---- }
    scr := lv_screen_active;
    ocount := lv_obj_get_child_count(scr);
    p := bufAppend('Screen Widgets: ', 0);
    p := bufAppendInt(ocount, p);
    lv_label_set_text(lbl_widgets, @buf[0]);

    { ---- Mouse position ---- }
    mx := driver.hid.mouse.getMouseX;
    my := driver.hid.mouse.getMouseY;
    p := bufAppend('Mouse: ', 0);
    p := bufAppendSInt(mx, p);
    p := bufAppend(', ', p);
    p := bufAppendSInt(my, p);
    lv_label_set_text(lbl_mouse, @buf[0]);

    { ---- LVGL ticks ---- }
    p := bufAppend('Ticks: ', 0);
    p := bufAppendInt(now_tick, p);
    lv_label_set_text(lbl_ticks, @buf[0]);

    { ---- Total memory ---- }
    mem_mb := safeDiv32(multibootinfo^.mem_upper + 1000, 1024) + 1;
    p := bufAppend('Memory: ', 0);
    p := bufAppendInt(mem_mb, p);
    p := bufAppend(' MB', p);
    lv_label_set_text(lbl_memory, @buf[0]);

    { ---- Resolution ---- }
    p := bufAppend('Res: ', 0);
    p := bufAppendInt(driver.video.frontBufferWidth, p);
    p := bufAppend('x', p);
    p := bufAppendInt(driver.video.frontBufferHeight, p);
    lv_label_set_text(lbl_resolution, @buf[0]);

    { Keep overlay on top }
    lv_obj_move_foreground(overlay);
end;

{ ============================================================
  Public API
  ============================================================ }
procedure update;
begin
    if visible then
        refreshLabels;
end;

procedure toggle;
begin
    if visible then begin
        destroyOverlay;
        visible := false;
    end else begin
        frame_count := 0;
        last_tick := lvgl_get_ticks;
        current_fps := 0;
        hist_index := 0;
        hist_count := 0;
        createOverlay;
        visible := true;
    end;
end;

function isVisible: boolean;
begin
    isVisible := visible;
end;

end.
