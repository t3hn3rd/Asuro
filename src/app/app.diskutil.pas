{
    Prog->DiskUtil - GUI disk utility application.

    Provides a graphical interface for inspecting storage devices,
    managing partitions, viewing volume information, and formatting
    volumes with registered filesystems.

    Layout: sidebar (device/volume list) + detail panel.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit app.diskutil;

interface

procedure init();

implementation

uses
    driver.video.desktop,
    driver.storage.fs.mgr,
    memory.heap,
    driver.video.lvgl,
    driver.storage.vol.mbr,
    proc.mgr,
    proc.types,
    driver.storage.mgr,
    driver.storage.types,
    core.strings,
    io.syslog,
    debug.tracer,
    driver.video,
    driver.storage.vol.mgr,
    driver.video.windows,
    core.util, arch.x86.util;

const
    WIN_W = 740;
    WIN_H = 480;
    SIDEBAR_W = 210;
    { Selection modes }
    SEL_NONE   = 0;
    SEL_DEVICE = 1;
    SEL_VOLUME = 2;

var
    win_id             : uint32;
    proc_pid           : uint32;
    sidebar            : Plv_obj;
    detail             : Plv_obj;
    { Current selection }
    sel_mode           : uint32;
    sel_dev_idx        : uint32;
    sel_vol_idx        : uint32;
    { Partition slot for pending delete confirmation }
    pending_del_slot   : sint32;
    { Active msgbox (only one at a time) }
    active_mbox        : Plv_obj;
    { Widgets kept across dialogs }
    fmt_dropdown       : Plv_obj;
    add_textarea       : Plv_obj;
    add_err_lbl        : Plv_obj;
    { Sidebar item tracking for highlight }
    active_sidebar_btn : Plv_obj;
    fmt_poll_timer     : Plv_timer;
    fmt_done_flag      : uint32;
    fmt_done_error     : TError;
    fmt_done_vol_idx   : uint32;
    ui_session_id      : uint32;

type
    PFmtUICallbackCtx = ^TFmtUICallbackCtx;
    TFmtUICallbackCtx = record
        SessionID : uint32;
        VolumeIdx : uint32;
    end;

{ ============================================================
  Forward declarations
  ============================================================ }
procedure launch; forward;
procedure diskutil_entry(ctx : PProcessContext); forward;
procedure onClose(wid: uint32); forward;
procedure refreshSidebar; forward;
procedure showDeviceDetail(devIdx: uint32); forward;
procedure showVolumeDetail(volIdx: uint32); forward;
procedure clearDetail; forward;
procedure fmt_poll_cb(tmr: Plv_timer); cdecl; forward;

{ ============================================================
  Helpers — size formatting
  ============================================================ }
function formatSizeStr(bytes: uint32): pchar;
begin
    if bytes >= 1073741824 then
        formatSizeStr := stringConcat(intToString(bytes div 1073741824), ' GB')
    else if bytes >= 1048576 then
        formatSizeStr := stringConcat(intToString(bytes div 1048576), ' MB')
    else if bytes >= 1024 then
        formatSizeStr := stringConcat(intToString(bytes div 1024), ' KB')
    else
        formatSizeStr := stringConcat(intToString(bytes), ' B');
end;

function formatSizePrecise(bytes: uint32): pchar;
var
    whole, frac : uint32;
begin
    if bytes >= 1073741824 then begin
        whole := bytes div 1073741824;
        frac := ((bytes mod 1073741824) * 10) div 1073741824;
        if frac > 0 then
            formatSizePrecise := stringConcat(stringConcat(intToString(whole), stringConcat('.', intToString(frac))), ' GB')
        else
            formatSizePrecise := stringConcat(intToString(whole), ' GB');
    end else if bytes >= 1048576 then begin
        whole := bytes div 1048576;
        frac := ((bytes mod 1048576) * 10) div 1048576;
        if frac > 0 then
            formatSizePrecise := stringConcat(stringConcat(intToString(whole), stringConcat('.', intToString(frac))), ' MB')
        else
            formatSizePrecise := stringConcat(intToString(whole), ' MB');
    end else if bytes >= 1024 then begin
        whole := bytes div 1024;
        formatSizePrecise := stringConcat(intToString(whole), ' KB');
    end else
        formatSizePrecise := stringConcat(intToString(bytes), ' B');
end;

function controllerStr(ct: TControllerType): pchar;
begin
    controllerStr := driver.storage.mgr.controller_type_2_string(ct);
end;

function boolStr(b: boolean): pchar;
begin
    if b then boolStr := 'Yes'
    else boolStr := 'No';
end;

function formatErrorName(err : TError) : pchar;
begin
    case err of
        eNone: formatErrorName := 'eNone';
        eUnknown: formatErrorName := 'eUnknown';
        eNotSupported: formatErrorName := 'eNotSupported';
        eOutOfMemory: formatErrorName := 'eOutOfMemory';
        eInvalidArgument: formatErrorName := 'eInvalidArgument';
        eFileInUse: formatErrorName := 'eFileInUse';
        eFileDoesNotExist: formatErrorName := 'eFileDoesNotExist';
        eInvalidFileName: formatErrorName := 'eInvalidFileName';
        eInvalidFileExtension: formatErrorName := 'eInvalidFileExtension';
        eFilenameTooLong: formatErrorName := 'eFilenameTooLong';
        eDirectoryDoesNotExist: formatErrorName := 'eDirectoryDoesNotExist';
        eDirectoryAlreadyExists: formatErrorName := 'eDirectoryAlreadyExists';
        eDirectoryNotEmpty: formatErrorName := 'eDirectoryNotEmpty';
        eDirectoryFull: formatErrorName := 'eDirectoryFull';
        eNotADirectory: formatErrorName := 'eNotADirectory';
        eWriteOnly: formatErrorName := 'eWriteOnly';
        eReadOnly: formatErrorName := 'eReadOnly';
        ePermissionDenied: formatErrorName := 'ePermissionDenied';
        eInvalidPath: formatErrorName := 'eInvalidPath';
        eTooManyOpenFiles: formatErrorName := 'eTooManyOpenFiles';
        eInvalidHandle: formatErrorName := 'eInvalidHandle';
        eFileNotLoaded: formatErrorName := 'eFileNotLoaded';
        eAlreadyExists: formatErrorName := 'eAlreadyExists';
        eDiskFull: formatErrorName := 'eDiskFull';
        eIOError: formatErrorName := 'eIOError';
        eIOTimeout: formatErrorName := 'eIOTimeout';
        eIOCancelled: formatErrorName := 'eIOCancelled';
        eDeviceNotReady: formatErrorName := 'eDeviceNotReady';
        eCorruptFilesystem: formatErrorName := 'eCorruptFilesystem';
        eBadSector: formatErrorName := 'eBadSector';
        eAlreadyMounted: formatErrorName := 'eAlreadyMounted';
        eNotMounted: formatErrorName := 'eNotMounted';
        eUnsupportedFilesystem: formatErrorName := 'eUnsupportedFilesystem';
        eDeviceNotFound: formatErrorName := 'eDeviceNotFound';
        eDeviceRemoved: formatErrorName := 'eDeviceRemoved';
        eQueueFull: formatErrorName := 'eQueueFull';
        eNoFreeSlot: formatErrorName := 'eNoFreeSlot';
        eInvalidPartitionTable: formatErrorName := 'eInvalidPartitionTable';
        eVolumeNotFound: formatErrorName := 'eVolumeNotFound';
    else
        formatErrorName := 'eUnknown';
    end;
end;

{ Check if a pchar string contains only digits }
function isNumericStr(s: pchar): boolean;
var
    i, len : uint32;
begin
    isNumericStr := false;
    if s = nil then exit;
    len := stringSize(s);
    if len = 0 then exit;
    for i := 0 to len - 1 do begin
        if (s[i] < '0') or (s[i] > '9') then exit;
    end;
    isNumericStr := true;
end;

{ ============================================================
  GUI helpers
  ============================================================ }
procedure addInfoRow(parent: Plv_obj; row_w: sint32; key: pchar; value: pchar);
var
    row, lbl_key, lbl_val : Plv_obj;
begin
    row := lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, row_w - 24, 24);
    lv_obj_set_style_pad_all(row, 0, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lbl_key := lv_label_create(row);
    lv_label_set_text(lbl_key, key);
    lv_obj_set_style_text_color(lbl_key, lv_color_make(140, 150, 170), 0);
    lv_obj_set_style_text_font(lbl_key, @lv_font_montserrat_14, 0);

    lbl_val := lv_label_create(row);
    lv_label_set_text(lbl_val, value);
    lv_obj_set_style_text_color(lbl_val, lv_color_make(220, 225, 240), 0);
    lv_obj_set_style_text_font(lbl_val, @lv_font_montserrat_14, 0);
end;

procedure addSectionHeader(parent: Plv_obj; title: pchar);
var
    lbl : Plv_obj;
begin
    lbl := lv_label_create(parent);
    lv_label_set_text(lbl, title);
    lv_obj_set_style_text_color(lbl, lv_color_make(100, 160, 255), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
end;

procedure addSeparator(parent: Plv_obj; row_w: sint32);
var
    sep : Plv_obj;
begin
    sep := lv_obj_create(parent);
    lv_obj_remove_style_all(sep);
    lv_obj_set_size(sep, row_w - 24, 1);
    lv_obj_set_style_bg_color(sep, lv_color_make(55, 60, 78), 0);
    lv_obj_set_style_bg_opa(sep, LV_OPA_COVER, 0);
    lv_obj_remove_flag(sep, LV_OBJ_FLAG_SCROLLABLE);
end;

procedure addStatusLabel(parent: Plv_obj; text: pchar; r, g, b: uint8);
var
    lbl : Plv_obj;
begin
    lbl := lv_label_create(parent);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, lv_color_make(r, g, b), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
end;

function makeButton(parent: Plv_obj; text: pchar; w: sint32): Plv_obj;
var
    btn, lbl : Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, w, 30);
    lv_obj_set_style_bg_color(btn, lv_color_make(55, 90, 190), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, 6, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, lv_color_make(225, 230, 245), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

    makeButton := btn;
end;

function makeDangerButton(parent: Plv_obj; text: pchar; w: sint32): Plv_obj;
var
    btn, lbl : Plv_obj;
begin
    btn := lv_button_create(parent);
    lv_obj_remove_style_all(btn);
    lv_obj_set_size(btn, w, 26);
    lv_obj_set_style_bg_color(btn, lv_color_make(160, 50, 50), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, 4, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lbl := lv_label_create(btn);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, lv_color_make(240, 220, 220), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

    makeDangerButton := btn;
end;

{ Add a usage bar (colored bar showing used vs total) }
procedure addUsageBar(parent: Plv_obj; row_w: sint32; used, total: uint32);
var
    bar : Plv_obj;
    pct : sint32;
begin
    if total = 0 then pct := 0
    else pct := sint32((used * 100) div total);
    if pct > 100 then pct := 100;

    bar := lv_bar_create(parent);
    lv_obj_set_size(bar, row_w - 24, 14);
    lv_bar_set_range(bar, 0, 100);
    lv_bar_set_value(bar, pct, LV_ANIM_OFF);

    { Track background }
    lv_obj_set_style_bg_color(bar, lv_color_make(45, 48, 60), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(bar, 4, LV_PART_MAIN);

    { Fill indicator }
    if pct < 75 then
        lv_obj_set_style_bg_color(bar, lv_color_make(70, 160, 100), LV_PART_INDICATOR)
    else if pct < 90 then
        lv_obj_set_style_bg_color(bar, lv_color_make(200, 170, 50), LV_PART_INDICATOR)
    else
        lv_obj_set_style_bg_color(bar, lv_color_make(200, 60, 60), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(bar, 4, LV_PART_INDICATOR);
end;

{ ============================================================
  Size parser — accepts '500MB', '2GB', '1024KB', '4096B',
                or plain number (bytes). Returns sector count.
                Returns 0 on invalid input.
  ============================================================ }
function parseSize(s: pchar; sectorSize: uint32): uint32;
var
    len    : uint32;
    last   : char;
    prev   : char;
    numEnd : uint32;
    value  : uint32;
    bytes  : uint32;
begin
    parseSize := 0;
    if s = nil then exit;
    len := stringSize(s);
    if len = 0 then exit;

    last := s[len - 1];

    if (last = 'B') or (last = 'b') then begin
        if len >= 3 then
            prev := s[len - 2]
        else
            prev := #0;

        if (prev = 'G') or (prev = 'g') then begin
            numEnd := len - 2;
            s[numEnd] := #0;
            if not isNumericStr(s) then begin s[numEnd] := prev; exit; end;
            value := stringToInt(s);
            s[numEnd] := prev;
            if value = 0 then exit;
            bytes := value * 1073741824;
        end else if (prev = 'M') or (prev = 'm') then begin
            numEnd := len - 2;
            s[numEnd] := #0;
            if not isNumericStr(s) then begin s[numEnd] := prev; exit; end;
            value := stringToInt(s);
            s[numEnd] := prev;
            if value = 0 then exit;
            bytes := value * 1048576;
        end else if (prev = 'K') or (prev = 'k') then begin
            numEnd := len - 2;
            s[numEnd] := #0;
            if not isNumericStr(s) then begin s[numEnd] := prev; exit; end;
            value := stringToInt(s);
            s[numEnd] := prev;
            if value = 0 then exit;
            bytes := value * 1024;
        end else begin
            { Just 'B' suffix — plain bytes }
            numEnd := len - 1;
            s[numEnd] := #0;
            if not isNumericStr(s) then begin s[numEnd] := last; exit; end;
            value := stringToInt(s);
            s[numEnd] := last;
            if value = 0 then exit;
            bytes := value;
        end;
    end else begin
        { Plain number (bytes) }
        if not isNumericStr(s) then exit;
        bytes := stringToInt(s);
        if bytes = 0 then exit;
    end;

    if sectorSize = 0 then exit;
    parseSize := bytes div sectorSize;
end;

{ ============================================================
  Close any active message box
  ============================================================ }
procedure closeMsgBox;
begin
    if active_mbox <> nil then begin
        lv_msgbox_close(active_mbox);
        active_mbox := nil;
    end;
    add_textarea := nil;
    add_err_lbl := nil;
    fmt_dropdown := nil;
end;

{ ============================================================
  Dialog callbacks — Add Partition
  ============================================================ }
procedure add_part_ok_cb(e: Plv_event); cdecl;
var
    code    : uint32;
    device  : PStorage_Device;
    text    : pchar;
    sectors : uint32;
    freeSec : uint32;
    slot    : sint32;
    lba     : uint32;
    part    : TPartition_table;
    mbr_rec : PMaster_Boot_Record;
    needsInit : boolean;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;

    device := driver.storage.mgr.get_device(sel_dev_idx);
    if device = nil then begin closeMsgBox; exit; end;

    { Check cached mbr to decide if disk needs initialisation }
    mbr_rec := driver.storage.mgr.get_cached_mbr(device);
    needsInit := (mbr_rec = nil) or (mbr_rec^.boot_sector <> $AA55);

    if needsInit then
        freeSec := device^.maxSectorCount - 1
    else
        freeSec := driver.storage.vol.mgr.get_free_sector_count(device);

    text := lv_textarea_get_text(add_textarea);
    sectors := 0;

    { Parse size if provided }
    if (text <> nil) and (text^ <> #0) then begin
        sectors := parseSize(text, device^.sectorSize);
        if sectors = 0 then begin
            if add_err_lbl <> nil then
                lv_label_set_text(add_err_lbl, 'Invalid size. Use e.g. 100MB, 2GB, 512KB.')
            else begin
                add_err_lbl := lv_label_create(lv_msgbox_get_content(active_mbox));
                lv_label_set_text(add_err_lbl, 'Invalid size. Use e.g. 100MB, 2GB, 512KB.');
                lv_obj_set_style_text_color(add_err_lbl, lv_color_make(230, 80, 80), 0);
                lv_obj_set_style_text_font(add_err_lbl, @lv_font_montserrat_14, 0);
            end;
            exit;
        end;
        if sectors > freeSec then begin
            if add_err_lbl <> nil then
                lv_label_set_text(add_err_lbl, 'Requested size exceeds available free space.')
            else begin
                add_err_lbl := lv_label_create(lv_msgbox_get_content(active_mbox));
                lv_label_set_text(add_err_lbl, 'Requested size exceeds available free space.');
                lv_obj_set_style_text_color(add_err_lbl, lv_color_make(230, 80, 80), 0);
                lv_obj_set_style_text_font(add_err_lbl, @lv_font_montserrat_14, 0);
            end;
            exit;
        end;
    end;

    { If blank, use all free space }
    if sectors = 0 then
        sectors := freeSec;

    if sectors = 0 then begin closeMsgBox; exit; end;

    { If disk needs init, do it now (async write, but cache updated synchronously) }
    if needsInit then begin
        driver.storage.vol.mgr.init_disk_async(device, nil, nil);
        { Cache is now fresh mbr with $AA55 signature, all slots empty }
        slot := 0;
        lba := 1;
    end else begin
        slot := driver.storage.vol.mgr.find_free_slot(device);
        if slot < 0 then begin closeMsgBox; exit; end;

        lba := driver.storage.vol.mgr.find_free_space(device, sectors);
        if lba = 0 then begin
            if add_err_lbl <> nil then
                lv_label_set_text(add_err_lbl, 'Could not find contiguous free space.')
            else begin
                add_err_lbl := lv_label_create(lv_msgbox_get_content(active_mbox));
                lv_label_set_text(add_err_lbl, 'Could not find contiguous free space.');
                lv_obj_set_style_text_color(add_err_lbl, lv_color_make(230, 80, 80), 0);
                lv_obj_set_style_text_font(add_err_lbl, @lv_font_montserrat_14, 0);
            end;
            exit;
        end;
    end;

    memset(uint32(@part), 0, sizeof(TPartition_table));
    driver.storage.vol.mbr.setup_partition(@part, lba, sectors);
    driver.storage.vol.mgr.add_partition_async(device, uint32(slot), part, nil, nil);

    closeMsgBox;
    refreshSidebar;
    showDeviceDetail(sel_dev_idx);
end;

procedure add_part_cancel_cb(e: Plv_event); cdecl;
var code : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    closeMsgBox;
end;

{ ============================================================
  Dialog callbacks — Delete Partition
  ============================================================ }
procedure del_part_ok_cb(e: Plv_event); cdecl;
var
    code   : uint32;
    device : PStorage_Device;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;

    device := driver.storage.mgr.get_device(sel_dev_idx);
    if device = nil then begin closeMsgBox; exit; end;

    if (pending_del_slot >= 0) and (pending_del_slot <= 3) then
        driver.storage.vol.mgr.remove_partition_async(device, uint32(pending_del_slot), nil, nil);

    closeMsgBox;
    refreshSidebar;
    showDeviceDetail(sel_dev_idx);
end;

procedure del_part_cancel_cb(e: Plv_event); cdecl;
var code : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    closeMsgBox;
end;

{ Per-row delete button click — opens confirmation for that specific slot }
procedure row_del_click_cb(e: Plv_event); cdecl;
var
    code    : uint32;
    slot    : uint32;
    mbox    : Plv_obj;
    btn_ok  : Plv_obj;
    btn_no  : Plv_obj;
    txt     : pchar;
    device  : PStorage_Device;
    mbr_rec : PMaster_Boot_Record;
    part    : TPartition_table;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;

    slot := uint32(lv_event_get_user_data(e));
    pending_del_slot := sint32(slot);

    txt := stringConcat('Delete partition in slot ', intToString(slot));

    device := driver.storage.mgr.get_device(sel_dev_idx);
    if device <> nil then begin
        mbr_rec := driver.storage.mgr.get_cached_mbr(device);
        if mbr_rec <> nil then begin
            part := mbr_rec^.partition[slot];
            if part.sector_count > 0 then begin
                txt := stringConcat(txt, ' (');
                txt := stringConcat(txt, formatSizeStr(part.sector_count * device^.sectorSize));
                txt := stringConcat(txt, ')');
            end;
        end;
    end;
    txt := stringConcat(txt, '?');

    closeMsgBox;
    mbox := lv_msgbox_create(lv_layer_top);
    active_mbox := mbox;
    lv_msgbox_add_title(mbox, 'Delete Partition');
    lv_msgbox_add_text(mbox, txt);
    addStatusLabel(lv_msgbox_get_content(mbox), 'This action cannot be undone.', 230, 160, 80);

    btn_ok := lv_msgbox_add_footer_button(mbox, 'Delete');
    lv_obj_add_event_cb(btn_ok, @del_part_ok_cb, LV_EVENT_CLICKED, nil);
    btn_no := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(btn_no, @del_part_cancel_cb, LV_EVENT_CLICKED, nil);
end;

{ ============================================================
  Dialog callbacks — Format Volume
  ============================================================ }

{ Async completion callback — fired from ISR context when format finishes.
  Only sets completion flags; LVGL work happens later on the UI poll timer. }
procedure fmt_done_cb(error : TError; userdata : pointer);
var
    ctx : PFmtUICallbackCtx;
begin
    ctx := PFmtUICallbackCtx(userdata);
    if ctx <> nil then begin
        if ctx^.SessionID = ui_session_id then begin
            fmt_done_error := error;
            fmt_done_vol_idx := ctx^.VolumeIdx;
            puint32(@fmt_done_flag)^ := 1;
        end;
        kfree(void(ctx));
    end;
end;

procedure fmt_poll_cb(tmr: Plv_timer); cdecl;
var
    mbox : Plv_obj;
begin
    if puint32(@fmt_done_flag)^ <> 1 then exit;
    puint32(@fmt_done_flag)^ := 0;

    refreshSidebar;
    showVolumeDetail(fmt_done_vol_idx);

    if fmt_done_error <> eNone then begin
        closeMsgBox;
        mbox := lv_msgbox_create(lv_layer_top);
        active_mbox := mbox;
        lv_msgbox_add_title(mbox, 'Format Failed');
        lv_msgbox_add_text(mbox, 'The volume was formatted but could not be verified.');
        lv_msgbox_add_text(mbox, formatErrorName(fmt_done_error));
        lv_msgbox_add_footer_button(mbox, 'OK');
    end;
end;

procedure fmt_ok_cb(e: Plv_event); cdecl;
var
    code   : uint32;
    selIdx : uint32;
    fs     : PFilesystem;
    vol    : PStorage_Volume;
    cbCtx  : PFmtUICallbackCtx;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;

    vol := driver.storage.vol.mgr.get_volume(sel_vol_idx);
    if vol = nil then begin closeMsgBox; exit; end;

    selIdx := lv_dropdown_get_selected(fmt_dropdown);
    fs := driver.storage.fs.mgr.get_filesystem(selIdx);
    if fs = nil then begin closeMsgBox; exit; end;

    closeMsgBox;

    cbCtx := PFmtUICallbackCtx(kalloc(sizeof(TFmtUICallbackCtx)));
    if cbCtx = nil then exit;
    cbCtx^.SessionID := ui_session_id;
    cbCtx^.VolumeIdx := sel_vol_idx;

    { Submit async format — returns immediately, fmt_done_cb only flips a flag. }
    if not driver.storage.vol.mgr.format_volume_async(vol^.device, sel_vol_idx, fs^.sName, nil,
        @fmt_done_cb, cbCtx) then begin
        kfree(void(cbCtx));
        closeMsgBox;
        active_mbox := lv_msgbox_create(lv_layer_top);
        lv_msgbox_add_title(active_mbox, 'Format Failed');
        lv_msgbox_add_text(active_mbox, 'Could not start the format operation.');
        lv_msgbox_add_footer_button(active_mbox, 'OK');
    end;
end;

procedure fmt_cancel_cb(e: Plv_event); cdecl;
var code : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    closeMsgBox;
end;

{ ============================================================
  Button click handler — Add Partition
  ============================================================ }
procedure btn_add_part_cb(e: Plv_event); cdecl;
var
    code    : uint32;
    device  : PStorage_Device;
    mbox    : Plv_obj;
    body    : Plv_obj;
    btn_ok  : Plv_obj;
    btn_no  : Plv_obj;
    freeSec : uint32;
    freeSlot: sint32;
    infoTxt : pchar;
    freeSlotCnt : uint32;
    i       : sint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    closeMsgBox;

    device := driver.storage.mgr.get_device(sel_dev_idx);
    if device = nil then exit;

    { Validate: writable }
    if not device^.writable then begin
        mbox := lv_msgbox_create(lv_layer_top);
        active_mbox := mbox;
        lv_msgbox_add_title(mbox, 'Cannot Add Partition');
        lv_msgbox_add_text(mbox, 'This device is read-only.');
        btn_no := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(btn_no, @add_part_cancel_cb, LV_EVENT_CLICKED, nil);
        exit;
    end;

    { Validate: free slot available }
    freeSlot := driver.storage.vol.mgr.find_free_slot(device);
    if freeSlot < 0 then begin
        mbox := lv_msgbox_create(lv_layer_top);
        active_mbox := mbox;
        lv_msgbox_add_title(mbox, 'Cannot Add Partition');
        lv_msgbox_add_text(mbox, 'All 4 partition slots are in use.');
        btn_no := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(btn_no, @add_part_cancel_cb, LV_EVENT_CLICKED, nil);
        exit;
    end;

    { Validate: free space exists }
    freeSec := driver.storage.vol.mgr.get_free_sector_count(device);
    if freeSec = 0 then begin
        mbox := lv_msgbox_create(lv_layer_top);
        active_mbox := mbox;
        lv_msgbox_add_title(mbox, 'Cannot Add Partition');
        lv_msgbox_add_text(mbox, 'No free space available on this device.');
        btn_no := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(btn_no, @add_part_cancel_cb, LV_EVENT_CLICKED, nil);
        exit;
    end;

    { Count free slots }
    freeSlotCnt := 0;
    for i := 0 to 3 do begin
        if driver.storage.vol.mgr.find_free_slot(device) >= 0 then
            freeSlotCnt := freeSlotCnt + 1;
    end;
    { Simpler: just use the volumes count }
    if device^.volumes <> nil then
        freeSlotCnt := 4 - device^.volumes^.Count
    else
        freeSlotCnt := 4;

    { Show dialog with context info }
    mbox := lv_msgbox_create(lv_layer_top);
    active_mbox := mbox;
    lv_msgbox_add_title(mbox, 'Add Partition');

    infoTxt := stringConcat('Free space: ', formatSizePrecise(freeSec * device^.sectorSize));
    infoTxt := stringConcat(infoTxt, '   |   Free slots: ');
    infoTxt := stringConcat(infoTxt, intToString(freeSlotCnt));

    lv_msgbox_add_text(mbox, infoTxt);
    lv_msgbox_add_text(mbox, 'Enter size (e.g. 100MB, 2GB) or leave blank for all free space:');

    body := lv_msgbox_get_content(mbox);
    add_textarea := lv_textarea_create(body);
    lv_textarea_set_one_line(add_textarea, true);
    lv_textarea_set_placeholder_text(add_textarea, formatSizeStr(freeSec * device^.sectorSize));
    lv_obj_set_width(add_textarea, 280);
    add_err_lbl := nil;

    btn_ok := lv_msgbox_add_footer_button(mbox, 'Create');
    lv_obj_add_event_cb(btn_ok, @add_part_ok_cb, LV_EVENT_CLICKED, nil);
    btn_no := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(btn_no, @add_part_cancel_cb, LV_EVENT_CLICKED, nil);
end;

{ ============================================================
  Button click handler — Format Volume
  ============================================================ }
procedure btn_format_cb(e: Plv_event); cdecl;
var
    code    : uint32;
    vol     : PStorage_Volume;
    mbox    : Plv_obj;
    body    : Plv_obj;
    btn_ok  : Plv_obj;
    btn_no  : Plv_obj;
    i       : uint32;
    fs      : PFilesystem;
    opts    : pchar;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    closeMsgBox;

    vol := driver.storage.vol.mgr.get_volume(sel_vol_idx);
    if vol = nil then exit;

    { Check writable }
    if (vol^.device <> nil) and (not vol^.device^.writable) then begin
        mbox := lv_msgbox_create(lv_layer_top);
        active_mbox := mbox;
        lv_msgbox_add_title(mbox, 'Cannot Format');
        lv_msgbox_add_text(mbox, 'The underlying device is read-only.');
        btn_no := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(btn_no, @fmt_cancel_cb, LV_EVENT_CLICKED, nil);
        exit;
    end;

    { Check filesystems available }
    if driver.storage.fs.mgr.get_filesystem_count() = 0 then begin
        mbox := lv_msgbox_create(lv_layer_top);
        active_mbox := mbox;
        lv_msgbox_add_title(mbox, 'Cannot Format');
        lv_msgbox_add_text(mbox, 'No filesystems are registered.');
        btn_no := lv_msgbox_add_footer_button(mbox, 'OK');
        lv_obj_add_event_cb(btn_no, @fmt_cancel_cb, LV_EVENT_CLICKED, nil);
        exit;
    end;

    mbox := lv_msgbox_create(lv_layer_top);
    active_mbox := mbox;
    lv_msgbox_add_title(mbox, 'Format Volume');
    lv_msgbox_add_text(mbox, 'Select filesystem. This will erase all data on the volume.');

    body := lv_msgbox_get_content(mbox);
    addStatusLabel(body,
        stringConcat('Volume size: ', formatSizePrecise(vol^.sectorCount * vol^.sectorSize)),
        160, 170, 190);

    { Build newline-separated options for dropdown }
    opts := nil;
    for i := 0 to driver.storage.fs.mgr.get_filesystem_count() - 1 do begin
        fs := driver.storage.fs.mgr.get_filesystem(i);
        if fs <> nil then begin
            if opts = nil then
                opts := fs^.sName
            else begin
                opts := stringConcat(opts, #10);
                opts := stringConcat(opts, fs^.sName);
            end;
        end;
    end;

    fmt_dropdown := lv_dropdown_create(body);
    lv_obj_set_width(fmt_dropdown, 280);
    if opts <> nil then
        lv_dropdown_set_options(fmt_dropdown, opts);

    btn_ok := lv_msgbox_add_footer_button(mbox, 'Format');
    lv_obj_add_event_cb(btn_ok, @fmt_ok_cb, LV_EVENT_CLICKED, nil);
    btn_no := lv_msgbox_add_footer_button(mbox, 'Cancel');
    lv_obj_add_event_cb(btn_no, @fmt_cancel_cb, LV_EVENT_CLICKED, nil);
end;

{ ============================================================
  Clear the detail panel
  ============================================================ }
procedure clearDetail;
begin
    if detail <> nil then
        lv_obj_clean(detail);
    sel_mode := SEL_NONE;
    pending_del_slot := -1;
end;

{ Find the volume that corresponds to a partition on a device }
function findVolumeForPartition(device: PStorage_Device; lbaStart: uint32): PStorage_Volume;
var
    i      : uint32;
    vol    : PStorage_Volume;
    volCnt : uint32;
begin
    findVolumeForPartition := nil;
    volCnt := driver.storage.vol.mgr.get_volume_count();
    for i := 0 to volCnt - 1 do begin
        vol := driver.storage.vol.mgr.get_volume(i);
        if vol = nil then continue;
        if (vol^.device = device) and (vol^.sectorStart = lbaStart) then begin
            findVolumeForPartition := vol;
            exit;
        end;
    end;
end;

{ ============================================================
  Build a single partition row with inline delete button.
  Only called for non-empty partitions.
  ============================================================ }
procedure addPartitionRow(parent: Plv_obj; row_w: sint32;
    slot: uint32; part: TPartition_table; sectorSize: uint32;
    device: PStorage_Device; canDelete: boolean);
var
    row     : Plv_obj;
    lbl     : Plv_obj;
    del_btn : Plv_obj;
    sizeStr : pchar;
    vol     : PStorage_Volume;
    freeStr : pchar;
    totalB  : uint32;
    freeB   : uint32;
begin
    row := lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, row_w - 24, 30);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, 6, 0);
    lv_obj_set_style_pad_left(row, 6, 0);
    lv_obj_set_style_pad_right(row, 6, 0);
    lv_obj_set_style_bg_color(row, lv_color_make(42, 46, 58), 0);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(row, 4, 0);

    { Slot number badge }
    lbl := lv_label_create(row);
    lv_label_set_text(lbl, intToString(slot));
    lv_obj_set_style_text_color(lbl, lv_color_make(100, 160, 255), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_width(lbl, 20);

    { System ID }
    lbl := lv_label_create(row);
    lv_label_set_text(lbl, stringConcat('ID:', intToString(part.system_id)));
    lv_obj_set_style_text_color(lbl, lv_color_make(160, 170, 190), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_width(lbl, 55);

    { Size }
    totalB := part.sector_count * sectorSize;
    sizeStr := formatSizeStr(totalB);
    lbl := lv_label_create(row);
    lv_label_set_text(lbl, sizeStr);
    lv_obj_set_style_text_color(lbl, lv_color_make(220, 225, 240), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lv_obj_set_width(lbl, 70);

    { Free space — look up the corresponding volume }
    vol := findVolumeForPartition(device, part.LBA_start);
    if vol <> nil then begin
        freeB := vol^.freeSectors * vol^.sectorSize;
        freeStr := stringConcat(formatSizeStr(freeB), ' free');
        lbl := lv_label_create(row);
        lv_label_set_text(lbl, freeStr);
        lv_obj_set_style_text_color(lbl, lv_color_make(100, 180, 130), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_width(lbl, 80);
    end else begin
        lbl := lv_label_create(row);
        lv_label_set_text(lbl, 'No FS');
        lv_obj_set_style_text_color(lbl, lv_color_make(120, 125, 145), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lv_obj_set_width(lbl, 80);
    end;

    { Boot indicator }
    if driver.storage.vol.mbr.get_bootable(@part) then begin
        lbl := lv_label_create(row);
        lv_label_set_text(lbl, 'BOOT');
        lv_obj_set_style_text_color(lbl, lv_color_make(100, 200, 120), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    end;

    { Delete button }
    if canDelete then begin
        del_btn := makeDangerButton(row, 'Del', 42);
        lv_obj_add_event_cb(del_btn, @row_del_click_cb, LV_EVENT_CLICKED, pointer(slot));
    end;
end;

{ ============================================================
  Show device detail — device info + partition list + actions
  ============================================================ }
procedure showDeviceDetail(devIdx: uint32);
var
    device      : PStorage_Device;
    btn_row     : Plv_obj;
    btn         : Plv_obj;
    dw          : sint32;
    i           : uint32;
    totalBytes  : uint32;
    usedSectors : uint32;
    freeBytes   : uint32;
    volCnt      : uint32;
    devVolCnt   : uint32;
    vol         : PStorage_Volume;
    fsName      : pchar;
    row         : Plv_obj;
    lbl         : Plv_obj;
    sizeStr     : pchar;
    freeStr     : pchar;
    totalB      : uint32;
    freeB       : uint32;
begin
    clearDetail;
    sel_mode := SEL_DEVICE;
    sel_dev_idx := devIdx;

    device := driver.storage.mgr.get_device(devIdx);
    if device = nil then begin
        addStatusLabel(detail, 'Device not found.', 230, 80, 80);
        exit;
    end;

    dw := WIN_W - SIDEBAR_W - 20;

    { ---- Device Info ---- }
    addSectionHeader(detail, 'Device Info');
    addInfoRow(detail, dw, 'Device Index', intToString(devIdx));
    addInfoRow(detail, dw, 'Controller', controllerStr(device^.controller));
    addInfoRow(detail, dw, 'Writable', boolStr(device^.writable));
    addInfoRow(detail, dw, 'Sector Size', stringConcat(intToString(device^.sectorSize), ' bytes'));
    totalBytes := device^.maxSectorCount * device^.sectorSize;
    addInfoRow(detail, dw, 'Total Size', formatSizePrecise(totalBytes));

    { Compute free space from in-memory volume data (no I/O) }
    usedSectors := 0;
    devVolCnt := 0;
    volCnt := driver.storage.vol.mgr.get_volume_count();
    for i := 0 to volCnt - 1 do begin
        vol := driver.storage.vol.mgr.get_volume(i);
        if (vol <> nil) and (vol^.device = device) then begin
            devVolCnt := devVolCnt + 1;
            usedSectors := usedSectors + vol^.sectorCount;
        end;
    end;
    if device^.maxSectorCount > usedSectors then
        freeBytes := (device^.maxSectorCount - usedSectors) * device^.sectorSize
    else
        freeBytes := 0;
    addInfoRow(detail, dw, 'Free Space', formatSizePrecise(freeBytes));
    addInfoRow(detail, dw, 'Volumes', intToString(devVolCnt));

    { Usage bar }
    if totalBytes > 0 then
        addUsageBar(detail, dw, totalBytes - freeBytes, totalBytes);

    addSeparator(detail, dw);

    { ---- Volumes on this device (from cached data — no disk I/O) ---- }
    addSectionHeader(detail, 'Volumes');

    if devVolCnt = 0 then
        addStatusLabel(detail, 'No volumes found.', 120, 125, 145)
    else begin
        for i := 0 to volCnt - 1 do begin
            vol := driver.storage.vol.mgr.get_volume(i);
            if (vol = nil) or (vol^.device <> device) then continue;

            row := lv_obj_create(detail);
            lv_obj_remove_style_all(row);
            lv_obj_set_size(row, dw - 24, 30);
            lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_layout(row, LV_LAYOUT_FLEX, 0);
            lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
            lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
            lv_obj_set_style_pad_column(row, 6, 0);
            lv_obj_set_style_pad_left(row, 6, 0);
            lv_obj_set_style_pad_right(row, 6, 0);
            lv_obj_set_style_bg_color(row, lv_color_make(42, 46, 58), 0);
            lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
            lv_obj_set_style_radius(row, 4, 0);

            { Filesystem name }
            if vol^.filesystem <> nil then
                fsName := vol^.filesystem^.sName
            else
                fsName := 'Unknown';
            lbl := lv_label_create(row);
            lv_label_set_text(lbl, fsName);
            lv_obj_set_style_text_color(lbl, lv_color_make(100, 160, 255), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_width(lbl, 70);

            { LBA start }
            lbl := lv_label_create(row);
            lv_label_set_text(lbl, stringConcat('LBA:', intToString(vol^.sectorStart)));
            lv_obj_set_style_text_color(lbl, lv_color_make(160, 170, 190), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_width(lbl, 80);

            { Size }
            totalB := vol^.sectorCount * vol^.sectorSize;
            sizeStr := formatSizeStr(totalB);
            lbl := lv_label_create(row);
            lv_label_set_text(lbl, sizeStr);
            lv_obj_set_style_text_color(lbl, lv_color_make(220, 225, 240), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_width(lbl, 70);

            { Free space }
            freeB := vol^.freeSectors * vol^.sectorSize;
            freeStr := stringConcat(formatSizeStr(freeB), ' free');
            lbl := lv_label_create(row);
            lv_label_set_text(lbl, freeStr);
            lv_obj_set_style_text_color(lbl, lv_color_make(100, 180, 130), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
            lv_obj_set_width(lbl, 80);
        end;
    end;

    addSeparator(detail, dw);

    { ---- Action buttons ---- }
    if device^.writable then begin
        btn_row := lv_obj_create(detail);
        lv_obj_remove_style_all(btn_row);
        lv_obj_set_size(btn_row, dw - 24, 38);
        lv_obj_remove_flag(btn_row, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_style_layout(btn_row, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(btn_row, LV_FLEX_FLOW_ROW);
        lv_obj_set_style_pad_column(btn_row, 8, 0);
        lv_obj_set_flex_align(btn_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

        btn := makeButton(btn_row, 'Add Partition', 130);
        lv_obj_add_event_cb(btn, @btn_add_part_cb, LV_EVENT_CLICKED, nil);
    end else begin
        addStatusLabel(detail, 'Device is read-only.', 160, 150, 130);
    end;
end;

{ ============================================================
  Show volume detail — volume info + format action
  ============================================================ }
procedure showVolumeDetail(volIdx: uint32);
var
    vol        : PStorage_Volume;
    dw         : sint32;
    totalBytes : uint32;
    freeBytes  : uint32;
    usedBytes  : uint32;
    fsName     : pchar;
    btn_row    : Plv_obj;
    btn        : Plv_obj;
    pctUsed    : uint32;
    devIdx     : uint32;
    i          : uint32;
begin
    clearDetail;
    sel_mode := SEL_VOLUME;
    sel_vol_idx := volIdx;

    vol := driver.storage.vol.mgr.get_volume(volIdx);
    if vol = nil then begin
        addStatusLabel(detail, 'Volume not found.', 230, 80, 80);
        exit;
    end;

    dw := WIN_W - SIDEBAR_W - 20;

    addSectionHeader(detail, 'Volume Info');
    addInfoRow(detail, dw, 'Volume Index', intToString(volIdx));

    { Find parent device index }
    devIdx := 0;
    for i := 0 to driver.storage.mgr.get_device_count() - 1 do begin
        if driver.storage.mgr.get_device(i) = vol^.device then begin
            devIdx := i;
            break;
        end;
    end;
    addInfoRow(detail, dw, 'Parent Device', stringConcat('Disk ', intToString(devIdx)));

    if vol^.filesystem <> nil then
        fsName := vol^.filesystem^.sName
    else
        fsName := 'Unknown';

    addInfoRow(detail, dw, 'Filesystem', fsName);
    addInfoRow(detail, dw, 'Sector Start', intToString(vol^.sectorStart));
    addInfoRow(detail, dw, 'Sector Count', intToString(vol^.sectorCount));
    addInfoRow(detail, dw, 'Sector Size', stringConcat(intToString(vol^.sectorSize), ' bytes'));

    totalBytes := vol^.sectorCount * vol^.sectorSize;
    freeBytes := vol^.freeSectors * vol^.sectorSize;
    usedBytes := totalBytes - freeBytes;

    addInfoRow(detail, dw, 'Total Size', formatSizePrecise(totalBytes));
    addInfoRow(detail, dw, 'Free Space', formatSizePrecise(freeBytes));
    addInfoRow(detail, dw, 'Used Space', formatSizePrecise(usedBytes));

    if totalBytes > 0 then begin
        pctUsed := (usedBytes * 100) div totalBytes;
        addInfoRow(detail, dw, 'Usage', stringConcat(intToString(pctUsed), '%'));
        addUsageBar(detail, dw, usedBytes, totalBytes);
    end;

    addInfoRow(detail, dw, 'Boot Drive', boolStr(vol^.isBootDrive));

    addSeparator(detail, dw);

    { ---- Action buttons ---- }
    btn_row := lv_obj_create(detail);
    lv_obj_remove_style_all(btn_row);
    lv_obj_set_size(btn_row, dw - 24, 38);
    lv_obj_remove_flag(btn_row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_layout(btn_row, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(btn_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(btn_row, 8, 0);
    lv_obj_set_flex_align(btn_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    if (vol^.device <> nil) and vol^.device^.writable then begin
        btn := makeButton(btn_row, 'Format', 100);
        lv_obj_add_event_cb(btn, @btn_format_cb, LV_EVENT_CLICKED, nil);
    end else begin
        addStatusLabel(detail, 'Device is read-only. Format disabled.', 160, 150, 130);
    end;
end;

{ ============================================================
  Sidebar highlight
  ============================================================ }
procedure highlightSidebarBtn(btn: Plv_obj);
begin
    if active_sidebar_btn <> nil then
        lv_obj_set_style_border_width(active_sidebar_btn, 0, 0);
    active_sidebar_btn := btn;
    if btn <> nil then begin
        lv_obj_set_style_border_width(btn, 2, 0);
        lv_obj_set_style_border_color(btn, lv_color_make(100, 160, 255), 0);
    end;
end;

procedure sidebar_dev_click_hl(e: Plv_event); cdecl;
var
    code : uint32;
    idx  : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    idx := uint32(lv_event_get_user_data(e));
    highlightSidebarBtn(lv_event_get_target(e));
    showDeviceDetail(idx);
end;

procedure sidebar_vol_click_hl(e: Plv_event); cdecl;
var
    code : uint32;
    idx  : uint32;
begin
    code := lv_event_get_code(e);
    if code <> LV_EVENT_CLICKED then exit;
    idx := uint32(lv_event_get_user_data(e));
    highlightSidebarBtn(lv_event_get_target(e));
    showVolumeDetail(idx);
end;

{ ============================================================
  Sidebar — build/rebuild the device and volume list
  ============================================================ }
procedure refreshSidebar;
var
    i, j    : uint32;
    devCnt  : uint32;
    volCnt  : uint32;
    device  : PStorage_Device;
    vol     : PStorage_Volume;
    btn     : Plv_obj;
    lbl     : Plv_obj;
    hdr     : Plv_obj;
    sizeStr : pchar;
begin
    if sidebar = nil then exit;
    lv_obj_clean(sidebar);
    active_sidebar_btn := nil;

    { Sidebar title }
    hdr := lv_label_create(sidebar);
    lv_label_set_text(hdr, 'Storage');
    lv_obj_set_style_text_color(hdr, lv_color_make(200, 205, 220), 0);
    lv_obj_set_style_text_font(hdr, @lv_font_montserrat_14, 0);

    devCnt := driver.storage.mgr.get_device_count();
    for i := 0 to devCnt - 1 do begin
        device := driver.storage.mgr.get_device(i);
        if device = nil then continue;

        { Section label for this device }
        addSectionHeader(sidebar, stringConcat('Disk ', intToString(i)));

        { Clickable device row }
        btn := lv_button_create(sidebar);
        lv_obj_remove_style_all(btn);
        lv_obj_set_size(btn, SIDEBAR_W - 24, 34);
        lv_obj_set_style_bg_color(btn, lv_color_make(45, 50, 68), 0);
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
        lv_obj_set_style_radius(btn, 6, 0);
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_pad_left(btn, 10, 0);
        lv_obj_set_style_pad_right(btn, 8, 0);
        lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
        lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

        lbl := lv_label_create(btn);
        lv_label_set_text(lbl, controllerStr(device^.controller));
        lv_obj_set_style_text_color(lbl, lv_color_make(210, 215, 230), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

        sizeStr := formatSizeStr(device^.maxSectorCount * device^.sectorSize);
        lbl := lv_label_create(btn);
        lv_label_set_text(lbl, sizeStr);
        lv_obj_set_style_text_color(lbl, lv_color_make(140, 150, 170), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

        lv_obj_add_event_cb(btn, @sidebar_dev_click_hl, LV_EVENT_CLICKED, pointer(i));

        { Auto-highlight if currently selected }
        if (sel_mode = SEL_DEVICE) and (sel_dev_idx = i) then
            highlightSidebarBtn(btn);

        { List volumes that belong to this device }
        volCnt := driver.storage.vol.mgr.get_volume_count();
        for j := 0 to volCnt - 1 do begin
            vol := driver.storage.vol.mgr.get_volume(j);
            if vol = nil then continue;
            if vol^.device <> device then continue;

            btn := lv_button_create(sidebar);
            lv_obj_remove_style_all(btn);
            lv_obj_set_size(btn, SIDEBAR_W - 36, 28);
            lv_obj_set_style_bg_color(btn, lv_color_make(38, 42, 56), 0);
            lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
            lv_obj_set_style_radius(btn, 4, 0);
            lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_pad_left(btn, 14, 0);
            lv_obj_set_style_pad_right(btn, 8, 0);
            lv_obj_set_style_layout(btn, LV_LAYOUT_FLEX, 0);
            lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
            lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

            lbl := lv_label_create(btn);
            if vol^.filesystem <> nil then
                lv_label_set_text(lbl, vol^.filesystem^.sName)
            else
                lv_label_set_text(lbl, 'Volume');
            lv_obj_set_style_text_color(lbl, lv_color_make(185, 195, 215), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

            sizeStr := formatSizeStr(vol^.sectorCount * vol^.sectorSize);
            lbl := lv_label_create(btn);
            lv_label_set_text(lbl, sizeStr);
            lv_obj_set_style_text_color(lbl, lv_color_make(120, 130, 150), 0);
            lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

            lv_obj_add_event_cb(btn, @sidebar_vol_click_hl, LV_EVENT_CLICKED, pointer(j));

            if (sel_mode = SEL_VOLUME) and (sel_vol_idx = j) then
                highlightSidebarBtn(btn);
        end;
    end;

    { Empty state placeholder }
    if devCnt = 0 then begin
        lbl := lv_label_create(sidebar);
        lv_label_set_text(lbl, 'No storage devices');
        lv_obj_set_style_text_color(lbl, lv_color_make(120, 125, 145), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
        lbl := lv_label_create(sidebar);
        lv_label_set_text(lbl, 'detected.');
        lv_obj_set_style_text_color(lbl, lv_color_make(120, 125, 145), 0);
        lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    end;
end;

{ ============================================================
  Window close handler
  ============================================================ }
procedure diskutil_entry(ctx : PProcessContext);
begin
    while (ctx^.State <> psFinished) and (ctx^.PendingMsg <> smKill) and (ctx^.PendingMsg <> smTerminate) do
        proc.mgr.proc_yield;
end;

procedure onClose(wid: uint32);
begin
    debug.tracer.push_trace('diskutil.onClose');
    closeMsgBox;
    ui_session_id := ui_session_id + 1;
    puint32(@fmt_done_flag)^ := 0;
    if fmt_poll_timer <> nil then begin
        lv_timer_delete(fmt_poll_timer);
        fmt_poll_timer := nil;
    end;
    if proc_pid <> 0 then begin
        proc.mgr.kill(proc_pid);
        proc_pid := 0;
    end;
    driver.video.windows.destroyWindow(wid);
    win_id := 0;
    sidebar := nil;
    detail := nil;
    active_sidebar_btn := nil;
    debug.tracer.pop_trace;
end;

{ ============================================================
  Launch — create the window and populate it
  ============================================================ }
procedure launch;
var
    scr_w, scr_h : sint32;
    wx, wy       : sint32;
    content      : Plv_obj;
    lbl          : Plv_obj;
    ctx          : PProcessContext;
begin
    debug.tracer.push_trace('diskutil.launch');

    if driver.video.windows.isWindowOpen(win_id) then begin
        debug.tracer.pop_trace;
        exit;
    end;

    scr_w := sint32(driver.video.frontBufferWidth);
    scr_h := sint32(driver.video.frontBufferHeight);
    wx := (scr_w - WIN_W) div 2;
    wy := (scr_h - WIN_H) div 2 - 30;

    win_id := driver.video.windows.createWindow(
        'Disk Utility',
        wx, wy, WIN_W, WIN_H,
        @onClose,
        nil
    );
    if win_id = 0 then begin
        debug.tracer.pop_trace;
        exit;
    end;

    content := driver.video.windows.getWindowContent(win_id);
    if content = nil then begin
        debug.tracer.pop_trace;
        exit;
    end;

    { Content: horizontal flex row for sidebar + detail }
    lv_obj_set_style_layout(content, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(content, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_all(content, 0, 0);
    lv_obj_set_style_pad_column(content, 0, 0);
    lv_obj_remove_flag(content, LV_OBJ_FLAG_SCROLLABLE);

    { ---- Sidebar ---- }
    sidebar := lv_obj_create(content);
    lv_obj_remove_style_all(sidebar);
    lv_obj_set_size(sidebar, SIDEBAR_W, lv_pct(100));
    lv_obj_set_style_bg_color(sidebar, lv_color_make(28, 31, 40), 0);
    lv_obj_set_style_bg_opa(sidebar, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_all(sidebar, 10, 0);
    lv_obj_set_style_pad_row(sidebar, 4, 0);
    lv_obj_set_style_layout(sidebar, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(sidebar, LV_FLEX_FLOW_COLUMN);
    lv_obj_add_flag(sidebar, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(sidebar, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_set_style_border_width(sidebar, 1, 0);
    lv_obj_set_style_border_color(sidebar, lv_color_make(48, 52, 68), 0);

    { ---- Detail panel ---- }
    detail := lv_obj_create(content);
    lv_obj_remove_style_all(detail);
    lv_obj_set_size(detail, WIN_W - SIDEBAR_W - 20, lv_pct(100));
    lv_obj_set_style_bg_color(detail, lv_color_make(35, 38, 48), 0);
    lv_obj_set_style_bg_opa(detail, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_all(detail, 14, 0);
    lv_obj_set_style_pad_row(detail, 6, 0);
    lv_obj_set_style_layout(detail, LV_LAYOUT_FLEX, 0);
    lv_obj_set_flex_flow(detail, LV_FLEX_FLOW_COLUMN);
    lv_obj_add_flag(detail, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scrollbar_mode(detail, LV_SCROLLBAR_MODE_AUTO);

    { Placeholder text }
    lbl := lv_label_create(detail);
    lv_label_set_text(lbl, 'Select a device or volume');
    lv_obj_set_style_text_color(lbl, lv_color_make(120, 125, 145), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);
    lbl := lv_label_create(detail);
    lv_label_set_text(lbl, 'from the sidebar.');
    lv_obj_set_style_text_color(lbl, lv_color_make(120, 125, 145), 0);
    lv_obj_set_style_text_font(lbl, @lv_font_montserrat_14, 0);

    { Reset state }
    sel_mode := SEL_NONE;
    sel_dev_idx := 0;
    sel_vol_idx := 0;
    pending_del_slot := -1;
    active_mbox := nil;
    fmt_dropdown := nil;
    add_textarea := nil;
    add_err_lbl := nil;
    active_sidebar_btn := nil;
    fmt_done_flag := 0;
    fmt_done_error := eNone;
    fmt_done_vol_idx := 0;
    fmt_poll_timer := lv_timer_create(@fmt_poll_cb, 50, nil);

    refreshSidebar;

    { Create process so app.diskutil appears in PS and is manageable }
    ctx := proc.mgr.create('Disk Utility', @diskutil_entry, nil, 1);
    if ctx <> nil then begin
        proc_pid := ctx^.ProcessID;
        driver.video.windows.setWindowOwner(win_id, ctx^.ProcessID);
    end;

    debug.tracer.pop_trace;
end;

{ ============================================================
  Init — register with the driver.video.desktop program launcher
  ============================================================ }
procedure init();
begin
    debug.tracer.push_trace('diskutil.init');
    win_id := 0;
    proc_pid := 0;
    sidebar := nil;
    detail := nil;
    sel_mode := SEL_NONE;
    sel_dev_idx := 0;
    sel_vol_idx := 0;
    pending_del_slot := -1;
    active_mbox := nil;
    fmt_dropdown := nil;
    add_textarea := nil;
    add_err_lbl := nil;
    active_sidebar_btn := nil;
    fmt_poll_timer := nil;
    fmt_done_flag := 0;
    fmt_done_error := eNone;
    fmt_done_vol_idx := 0;
    ui_session_id := 1;
    driver.video.desktop.registerProgram('Disk Utility', @launch);
    debug.tracer.pop_trace;
end;

end.
