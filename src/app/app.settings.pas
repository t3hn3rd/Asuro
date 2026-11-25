unit app.settings;

interface

procedure Launch;

implementation

uses
    app.filepicker,
    core.ds.hashmap,
    core.strings,
    driver.storage.types,
    driver.storage.fs.registry,
    driver.storage.vfs,
    driver.video,
    driver.video.lvgl,
    driver.video.windows,
    memory.heap,
    proc.mgr,
    proc.types;

const
    SETTINGS_ROOT = '/cfg/settings';
    WINDOW_WIDTH = 720;
    WINDOW_HEIGHT = 520;
    MAX_FIELD_BYTES = 4096;
    MAX_SOURCE_BYTES = 64 * 1024;
    MAX_SOURCE_COLUMNS = 256;

type
    TControl = (scUnavailable, scDropdown, scToggle, scText, scFile, scSlider);

    PEntry = ^TEntry;
    TEntry = record
        Next, Children : PEntry;
        Path, ID, LabelText, Description, Current : PChar;
        Target, Draft : PChar;
        Length, Order : uint32;
        Control : TControl;
        OriginalChoice, SelectedChoice : PEntry;
        OriginalNumber, Number, Minimum, Maximum, Step : sint32;
        Button, ValueLabel : Plv_obj;
    end;

    PSourceColumns = ^TSourceColumns;
    TSourceColumns = array[0..MAX_SOURCE_COLUMNS - 1] of PEntry;

    PDirectoryScan = ^TDirectoryScan;
    TDirectoryScan = record
        Path : PChar;
        Entries : PEntry;
    end;

    PValueLookup = ^TValueLookup;
    TValueLookup = record
        Target : PChar;
        Name : PChar;
    end;

var
    sections, selectedSection : PEntry;
    windowID, windowOwner : uint32;
    allButton, searchBox, results, applyButton, statusLabel : Plv_obj;
    pickerItem : PEntry;
    pickerOpen : Boolean;

function JoinPath(parent, name : PChar) : PChar;
var
    prefix : PChar;
begin
    prefix := stringConcat(parent, '/');
    JoinPath := stringConcat(prefix, name);
    kfree(void(prefix));
end;

function ReadLimitedValue(path : PChar; limit : uint32;
                         var length : uint32) : PChar;
var
    handle : TFileHandle;
    error : TError;
    buffer : PChar;
begin
    ReadLimitedValue := nil;
    length := 0;
    handle := OpenFile(path, omRead, @error);
    if handle = 0 then exit;
    length := FileSizeFromHandle(handle);
    if length <= limit then begin
        buffer := stringNew(length);
        if (length = 0) or
           (ReadFile(handle, 0, PUInt8(buffer), length) = length) then
            ReadLimitedValue := buffer
        else
            kfree(void(buffer));
    end;
    CloseFile(handle);
end;

function ReadValue(path : PChar; var length : uint32) : PChar;
begin
    ReadValue := ReadLimitedValue(path, MAX_FIELD_BYTES, length);
end;

function ReadField(parent, name : PChar) : PChar;
var
    path : PChar;
    length : uint32;
begin
    path := JoinPath(parent, name);
    ReadField := ReadValue(path, length);
    kfree(void(path));
end;

procedure FreeEntries(entry : PEntry);
var
    next : PEntry;
begin
    while entry <> nil do begin
        next := entry^.Next;
        FreeEntries(entry^.Children);
        kfree(void(entry^.Path));
        if entry^.ID <> nil then kfree(void(entry^.ID));
        if entry^.LabelText <> nil then kfree(void(entry^.LabelText));
        if entry^.Description <> nil then kfree(void(entry^.Description));
        if entry^.Current <> nil then kfree(void(entry^.Current));
        if entry^.Target <> nil then kfree(void(entry^.Target));
        if entry^.Draft <> nil then kfree(void(entry^.Draft));
        kfree(void(entry));
        entry := next;
    end;
end;

procedure CollectDirectory(key : PChar; data : void; userData : void);
var
    entry, current, previous : PEntry;
    scan : PDirectoryScan;
    objectInfo : PVFSObject;
    bytes : PChar;
    length : uint32;
    path : PChar;
begin
    objectInfo := PVFSObject(data);
    if objectInfo = nil then exit;
    if (objectInfo^.ObjectType <> otVDIRECTORY) and
       (objectInfo^.ObjectType <> otDIRECTORY) then exit;
    scan := PDirectoryScan(userData);

    entry := PEntry(kalloc(SizeOf(TEntry)));
    entry^.Path := JoinPath(scan^.Path, key);
    entry^.ID := stringCopy(key);
    entry^.LabelText := ReadField(entry^.Path, 'label.txt');
    entry^.Description := ReadField(entry^.Path, 'description.txt');
    entry^.Order := High(uint32);

    path := JoinPath(entry^.Path, 'order.u32');
    bytes := ReadValue(path, length);
    kfree(void(path));
    if bytes <> nil then begin
        if length = SizeOf(uint32) then entry^.Order := PUInt32(bytes)^;
        kfree(void(bytes));
    end;

    previous := nil;
    current := scan^.Entries;
    while current <> nil do begin
        if entry^.Order < current^.Order then break;
        if (entry^.Order = current^.Order) and
           (stringCompare(entry^.ID, current^.ID) < 0) then break;
        previous := current;
        current := current^.Next;
    end;
    entry^.Next := current;
    if previous = nil then scan^.Entries := entry
    else previous^.Next := entry;
