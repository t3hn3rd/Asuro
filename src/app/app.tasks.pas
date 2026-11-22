unit app.tasks;

interface

procedure openTasks;

implementation

uses
    arch.platform.cpu, core.util, core.strings, core.ds.lists, memory.heap,
    proc.mgr, proc.types, driver.hid.mouse, driver.video, driver.video.lvgl, driver.video.windows;

const
    TASKS_W = 740;
    TASKS_H = 420;
    REFRESH_MS = 1000;
    COLUMN_COUNT = 8;
    TABLE_PAD = 20;
    SCROLLBAR_GUTTER = 10;
    CELL_PAD = 6;
    ROW_HEIGHT = 30;
    COLUMN_MIN = 20;
    INITIAL_WEIGHTS : array[0..COLUMN_COUNT - 1] of sint32 = (0, 130, 64, 60, 70, 74, 70, 66);

type
    PTaskInfo = ^TTaskInfo;
    TTaskInfo = record
        pid, cpu_ticks, stack_kib, bindings : uint32;
        name : array[0..31] of char;
        state : TProcessState;
        priority : uint8;
        quantum : uint16;
    end;

var
    window_id, selected_pid : uint32;
    has_selection : boolean;
    task_header, task_list, kill_button : Plv_obj;
    column_widths, column_weights, column_mins : array[0..COLUMN_COUNT - 1] of sint32;
    drag_x : sint32;
    dragging_column : boolean;
    refresh_timer : Plv_timer;

function stateText(state: TProcessState): pchar;
begin
    case state of
        psCreated:   stateText := 'Created';
        psRunning:   stateText := 'Running';
        psReady:     stateText := 'Ready';
        psSuspended: stateText := 'Suspended';
        psAwaiting:  stateText := 'Awaiting';
        psFinished:  stateText := 'Finished';
        psError:     stateText := 'Error';
    end;
end;

procedure setNumber(label_obj: Plv_obj; number: uint32);
var
    value : pchar;
begin
    value := intToString(number);
    lv_label_set_text(label_obj, value);
    kfree(void(value));
end;

{ Copy only the fields the UI needs while the scheduler cannot reap a task. }
function snapshotTasks(entries: PTaskInfo; capacity: uint32): uint32;
var
    i, count : uint32;
    ctx : PProcessContext;
    entry : PTaskInfo;
    flags : PtrUInt;
begin
    count := 0;
    entry := entries;
    flags := arch.platform.cpu.lock;
    for i := 1 to capacity do begin
        ctx := getProcessByIndex(i - 1);
        if ctx = nil then break;
        if (ctx^.State = psFinished) or (ctx^.State = psError) then continue;
        entry^.pid := ctx^.ProcessID;
        entry^.name := ctx^.Name;
        entry^.state := ctx^.State;
        entry^.priority := ctx^.Priority;
        entry^.quantum := ctx^.Quantum;
        entry^.cpu_ticks := ctx^.CpuTicks;
        entry^.stack_kib := (ctx^.StackTop - PtrUInt(ctx^.StackBase)) div 1024;
        entry^.bindings := 0;
        if ctx^.Resources <> nil then
            entry^.bindings := DL_Size(PDList(ctx^.Resources));
        inc(entry);
        inc(count);
    end;
    arch.platform.cpu.unlock(flags);
    snapshotTasks := count;
end;

procedure updateSelection;
var
    i, count, pid : uint32;
    row : Plv_obj;
    found : boolean;
begin
    found := false;
    count := lv_obj_get_child_count(task_list);
    for i := 1 to count do begin
        row := lv_obj_get_child(task_list, sint32(i - 1));
        pid := uint32(lv_obj_get_user_data(row));
        if has_selection and (pid = selected_pid) then begin
            found := true;
            lv_obj_set_style_bg_color(row, lv_color_make(62, 82, 117), 0);
        end else
            lv_obj_set_style_bg_color(row, lv_color_make(37, 41, 54), 0);
    end;
    has_selection := found;
    if found and (selected_pid <> 0) and (selected_pid <> CurrentProcess^.ProcessID) then
        lv_obj_remove_state(kill_button, LV_STATE_DISABLED)
    else
        lv_obj_add_state(kill_button, LV_STATE_DISABLED);