end;

function ListDirectories(path : PChar) : PEntry;
var
    scan : TDirectoryScan;
    listing : PHashMap;
begin
    scan.Path := path;
    scan.Entries := nil;
    listing := GetDirectoryListingFrom(path, '/');
    if listing <> nil then begin
        core.ds.hashmap.forEach(listing, @CollectDirectory, void(@scan));
        FreeDirectoryListing(listing);
    end;
    ListDirectories := scan.Entries;
end;

function EntryLabel(entry : PEntry) : PChar;
begin
    EntryLabel := entry^.LabelText;
    if EntryLabel = nil then EntryLabel := entry^.ID;
end;

procedure FindValueName(key : PChar; data : void; userData : void);
var
    lookup : PValueLookup;
begin
    lookup := PValueLookup(userData);
    if (lookup^.Name = nil) and stringStartsWith(key, 'value.') then
        if stringEndsWith(lookup^.Target, @key[5]) then
            lookup^.Name := stringCopy(key);
end;

function ReadChange(change : PEntry) : Boolean;
var
    lookup : TValueLookup;
    listing : PHashMap;
    path : PChar;
begin
    ReadChange := false;
    if not stringStartsWith(change^.Target, '/cfg/') then exit;
    listing := GetDirectoryListingFrom(change^.Path, '/');
    if listing = nil then exit;
    lookup.Target := change^.Target;
    lookup.Name := nil;
    core.ds.hashmap.forEach(listing, @FindValueName, void(@lookup));
    FreeDirectoryListing(listing);
    if lookup.Name = nil then exit;
    path := JoinPath(change^.Path, lookup.Name);
    change^.Current := ReadValue(path, change^.Length);
    kfree(void(path));
    kfree(void(lookup.Name));
    ReadChange := change^.Current <> nil;
end;

function MatchesChoice(choice : PEntry) : Boolean;
var
    change : PEntry;
    actual : PChar;
    length, i : uint32;
    matches : Boolean;
begin
    MatchesChoice := false;
    change := choice^.Children;
    if change = nil then exit;
    while change <> nil do begin
        actual := ReadValue(change^.Target, length);
        if actual = nil then exit;
        matches := length = change^.Length;
        i := 0;
        while matches and (i < length) do begin
            matches := actual[i] = change^.Current[i];
            Inc(i);
        end;
        kfree(void(actual));
        if not matches then exit;
        change := change^.Next;
    end;
    MatchesChoice := true;
end;

function ReadChoice(choice : PEntry; target : PChar) : Boolean;
var
    path : PChar;
    change : PEntry;
begin
    if target <> nil then begin
        change := PEntry(kalloc(SizeOf(TEntry)));
        change^.Path := stringCopy(choice^.Path);
        change^.Target := stringCopy(target);
        choice^.Children := change;
        ReadChoice := ReadChange(change);
        exit;
    end;

    path := JoinPath(choice^.Path, 'changes');
    choice^.Children := ListDirectories(path);
    kfree(void(path));
    ReadChoice := false;
    change := choice^.Children;
    if change = nil then exit;
    while change <> nil do begin
        change^.Target := ReadField(change^.Path, 'target.txt');
        if not ReadChange(change) then exit;
        change := change^.Next;
    end;
    ReadChoice := true;
end;

function ReadColumnType(column : PEntry) : Boolean;
var
    target, current : PChar;
    length : uint32;
begin
    ReadColumnType := false;
    target := column^.Target;
    if not stringStartsWith(target, '/cfg/') then exit;

    if stringEndsWith(target, '.u8') or stringEndsWith(target, '.i8') then
        column^.Length := 1
    else if stringEndsWith(target, '.u16') or stringEndsWith(target, '.i16') then
        column^.Length := 2
    else if stringEndsWith(target, '.u32') or stringEndsWith(target, '.i32') then
        column^.Length := 4
    else if stringEndsWith(target, '.u64') or stringEndsWith(target, '.i64') then
        column^.Length := 8
    else
        exit;

    { Number records whether the target uses a signed integer. }
    column^.Number := Ord(stringEndsWith(target, '.i8') or stringEndsWith(target, '.i16')
                         or stringEndsWith(target, '.i32') or stringEndsWith(target, '.i64'));
    current := ReadValue(target, length);
    ReadColumnType := (current <> nil) and (length = column^.Length);
    kfree(void(current));
end;

function IndexColumns(list : PEntry; index : PSourceColumns;
                      count : uint32) : Boolean;
var
    entry : PEntry;
    path, bytes : PChar;
    length, position, i : uint32;
begin
    IndexColumns := false;
    entry := list;
    while entry <> nil do begin
        path := JoinPath(entry^.Path, 'index.u32');
        bytes := ReadValue(path, length);
        kfree(void(path));
        if bytes = nil then exit;
        position := count;
        if length = SizeOf(uint32) then position := PUInt32(bytes)^;
        kfree(void(bytes));
        if position >= count then exit;
        if index^[position] <> nil then exit;

        entry^.Target := ReadField(entry^.Path, 'target.txt');
        if not ReadColumnType(entry) then exit;
        for i := 0 to count - 1 do
            if (index^[i] <> nil) and stringEquals(index^[i]^.Target, entry^.Target) then exit;
        index^[position] := entry;
        entry := entry^.Next;
    end;
    IndexColumns := true;
end;

function EncodeInteger(token : PChar; width : uint32; signed : Boolean;
                       bytes : PChar) : Boolean;
var
    negative : Boolean;
    limit, value : uint64;
    digit, i : uint32;
begin
    EncodeInteger := false;
    negative := token^ = '-';
    if negative then begin
        if not signed then exit;
        Inc(token);
    end;
    if token^ = #0 then exit;

    limit := High(uint64) shr (64 - width * 8);
    if signed then begin
        limit := limit shr 1;
        if negative then Inc(limit);
    end;
    value := 0;
    while token^ <> #0 do begin
        if (token^ < '0') or (token^ > '9') then exit;
        digit := Ord(token^) - Ord('0');
        if value > (limit - digit) div 10 then exit;
        value := value * 10 + digit;
        Inc(token);
    end;

    if negative and (value <> 0) then value := (not value) + 1;
    for i := 0 to width - 1 do begin
        bytes[i] := Char(value and $FF);
        value := value shr 8;
    end;
    EncodeInteger := true;
end;

function SourceLabel(template : PChar; change : PEntry) : PChar;
var
    output, cursor, name, close : PChar;
    field : PEntry;
    used, length, i : uint32;