end;

procedure selectTask(e: Plv_event); cdecl;
begin
    selected_pid := uint32(lv_obj_get_user_data(lv_event_get_target(e)));
    has_selection := true;
    updateSelection;
end;

procedure sizeRow(row: Plv_obj);
var
    col : sint32;
begin
    for col := 0 to COLUMN_COUNT - 1 do
        lv_obj_set_width(lv_obj_get_child(row, col), column_widths[col]);
end;

procedure applyColumnWidths;
var
    i, count : uint32;
begin
    sizeRow(task_header);
    count := lv_obj_get_child_count(task_list);
    for i := 1 to count do
        sizeRow(lv_obj_get_child(task_list, sint32(i - 1)));
end;

procedure resizeTasks(id: uint32; new_w, new_h: sint32);
var
    col, available, total_weight, assigned : sint32;
begin
    available := new_w - 2 * TABLE_PAD - SCROLLBAR_GUTTER;
    total_weight := 0;
    for col := 0 to COLUMN_COUNT - 1 do begin
        available := available - column_mins[col];
        total_weight := total_weight + column_weights[col];
    end;
    if available < 0 then available := 0;
    assigned := 0;
    for col := 0 to COLUMN_COUNT - 2 do begin
        column_widths[col] := column_mins[col] + available * column_weights[col] div total_weight;
        assigned := assigned + column_widths[col] - column_mins[col];
    end;
    column_widths[COLUMN_COUNT - 1] := column_mins[COLUMN_COUNT - 1] + available - assigned;
    applyColumnWidths;
end;

procedure resizeColumn(e: Plv_event); cdecl;
var
    code : uint32;
    col, i, mouse_x, delta, lower, upper : sint32;
begin
    code := lv_event_get_code(e);
    if code = LV_EVENT_PRESSED then begin
        drag_x := getMouseX;
        dragging_column := true;
    end else if (code = LV_EVENT_RELEASED) or (code = LV_EVENT_PRESS_LOST) then
        dragging_column := false
    else if (code = LV_EVENT_PRESSING) and dragging_column then begin
        col := sint32(lv_event_get_user_data(e));
        mouse_x := getMouseX;
        lower := column_mins[col] - column_widths[col];
        upper := column_widths[col + 1] - column_mins[col + 1];
        delta := mouse_x - drag_x;
        if delta < lower then delta := lower;
        if delta > upper then delta := upper;
        if delta = 0 then exit;
        column_widths[col] := column_widths[col] + delta;
        column_widths[col + 1] := column_widths[col + 1] - delta;
        for i := 0 to COLUMN_COUNT - 1 do
            column_weights[i] := column_widths[i] - column_mins[i];
        drag_x := drag_x + delta;
        applyColumnWidths;
    end;
end;

procedure addColumnGrip(cell: Plv_obj; col: sint32);
var
    grip, line : Plv_obj;