begin
    SourceLabel := nil;
    output := stringNew(MAX_FIELD_BYTES);
    cursor := template;
    used := 0;
    while (cursor^ <> #0) and (used < MAX_FIELD_BYTES) do begin
        if (cursor^ = #10) or (cursor^ = #13) or (cursor^ = '}') then break;
        if cursor^ <> '{' then begin
            output[used] := cursor^;
            Inc(used);
            Inc(cursor);
        end else begin
            name := cursor;
            Inc(name);
            close := name;
            while (close^ <> #0) and (close^ <> '}') do Inc(close);
            if close^ <> '}' then break;
            close^ := #0;
            field := change;
            while (field <> nil) and not stringEquals(field^.ID, name) do
                field := field^.Next;
            close^ := '}';
            if field = nil then break;
            length := stringSize(field^.LabelText);
            if length > MAX_FIELD_BYTES - used then break;
            for i := 0 to length - 1 do output[used + i] := field^.LabelText[i];
            Inc(used, length);
            cursor := close;
            Inc(cursor);
        end;
    end;
    if (cursor^ = #0) and (used <> 0) then SourceLabel := stringCopy(output);
    kfree(void(output));
end;

function ParseSourceRow(row, template : PChar; columns : PSourceColumns;
                        count : uint32) : PEntry;
var
    choice, change, column : PEntry;
    token : PChar;
    i : uint32;
    valid : Boolean;
begin
    ParseSourceRow := nil;
    choice := PEntry(kalloc(SizeOf(TEntry)));
    valid := true;
    for i := 0 to count - 1 do begin
        while (row^ = ' ') or (row^ = #9) do Inc(row);
        if row^ = #0 then begin
            valid := false;
            break;
        end;
        token := row;
        while (row^ <> #0) and (row^ <> ' ') and (row^ <> #9) do Inc(row);
        if row^ <> #0 then begin
            row^ := #0;
            Inc(row);
        end;

        column := columns^[i];
        change := PEntry(kalloc(SizeOf(TEntry)));
        change^.Next := choice^.Children;
        choice^.Children := change;
        change^.ID := stringCopy(column^.ID);
        change^.Target := stringCopy(column^.Target);
        change^.Length := column^.Length;
        change^.Current := stringNew(change^.Length);
        if not EncodeInteger(token, change^.Length, column^.Number <> 0, change^.Current) then begin
            valid := false;
            break;
        end;
        change^.LabelText := stringCopy(token);
    end;
    while (row^ = ' ') or (row^ = #9) do Inc(row);
    if valid and (row^ = #0) then choice^.LabelText := SourceLabel(template, choice^.Children);
    if choice^.LabelText <> nil then ParseSourceRow := choice
    else FreeEntries(choice);
end;

procedure LoadSourceRows(item : PEntry; data, template : PChar;
                         columns : PSourceColumns; count : uint32);
var
    row, cursor : PChar;
    choice, last : PEntry;
begin
    cursor := data;
    last := nil;
    while cursor^ <> #0 do begin
        row := cursor;
        while (cursor^ <> #0) and (cursor^ <> #10) do Inc(cursor);
        if cursor^ = #10 then begin
            cursor^ := #0;
            if (cursor <> row) and (PChar(uint32(cursor) - 1)^ = #13) then
                PChar(uint32(cursor) - 1)^ := #0;
            Inc(cursor);
        end;

        choice := ParseSourceRow(row, template, columns, count);
        if choice = nil then continue;
        if last = nil then item^.Children := choice
        else last^.Next := choice;
        last := choice;
        if (item^.OriginalChoice = nil) and MatchesChoice(choice) then
            item^.OriginalChoice := choice;
    end;
end;

procedure ReadSourcedChoices(item : PEntry; base : PChar);
var
    path, format, template, data : PChar;
    list, column : PEntry;
    columns : PSourceColumns;
    count, length : uint32;
begin
    format := ReadField(base, 'format.txt');
    if not stringEquals(format, 'integer-rows-v1') then begin
        kfree(void(format));
        exit;
    end;
    kfree(void(format));

    path := ReadField(base, 'source.txt');
    data := nil;
    if stringStartsWith(path, '/') then
        data := ReadLimitedValue(path, MAX_SOURCE_BYTES, length);
    kfree(void(path));
    if data = nil then exit;

    template := ReadField(base, 'label.txt');
    path := JoinPath(base, 'columns');
    list := ListDirectories(path);
    kfree(void(path));
    count := 0;
    column := list;
    while column <> nil do begin
        Inc(count);
        column := column^.Next;
    end;
    if (count > 0) and (count <= MAX_SOURCE_COLUMNS) and (template <> nil)
        and (stringSize(data) = length) then begin
        columns := PSourceColumns(kalloc(count * SizeOf(PEntry)));
        if IndexColumns(list, columns, count) then
            LoadSourceRows(item, data, template, columns, count);
        kfree(void(columns));
    end;
    FreeEntries(list);
    kfree(void(template));
    kfree(void(data));
end;

procedure ReadDropdown(item : PEntry);
var
    path : PChar;
    choice, next, last : PEntry;
begin
    path := JoinPath(item^.Path, 'choices-source');
    if PathValid(path) = pvDirectory then begin
        ReadSourcedChoices(item, path);
        kfree(void(path));
        item^.SelectedChoice := item^.OriginalChoice;
        if item^.Children <> nil then item^.Control := scDropdown;
        exit;
    end;
    kfree(void(path));
    path := JoinPath(item^.Path, 'choices');
    choice := ListDirectories(path);
    kfree(void(path));
    last := nil;
    while choice <> nil do begin
        next := choice^.Next;
        choice^.Next := nil;
        if ReadChoice(choice, item^.Target) then begin
            if last = nil then item^.Children := choice
            else last^.Next := choice;
            last := choice;
            if (item^.OriginalChoice = nil) and MatchesChoice(choice) then
                item^.OriginalChoice := choice;
        end else
            FreeEntries(choice);
        choice := next;
    end;
    item^.SelectedChoice := item^.OriginalChoice;
    if item^.Children <> nil then item^.Control := scDropdown;
end;

function ReadSliderField(item : PEntry; name : PChar; var value : sint32) : Boolean;
var
    path, bytes : PChar;
    length : uint32;
begin
    ReadSliderField := false;
    path := JoinPath(item^.Path, name);
    bytes := ReadValue(path, length);
    kfree(void(path));
    if bytes = nil then exit;
    if (length = SizeOf(uint32)) and (PUInt32(bytes)^ <= High(sint32)) then begin
        value := sint32(PUInt32(bytes)^);
        ReadSliderField := true;
    end;
    kfree(void(bytes));
end;

procedure ReadItem(item : PEntry);
var
    control : PChar;
begin
    control := ReadField(item^.Path, 'control.txt');
    item^.Target := ReadField(item^.Path, 'target.txt');
    if stringEquals(control, 'dropdown') then
        ReadDropdown(item)
    else if stringStartsWith(item^.Target, '/cfg/') then begin
        item^.Current := ReadValue(item^.Target, item^.Length);
        if item^.Current <> nil then begin
            if stringEndsWith(item^.Target, '.txt') and
               (stringSize(item^.Current) = item^.Length) then begin
                if stringEquals(control, 'text') then item^.Control := scText;
                if stringEquals(control, 'file') then item^.Control := scFile;
            end;
            if stringEquals(control, 'toggle') and stringEndsWith(item^.Target, '.bool')
                and (item^.Length = 1) and (Ord(item^.Current[0]) <= 1) then begin
                item^.Control := scToggle;
                item^.OriginalNumber := Ord(item^.Current[0]);
            end;
            if stringEquals(control, 'slider') and stringEndsWith(item^.Target, '.u32')
                and (item^.Length = SizeOf(uint32))
                and (PUInt32(item^.Current)^ <= High(sint32)) then begin
                item^.OriginalNumber := sint32(PUInt32(item^.Current)^);
                if ReadSliderField(item, 'min.u32', item^.Minimum)
                    and ReadSliderField(item, 'max.u32', item^.Maximum)
                    and ReadSliderField(item, 'step.u32', item^.Step)
                    and (item^.Minimum < item^.Maximum) and (item^.Step > 0)
                    and (item^.OriginalNumber >= item^.Minimum)
                    and (item^.OriginalNumber <= item^.Maximum) then
                    item^.Control := scSlider;
            end;
            item^.Number := item^.OriginalNumber;
        end;
    end;
    if control <> nil then kfree(void(control));
end;

function LoadSections : PEntry;
var
    section, item : PEntry;
    path : PChar;
begin
    LoadSections := ListDirectories(SETTINGS_ROOT);
    section := LoadSections;
    while section <> nil do begin
        path := JoinPath(section^.Path, 'items');
        section^.Children := ListDirectories(path);
        kfree(void(path));
        item := section^.Children;
        while item <> nil do begin
            ReadItem(item);
            item := item^.Next;
        end;
        section := section^.Next;
    end;
end;

function AddLabel(parent : Plv_obj; caption : PChar; colour : uint32) : Plv_obj;
var
    labelObject : Plv_obj;
begin
    labelObject := lv_label_create(parent);
    lv_obj_set_width(labelObject, lv_pct(100));
    lv_label_set_long_mode(labelObject, LV_LABEL_LONG_WRAP);
    lv_label_set_text(labelObject, caption);
    lv_obj_set_style_text_color(labelObject, lv_color_hex(colour), 0);
    AddLabel := labelObject;
end;

function CreateColumn(parent : Plv_obj) : Plv_obj;
var
    column : Plv_obj;
begin
    column := lv_obj_create(parent);
    lv_obj_remove_style_all(column);
    lv_obj_set_flex_flow(column, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(column, 8, 0);
    CreateColumn := column;
end;

function ItemMatches(section, item : PEntry; query : PChar) : Boolean;
begin
    ItemMatches := (query = nil) or (query[0] = #0) or
                   stringContainsCI(EntryLabel(section), query) or
                   stringContainsCI(EntryLabel(item), query);
    if not ItemMatches and (item^.Description <> nil) then
        ItemMatches := stringContainsCI(item^.Description, query);
end;

function IsDirty(item : PEntry) : Boolean;
begin
    IsDirty := false;
    case item^.Control of
        scDropdown: IsDirty := item^.SelectedChoice <> item^.OriginalChoice;
        scText, scFile: IsDirty := item^.Draft <> nil;
        scToggle, scSlider: IsDirty := item^.Number <> item^.OriginalNumber;
    end;
end;

procedure UpdateApply;
var
    section, item : PEntry;
begin
    section := sections;
    while section <> nil do begin
        item := section^.Children;
        while item <> nil do begin
            if IsDirty(item) then begin
                lv_obj_remove_state(applyButton, LV_STATE_DISABLED);
                lv_label_set_text(statusLabel, 'Unapplied changes');
                exit;
            end;
            item := item^.Next;
        end;
        section := section^.Next;
    end;
    lv_obj_add_state(applyButton, LV_STATE_DISABLED);
    lv_label_set_text(statusLabel, 'Changes are saved automatically when a writable volume is available.');
end;

function EditText(item : PEntry) : PChar;
begin
    EditText := item^.Current;
    if item^.Draft <> nil then EditText := item^.Draft;
end;

procedure SetDraft(item : PEntry; value : PChar);
begin
    if item^.Draft <> nil then kfree(void(item^.Draft));
    item^.Draft := nil;
    if not stringEquals(value, item^.Current) then item^.Draft := stringCopy(value);
    UpdateApply;
end;

procedure UpdateNumberLabel(item : PEntry);
var
    caption : PChar;
begin
    caption := intToString(uint32(item^.Number));
    lv_label_set_text(item^.ValueLabel, caption);
    kfree(void(caption));
end;

procedure ControlChanged(event : Plv_event); cdecl;
var
    item, choice : PEntry;
    widget : Plv_obj;
    index : uint32;
    value, snapped : sint32;
begin
    item := PEntry(lv_event_get_user_data(event));
    widget := lv_event_get_target_obj(event);
    case item^.Control of
        scDropdown:
            begin
                index := lv_dropdown_get_selected(widget);
                choice := item^.Children;
                if item^.OriginalChoice = nil then begin
                    if index = 0 then choice := nil
                    else Dec(index);
                end;
                while (choice <> nil) and (index <> 0) do begin
                    choice := choice^.Next;
                    Dec(index);
                end;
                item^.SelectedChoice := choice;
            end;
        scText:
            begin
                SetDraft(item, lv_textarea_get_text(widget));
                exit;
            end;
        scToggle: item^.Number := Ord(lv_obj_has_state(widget, LV_STATE_CHECKED));
        scSlider:
            begin
                value := lv_slider_get_value(widget);
                snapped := item^.Minimum + ((value - item^.Minimum) div item^.Step) * item^.Step;
                if value = item^.Maximum then snapped := value;
                item^.Number := snapped;
                UpdateNumberLabel(item);
            end;
    end;
    UpdateApply;
end;

procedure FinishSliderEdit(event : Plv_event); cdecl;
var
    item : PEntry;
begin
    item := PEntry(lv_event_get_user_data(event));
    lv_slider_set_value(lv_event_get_target_obj(event), item^.Number, LV_ANIM_OFF);
end;

procedure RefreshResults; forward;

procedure FileSelected(path : PChar; unused : Pointer); cdecl;
begin
    pickerOpen := false;
    if path <> nil then begin
        if (pickerItem <> nil) and (stringSize(path) <= MAX_FIELD_BYTES) then begin
            SetDraft(pickerItem, path);
            RefreshResults;
        end;
        kfree(void(path));
    end;
    pickerItem := nil;
end;

procedure BrowseFile(event : Plv_event); cdecl;
begin
    if pickerOpen then exit;
    pickerItem := PEntry(lv_event_get_user_data(event));
    pickerOpen := true;
    app.filepicker.show_open(EntryLabel(pickerItem), '/', FP_FILTER_ALL, @FileSelected, nil);
end;

function AddButton(parent : Plv_obj; caption : PChar) : Plv_obj;
var
    button, labelObject : Plv_obj;
begin
    button := lv_button_create(parent);
    labelObject := lv_label_create(button);
    lv_label_set_text(labelObject, caption);
    lv_obj_center(labelObject);
    lv_group_add_obj(lvgl_get_kb_group, button);
    AddButton := button;
end;

procedure SetDropdownOptions(widget : Plv_obj; item : PEntry);
var
    choice : PEntry;
    options, prefix, caption : PChar;
    index, selected : uint32;
begin
    options := nil;
    index := 0;
    selected := 0;
    if item^.OriginalChoice = nil then begin
        options := stringCopy('Custom');
        Inc(index);
    end;
    choice := item^.Children;
    while choice <> nil do begin
        caption := EntryLabel(choice);
        if options = nil then
            options := stringCopy(caption)
        else begin
            prefix := stringConcat(options, #10);
            kfree(void(options));
            options := stringConcat(prefix, caption);
            kfree(void(prefix));
        end;
        if choice = item^.SelectedChoice then selected := index;
        Inc(index);
        choice := choice^.Next;
    end;
    lv_dropdown_set_options(widget, options);
    lv_dropdown_set_selected(widget, selected);
    kfree(void(options));
end;

procedure ShowItem(item : PEntry);
var
    card, widget : Plv_obj;
begin
    card := CreateColumn(results);
    lv_obj_set_size(card, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_remove_flag(card, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(card, 12, 0);
    lv_obj_set_style_radius(card, 8, 0);
    lv_obj_set_style_bg_color(card, lv_color_hex($273043), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    AddLabel(card, EntryLabel(item), $E9EDF7);
    if item^.Description <> nil then AddLabel(card, item^.Description, $A4AFC4);

    case item^.Control of
        scDropdown:
            begin
                widget := lv_dropdown_create(card);
                lv_obj_set_width(widget, lv_pct(100));
                SetDropdownOptions(widget, item);
            end;
        scToggle:
            begin
                widget := lv_switch_create(card);
                if item^.Number <> 0 then lv_obj_add_state(widget, LV_STATE_CHECKED);
            end;
        scText:
            begin
                widget := lv_textarea_create(card);
                lv_obj_set_width(widget, lv_pct(100));
                lv_textarea_set_one_line(widget, true);
                lv_textarea_set_max_length(widget, MAX_FIELD_BYTES);
                lv_textarea_set_text(widget, EditText(item));
            end;
        scFile:
            begin
                AddLabel(card, EditText(item), $BCCBE7);
                widget := AddButton(card, 'Browse');
                lv_obj_add_event_cb(widget, @BrowseFile, LV_EVENT_CLICKED, item);
                exit;
            end;
        scSlider:
            begin
                item^.ValueLabel := lv_label_create(card);
                UpdateNumberLabel(item);
                widget := lv_slider_create(card);
                lv_obj_set_width(widget, lv_pct(96));
                lv_slider_set_range(widget, item^.Minimum, item^.Maximum);
                lv_slider_set_value(widget, item^.Number, LV_ANIM_OFF);
                lv_obj_add_event_cb(widget, @FinishSliderEdit, LV_EVENT_RELEASED, item);
            end;
    else
        AddLabel(card, 'Unavailable', $BCCBE7);
        exit;
    end;
    lv_group_add_obj(lvgl_get_kb_group, widget);
    lv_obj_add_event_cb(widget, @ControlChanged, LV_EVENT_VALUE_CHANGED, item);
end;

procedure AddChange(var changes : PRegistryFileChange; target, bytes : PChar;
                    length : uint32);
var
    change : PRegistryFileChange;
begin
    change := PRegistryFileChange(kalloc(SizeOf(TRegistryFileChange)));
    change^.Next := changes;
    change^.Path := target;
    change^.Bytes := PUInt8(bytes);
    change^.Length := length;
    changes := change;
end;

procedure CollectChanges(item : PEntry; var changes : PRegistryFileChange);
var
    change : PEntry;
begin
    case item^.Control of
        scDropdown:
            begin
                change := item^.SelectedChoice^.Children;
                while change <> nil do begin
                    AddChange(changes, change^.Target, change^.Current, change^.Length);
                    change := change^.Next;
                end;
            end;
        scText, scFile:
            AddChange(changes, item^.Target, item^.Draft, stringSize(item^.Draft));
        scToggle:
            AddChange(changes, item^.Target, PChar(@item^.Number), 1);
        scSlider:
            AddChange(changes, item^.Target, PChar(@item^.Number), SizeOf(uint32));
    end;
end;

procedure ApplyClicked(event : Plv_event); cdecl;
var
    section, item : PEntry;
    changes, next : PRegistryFileChange;
    applied, tooLong : Boolean;
begin
    changes := nil;
    tooLong := false;
    section := sections;
    while section <> nil do begin
        item := section^.Children;
        while item <> nil do begin
            if IsDirty(item) then begin
                if stringSize(item^.Draft) > MAX_FIELD_BYTES then tooLong := true
                else CollectChanges(item, changes);
            end;
            item := item^.Next;
        end;
        section := section^.Next;
    end;
    applied := not tooLong and (changes <> nil) and ApplyFileChanges(changes);
    while changes <> nil do begin
        next := changes^.Next;
        kfree(void(changes));
        changes := next;
    end;
    if tooLong then begin
        lv_label_set_text(statusLabel, 'Text settings are limited to 4096 bytes.');
        exit;
    end;
    if not applied then begin
        lv_label_set_text(statusLabel, 'Could not apply changes. Check the setting values and targets.');
        exit;
    end;

    section := sections;
    while section <> nil do begin
        item := section^.Children;
        while item <> nil do begin
            item^.OriginalChoice := item^.SelectedChoice;
            item^.OriginalNumber := item^.Number;
            if item^.Draft <> nil then begin
                kfree(void(item^.Current));
                item^.Current := item^.Draft;
                item^.Draft := nil;
            end;
            item := item^.Next;
        end;
        section := section^.Next;
    end;
    UpdateApply;
    lv_label_set_text(statusLabel, 'Applied to the registry. Existing components may need a restart.');
    RefreshResults;
end;

procedure RefreshResults;
var
    section, item : PEntry;
    query : PChar;
    shown, heading : Boolean;
    sectionTitle : Plv_obj;
begin
    lv_obj_clean(results);
    query := lv_textarea_get_text(searchBox);
    shown := false;
    section := sections;
    while section <> nil do begin
        if (selectedSection = nil) or (selectedSection = section) then begin
            heading := false;
            item := section^.Children;
            while item <> nil do begin
                if ItemMatches(section, item, query) then begin
                    if not heading then begin
                        sectionTitle := AddLabel(results, EntryLabel(section), $E9EDF7);
                        if (selectedSection = nil) and shown then
                            lv_obj_set_style_margin_top(sectionTitle, 12, 0);
                        if section^.Description <> nil then
                            AddLabel(results, section^.Description, $A4AFC4);
                        heading := true;
                    end;
                    ShowItem(item);
                    shown := true;
                end;
                item := item^.Next;
            end;
        end;
        section := section^.Next;
    end;
    if sections = nil then AddLabel(results, 'No settings are registered.', $A4AFC4)
    else if not shown then AddLabel(results, 'No settings match your search.', $A4AFC4);
    lv_obj_scroll_to_y(results, 0, LV_ANIM_OFF);
end;

procedure SelectSection(event : Plv_event); cdecl;
var
    section : PEntry;
begin
    selectedSection := PEntry(lv_event_get_user_data(event));
    if selectedSection = nil then lv_obj_add_state(allButton, LV_STATE_CHECKED)
    else lv_obj_remove_state(allButton, LV_STATE_CHECKED);
    section := sections;
    while section <> nil do begin
        if section = selectedSection then lv_obj_add_state(section^.Button, LV_STATE_CHECKED)
        else lv_obj_remove_state(section^.Button, LV_STATE_CHECKED);
        section := section^.Next;
    end;
    RefreshResults;
end;

procedure SearchChanged(event : Plv_event); cdecl;
begin
    RefreshResults;
end;

procedure CloseSettings(id : uint32);
begin
    pickerItem := nil;
    destroyWindow(id);
    FreeEntries(sections);
    sections := nil;
    selectedSection := nil;
    windowID := 0;
    windowOwner := 0;
end;

function AddCategory(list : Plv_obj; caption : PChar; section : PEntry) : Plv_obj;
var
    button : Plv_obj;
begin
    button := lv_list_add_button(list, nil, caption);
    lv_obj_set_width(button, lv_pct(100));
    lv_obj_set_style_bg_color(button, lv_color_hex($202837), 0);
    lv_obj_set_style_bg_color(button, lv_color_hex($364966), LV_STATE_CHECKED);
    lv_obj_set_style_text_color(button, lv_color_hex($E9EDF7), 0);
    lv_obj_add_event_cb(button, @SelectSection, LV_EVENT_CLICKED, section);
    AddCategory := button;
end;

procedure OpenSettings;
var
    content, toolbar, body, sidebar : Plv_obj;
    section : PEntry;
begin
    content := getWindowContent(windowID);
    lv_obj_set_flex_flow(content, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(content, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(content, 12, 0);
    lv_obj_set_style_pad_row(content, 10, 0);

    toolbar := lv_obj_create(content);
    lv_obj_remove_style_all(toolbar);
    lv_obj_remove_flag(toolbar, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(toolbar, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(toolbar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(toolbar, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(toolbar, 10, 0);

    searchBox := lv_textarea_create(toolbar);
    lv_textarea_set_one_line(searchBox, true);
    lv_textarea_set_placeholder_text(searchBox, 'Search settings');
    lv_obj_set_flex_grow(searchBox, 1);
    lv_group_add_obj(lvgl_get_kb_group, searchBox);
    applyButton := AddButton(toolbar, 'Apply');
    lv_obj_add_event_cb(applyButton, @ApplyClicked, LV_EVENT_CLICKED, nil);
    statusLabel := lv_label_create(content);
    lv_obj_set_width(statusLabel, lv_pct(100));
    lv_label_set_long_mode(statusLabel, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_color(statusLabel, lv_color_hex($A4AFC4), 0);
    UpdateApply;

    body := lv_obj_create(content);
    lv_obj_remove_style_all(body);
    lv_obj_remove_flag(body, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(body, lv_pct(100), 0);
    lv_obj_set_flex_grow(body, 1);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(body, 12, 0);

    sidebar := lv_list_create(body);
    lv_obj_set_size(sidebar, 156, lv_pct(100));
    lv_obj_set_style_pad_all(sidebar, 0, 0);
    lv_obj_set_style_bg_color(sidebar, lv_color_hex($202837), 0);
    allButton := AddCategory(sidebar, 'All', nil);
    lv_obj_add_state(allButton, LV_STATE_CHECKED);
    section := sections;
    while section <> nil do begin
        section^.Button := AddCategory(sidebar, EntryLabel(section), section);
        section := section^.Next;
    end;

    results := CreateColumn(body);
    lv_obj_set_size(results, 0, lv_pct(100));
    lv_obj_set_flex_grow(results, 1);
    lv_obj_set_scroll_dir(results, LV_DIR_VER);
    lv_obj_add_flag(results, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(searchBox, @SearchChanged, LV_EVENT_VALUE_CHANGED, nil);
    RefreshResults;
    lv_group_focus_obj(searchBox);
end;

procedure SettingsMain(context : PProcessContext);
var
    width, height, screenWidth, screenHeight : sint32;
    loaded : PEntry;
    pid : uint32;
begin
    loaded := LoadSections;
    pid := context^.ProcessID;

    lvgl_lock;
    screenWidth := sint32(driver.video.frontBufferWidth);
    screenHeight := sint32(driver.video.frontBufferHeight);
    width := WINDOW_WIDTH;
    height := WINDOW_HEIGHT;
    if width > screenWidth - 24 then width := screenWidth - 24;
    if height > screenHeight - 72 then height := screenHeight - 72;
    if (width >= 300) and (height >= 200) then
        windowID := createWindow('Settings', (screenWidth - width) div 2,
                                 (screenHeight - height) div 2, width, height,
                                 @CloseSettings, nil);
    if windowID <> 0 then begin
        sections := loaded;
        windowOwner := pid;
        setWindowOwner(windowID, pid);
        OpenSettings;
    end else
        FreeEntries(loaded);
    lvgl_unlock;

    while windowOwner = pid do proc.mgr.proc_sleep_ms(25);
    proc.mgr.proc_exit(0);
end;

procedure Launch;
begin
    if isWindowOpen(windowID) then begin
        focusWindow(windowID);
        if searchBox <> nil then lv_group_focus_obj(searchBox);
        exit;
    end;
    if proc.mgr.findByName('Settings') = nil then
        proc.mgr.create('Settings', @SettingsMain, nil, 1);
end;

end.