begin
    grip := lv_obj_create(cell);
    lv_obj_remove_style_all(grip);
    lv_obj_remove_flag(grip, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(grip, LV_OBJ_FLAG_CLICKABLE or LV_OBJ_FLAG_PRESS_LOCK);
    lv_obj_set_size(grip, 10, ROW_HEIGHT);
    lv_obj_align(grip, LV_ALIGN_RIGHT_MID, CELL_PAD, 0);
    lv_obj_add_event_cb(grip, @resizeColumn, LV_EVENT_PRESSED, pointer(col));
    lv_obj_add_event_cb(grip, @resizeColumn, LV_EVENT_PRESSING, pointer(col));
    lv_obj_add_event_cb(grip, @resizeColumn, LV_EVENT_RELEASED, nil);
    lv_obj_add_event_cb(grip, @resizeColumn, LV_EVENT_PRESS_LOST, nil);

    line := lv_obj_create(grip);
    lv_obj_remove_style_all(line);
    lv_obj_remove_flag(line, LV_OBJ_FLAG_CLICKABLE or LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(line, 1, 16);
    lv_obj_set_style_bg_color(line, lv_color_make(105, 115, 145), 0);
    lv_obj_set_style_bg_opa(line, LV_OPA_COVER, 0);
    lv_obj_center(line);
end;

function createRow(parent: Plv_obj; header: boolean): Plv_obj;
var
    row, cell, lbl : Plv_obj;
    col : sint32;
begin
    row := lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE or LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(row, lv_pct(100), ROW_HEIGHT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(row, 1, 0);
    lv_obj_set_style_border_side(row, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_color(row, lv_color_make(65, 71, 93), 0);
    if header then
        lv_obj_set_style_bg_color(row, lv_color_make(35, 38, 48), 0)
    else begin
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_event_cb(row, @selectTask, LV_EVENT_CLICKED, nil);
    end;

    for col := 0 to COLUMN_COUNT - 1 do begin
        cell := lv_obj_create(row);
        lv_obj_remove_style_all(cell);
        lv_obj_remove_flag(cell, LV_OBJ_FLAG_SCROLLABLE or LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_size(cell, column_widths[col], lv_pct(100));
        lv_obj_set_style_pad_left(cell, CELL_PAD, 0);
        lv_obj_set_style_pad_right(cell, CELL_PAD, 0);

        lbl := lv_label_create(cell);
        lv_obj_set_size(lbl, lv_pct(100), 18);
        lv_label_set_long_mode(lbl, LV_LABEL_LONG_CLIP);
        lv_obj_set_style_text_color(lbl, lv_color_make(215, 221, 239), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lv_obj_center(lbl);
        if header and (col < COLUMN_COUNT - 1) then addColumnGrip(cell, col);
    end;
    createRow := row;
end;

function cellLabel(row: Plv_obj; col: sint32): Plv_obj;
begin
    cellLabel := lv_obj_get_child(lv_obj_get_child(row, col), 0);
end;

procedure refreshTasks(timer: Plv_timer); cdecl;
var
    entries, entry : PTaskInfo;
    capacity, count, row_count, i : uint32;
    row : Plv_obj;
begin
    capacity := processCount;
    if capacity = 0 then exit;
    entries := PTaskInfo(kalloc(capacity * sizeof(TTaskInfo)));
    if entries = nil then exit;
    count := snapshotTasks(entries, capacity);
    row_count := lv_obj_get_child_count(task_list);
    while row_count > count do begin
        dec(row_count);
        lv_obj_delete(lv_obj_get_child(task_list, sint32(row_count)));
    end;
    entry := entries;
    for i := 1 to count do begin
        if i > row_count then
            row := createRow(task_list, false)
        else
            row := lv_obj_get_child(task_list, sint32(i - 1));
        lv_obj_set_user_data(row, pointer(entry^.pid));
        setNumber(cellLabel(row, 0), entry^.pid);
        lv_label_set_text(cellLabel(row, 1), @entry^.name[0]);
        lv_label_set_text(cellLabel(row, 2), stateText(entry^.state));
        setNumber(cellLabel(row, 3), entry^.priority);
        setNumber(cellLabel(row, 4), entry^.quantum);
        setNumber(cellLabel(row, 5), entry^.cpu_ticks);
        if entry^.pid = 0 then
            lv_label_set_text(cellLabel(row, 6), '-')
        else
            setNumber(cellLabel(row, 6), entry^.stack_kib);
        setNumber(cellLabel(row, 7), entry^.bindings);
        inc(entry);
    end;
    kfree(void(entries));
    updateSelection;
end;

procedure killTask(e: Plv_event); cdecl;
begin
    if not has_selection then exit;
    if (selected_pid = 0) or (selected_pid = CurrentProcess^.ProcessID) then exit;
    proc.mgr.kill(selected_pid);
    has_selection := false;
    refreshTasks(nil);
end;

procedure closeTasks(id: uint32);
begin
    if refresh_timer <> nil then lv_timer_delete(refresh_timer);
    refresh_timer := nil;
    window_id := 0;
    has_selection := false;
    dragging_column := false;
    destroyWindow(id);
end;

procedure openTasks;
var
    content, header_area, footer, caption : Plv_obj;
    w, h, scr_w, scr_h, i, digit_width, max_digit_width : sint32;
    digit : array[0..1] of char;
begin
    if isWindowOpen(window_id) then begin
        focusWindow(window_id);
        exit;
    end;

    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);
    w := TASKS_W;
    h := TASKS_H;
    if w > scr_w - 24 then w := scr_w - 24;
    if h > scr_h - 76 then h := scr_h - 76;
    window_id := createWindow('Tasks', (scr_w - w) div 2,
        (scr_h - 52 - h) div 2, w, h, @closeTasks, nil);
    if window_id = 0 then exit;
    lv_obj_set_parent(getWindowFrame(window_id), lv_layer_top);

    content := getWindowContent(window_id);
    lv_obj_remove_flag(content, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_left(content, TABLE_PAD, 0);
    lv_obj_set_style_pad_right(content, TABLE_PAD, 0);

    max_digit_width := 0;
    digit[1] := #0;
    for i := 0 to 9 do begin
        digit[0] := char(ord('0') + i);
        digit_width := lv_text_get_width(@digit[0], 1, @lv_font_montserrat_14, 0);
        if digit_width > max_digit_width then max_digit_width := digit_width;
    end;
    for i := 0 to COLUMN_COUNT - 1 do begin
        column_mins[i] := COLUMN_MIN;
        column_weights[i] := INITIAL_WEIGHTS[i];
        column_widths[i] := COLUMN_MIN;
    end;
    column_mins[0] := 10 * max_digit_width + 2 * CELL_PAD;

    header_area := lv_obj_create(content);
    lv_obj_remove_style_all(header_area);
    lv_obj_remove_flag(header_area, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(header_area, lv_pct(100), ROW_HEIGHT);
    lv_obj_set_style_pad_right(header_area, SCROLLBAR_GUTTER, 0);
    task_header := createRow(header_area, true);
    lv_label_set_text(cellLabel(task_header, 0), 'PID');
    lv_label_set_text(cellLabel(task_header, 1), 'Task');
    lv_label_set_text(cellLabel(task_header, 2), 'State');
    lv_label_set_text(cellLabel(task_header, 3), 'Priority');
    lv_label_set_text(cellLabel(task_header, 4), 'Quantum');
    lv_label_set_text(cellLabel(task_header, 5), 'CPU ticks');
    lv_label_set_text(cellLabel(task_header, 6), 'Stack KiB');
    lv_label_set_text(cellLabel(task_header, 7), 'Bindings');

    task_list := lv_obj_create(content);
    lv_obj_remove_style_all(task_list);
    lv_obj_set_size(task_list, lv_pct(100), 0);
    lv_obj_set_flex_grow(task_list, 1);
    lv_obj_set_flex_flow(task_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_right(task_list, SCROLLBAR_GUTTER, 0);
    lv_obj_set_scroll_dir(task_list, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(task_list, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_set_style_width(task_list, 4, LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_opa(task_list, LV_OPA_COVER, LV_PART_SCROLLBAR);
    lv_obj_set_style_bg_color(task_list, lv_color_make(105, 115, 145), LV_PART_SCROLLBAR);

    footer := lv_obj_create(content);
    lv_obj_remove_style_all(footer);
    lv_obj_set_size(footer, lv_pct(100), 36);
    lv_obj_remove_flag(footer, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(footer, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(footer, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    kill_button := lv_button_create(footer);
    lv_obj_set_size(kill_button, 100, 32);
    lv_obj_set_style_bg_color(kill_button, lv_color_make(158, 58, 67), 0);
    lv_obj_add_event_cb(kill_button, @killTask, LV_EVENT_CLICKED, nil);
    caption := lv_label_create(kill_button);
    lv_label_set_text(caption, 'Kill task');
    lv_obj_center(caption);
    setWindowMinWidth(window_id, 2 * TABLE_PAD + SCROLLBAR_GUTTER +
        column_mins[0] + (COLUMN_COUNT - 1) * COLUMN_MIN);
    setWindowResizeCallback(window_id, @resizeTasks);
    resizeTasks(window_id, w, h);
    updateSelection;
    refreshTasks(nil);
    refresh_timer := lv_timer_create(@refreshTasks, REFRESH_MS, nil);
end;

end.
