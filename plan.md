# File Browser — Implementation Plan

## Phase 0: Icon Toolchain

**Goal:** Python+Pillow script generating uncompressed 32-bit TGA icons from Bootstrap Icons SVGs, integrated into Docker build.

**Steps:**
1. Add `python3`, `python3-pip`, `pillow` to Dockerfile.
2. Create `toolchain/generate_icons.py`:
   - Reads Bootstrap Icons SVG source files.
   - Renders each icon at 16×16 and 64×64 onto transparent RGBA canvas.
   - Writes uncompressed TGA Type 2, 32-bit, top-down origin (BGRA pixel order).
   - Outputs to `iso/sys/icons/<name>_16.tga` and `iso/sys/icons/<name>_64.tga`.
   - Generates `iso/sys/icons/manifest.txt` mapping icon name → filenames.
3. Create `toolchain/compile_icons.sh`: invokes `python3 /build/toolchain/generate_icons.py`.
4. Insert `"compile_icons"` step into `run_steps` array in `toolchain/compile.sh` before `isogen`.
5. Create `iso/sys/icons/` directory.

**Icon categories (~45 icons total):**
- Base type (16×16 + 64×64): `file-generic`, `folder`, `folder-open`, `drive`, `image`, `text`, `audio`, `video`, `archive`, `binary`, `config`, `unknown` (~12)
- Toolbar (16×16 only): `back`, `forward`, `up`, `refresh`, `home`, `cut`, `copy`, `paste`, `delete`, `rename`, `newfolder`, `newfile`, `search`, `filter`, `view-detail`, `view-compact`, `preview`, `bookmark`, `tab-new`, `tab-close` (~20)
- Extension overlay (64×64 only): `.txt`, `.tga`, `.md`, `.asr`, `.wasm`, `.cfg`, `.log` — base type icon with extension label text overlay (~7)
- App launcher (64×64): `filebrowser` icon for desktop registration (~1)
you
---

## Phase 1: Core Search & String Library + DRY Refactor

**Goal:** Add missing string primitives to `core.strings.pas`, create `core.search.pas` for higher-level search/sort/format utilities, then refactor `desktop.pas` and `filepicker.pas` to use them.

### Step 1.1 — Extend `core.strings.pas` interface

| Function | Signature | Purpose |
|---|---|---|
| `charToLower` | `(c: char): char` | Zero-alloc single-char lowercase |
| `charToUpper` | `(c: char): char` | Zero-alloc single-char uppercase |
| `stringCompare` | `(a, b: pchar): sint32` | Lexicographic compare → -1/0/+1 |
| `stringCompareCI` | `(a, b: pchar): sint32` | Case-insensitive lexicographic compare |
| `stringEqualsCI` | `(a, b: pchar): boolean` | Case-insensitive equality |
| `stringContainsCI` | `(haystack, needle: pchar): boolean` | Case-insensitive substring (zero-alloc) |
| `stringIndexOfCI` | `(str, find: pchar): sint32` | Case-insensitive indexOf |
| `stringStartsWith` | `(str, prefix: pchar): boolean` | Prefix check |
| `stringStartsWithCI` | `(str, prefix: pchar): boolean` | Case-insensitive prefix check |
| `stringEndsWith` | `(str, suffix: pchar): boolean` | Suffix check |
| `stringEndsWithCI` | `(str, suffix: pchar): boolean` | Case-insensitive suffix check |

### Step 1.2 — Create `core.search.pas`

| Function | Signature | Purpose |
|---|---|---|
| `getFileExtension` | `(name: pchar): pchar` | Returns pointer into name at last `.` (no alloc) |
| `fmtFileSize` | `(sz: uint32): pchar` | Moved from filepicker — returns kalloc'd human-readable size |
| `sortStringArray` | `(arr: PPChar; n: uint32)` | In-place insertion sort using `stringCompareCI` |
| `sortStringArrayWithData` | `(arr: PPChar; data: puint32; n: uint32)` | Parallel sort — sorts arr and swaps data in lockstep |

### Step 1.3 — Extend `UnitTest` in `core.strings`

### Step 1.4 — DRY refactor `app.filepicker.pas`
- Remove `strLess`, `sortNames`, `sortNamesWithSizes`, `matchesFilter`, `fmtFileSize`.
- Add `uses core.search`.
- Replace calls with `core.strings` / `core.search` equivalents.

### Step 1.5 — DRY refactor `driver.video.desktop.pas`
- Remove `toLowerC` and `ciContains`.
- Replace `ciContains(haystack, needle)` → `stringContainsCI(haystack, needle)`.

### Step 1.6 — Register in `app.mgr.pas`

---

## Phase 2: App Skeleton

**Goal:** Minimal `app.filebrowser.pas` — creates a window, registers with desktop launcher.

1. Create `src/app/app.filebrowser.pas` following `app.notepad.pas` pattern.
2. Define `TFileBrowserState` heap-allocated record: window ID, current path, LVGL widget pointers, tab array, bookmark array, filter state, view mode enum.
3. Implement `launch` → `createWindow`, spawn process, store state.
4. Implement `init` → `registerProgram('Files', @launch)`.
5. Add to `app.mgr.pas` uses + init call.
6. Add resize/close callbacks.

---

## Phase 3: VFS Integration & Directory Loading

**Goal:** Load and display directory contents using VFS API.

1. Implement `do_refresh(state)` — `GetDirectoryListingFrom`, hashmap forEach callback, classify dirs/files, sort via `core.search`.
2. Heap-allocated name/size buffers, ENTRY_MAX=256 (Lesson #11).
3. Zero-guard all `for i := 0 to count - 1` loops (Lesson #13).
4. `schedule_refresh` — 1ms `lv_timer_create` one-shot.
5. `FreeDirectoryListing` before loading new listing.

---

## Phase 4: Detail List View (Default)

**Goal:** Primary view using `lv_table` — columns: Icon, Name, Size, Type.

1. Create `lv_table` in window content area.
2. Set columns: Icon (24px), Name (flex), Size (70px), Type (60px).
3. Populate from `do_refresh` results — dirs first, then files.
4. `fmtFileSize` for size column, `getFileExtension` for type column.
5. Row→VFS entry mapping via `lv_table_set_cell_user_data`.
6. Handle selection via `LV_EVENT_VALUE_CHANGED`.
7. Double-click → navigate into dir or open file via `dispatch`.

---

## Phase 5: Navigation

**Goal:** Back/forward/up + Dolphin-style breadcrumb bar with click-to-edit.

1. Toolbar row: Back, Forward, Up, breadcrumb container, Refresh.
2. Path history stack (HIST_MAX=32, heap-allocated).
3. Breadcrumb bar: parse path → row of `lv_btn` per segment + separator `›`.
4. Click segment → navigate to that prefix.
5. Click whitespace/edit icon → switch to `lv_textarea` (full path editable).
6. Enter → navigate to typed path; Escape → revert to breadcrumbs.
7. Disable Back/Forward at history boundaries.

---

## Phase 6: File Operations

**Goal:** Delete, Rename, Create Folder, Create File, Copy/Move clipboard.

1. Delete: confirmation msgbox → `DeleteFile`/`DeleteDirectory` (async).
2. Rename: inline textarea overlay → `RenameFile`.
3. Create Folder: msgbox with input → `CreateDirectory`.
4. Create File: msgbox with input → `OpenFile` (create) + `CloseFile`.
5. Copy/Cut/Paste clipboard: `clip_paths` array, `clip_is_cut` flag. Paste reads+writes, cut deletes source.
6. All errors → `lv_msgbox` (Lesson #2).

---

## Phase 7: Context Menu (Right-Click)

1. Register mouse hook (`MOUSE_CLICK_RIGHT`).
2. Hit-test to determine which row is under cursor.
3. Popup `lv_obj` at mouse position with menu items.
4. Items: Open, Copy, Cut, Rename, Delete, Properties (file/dir); New Folder, New File, Paste, Refresh (empty area).
5. Click outside or Escape → destroy popup.
6. Remove mouse hook on window close.

---

## Phase 8: Tabs

**Goal:** Multiple directory tabs (MAX_TABS=8).

1. Tab bar (row of `lv_btn`) at top, below toolbar.
2. Each tab owns: `cur_path`, history stack, selection state, directory listing cache.
3. `TTabState` record, heap-allocated × MAX_TABS.
4. "+" creates new tab, "×" closes tab (min 1).
5. Ctrl+T = new tab, Ctrl+W = close tab.

---

## Phase 9: Bookmarks

**Goal:** User-editable sidebar bookmarks (session-only).

1. Left sidebar panel (150px, column flex).
2. Defaults: Root `/`, Drives (auto-detected).
3. "Add Bookmark" adds current dir.
4. Right-click → Remove.
5. MAX_BOOKMARKS=16.

---

## Phase 10: Quick Filter

1. `lv_textarea` filter input in toolbar (150px).
2. On change → re-render rows with `stringContainsCI(name, filter)`.
3. Filter persists per-tab.
4. Clear button shows all.

---

## Phase 11: Type-Ahead Jump-To

1. Keyboard handler on table.
2. Typed chars → `type_ahead_buf` (32 chars).
3. Find first entry matching `stringStartsWithCI(name, buf)`.
4. Scroll + select.
5. Reset after 1s via `lv_timer`.

---

## Phase 12: File Preview Panel

1. Toggle-able right panel (200px).
2. Show: filename, size, type, full path.
3. For `.tga`: parse + thumbnail via `buildImageDsc`.
4. For dirs: item count.

---

## Phase 13: Compact List View

1. View mode enum: `vmDetail`, `vmCompact`.
2. Compact: flex-wrap layout with icon + name buttons.
3. Toolbar toggle switches modes.

---

## Phase 14: Column Header Sorting

1. Header row in table (styled differently).
2. Click header → sort by that column.
3. Toggle ascending/descending on repeated clicks.
4. Dirs always first, sorted within group.
5. Sort indicator `▲`/`▼` in header text.

---

## Phase 15: Hidden Files Toggle

1. Toolbar toggle button.
2. `show_hidden` boolean per tab (default: false).
3. Skip entries with `name[0] = '.'` when hidden.

---

## Phase 16: Enhanced Status Bar

1. Bottom bar (24px, horizontal flex).
2. Left: `"N items"` / `"N items, M selected"`.
3. Center: current path.
4. Right: selection size total.

---

## Phase 17: WatchDirectory Live Refresh

1. After `do_refresh` → `WatchDirectory(cur_path, callback, state)`.
2. Store watch ID per tab.
3. Callback sets `dirty` flag (pointer deref, Lesson #6).
4. Periodic LVGL timer (500ms) checks flag → `schedule_refresh`.
5. On tab/dir change: `UnwatchDirectory(old_id)`.
6. On close: unwatch all tabs.

---

## Design Decisions

- **`core.strings.pas` extension** for string primitives — keeps all string ops in one place.
- **Separate `core.search.pas`** for file-oriented utilities (fmtFileSize, getFileExtension, sort helpers).
- **DRY refactor in Phase 1 before file browser** — filepicker/desktop benefit immediately.
- **Insertion sort** — 256-entry max, stack-safe, no recursion.
- **Session-only bookmarks** — no config file format needed yet.
- **Tabs via manual button bar** — lighter than `lv_tabview`, consistent with existing patterns.

## Key Constraints (from lessons_learnt.md)

- #10: No sync disk I/O in LVGL timer/event callbacks.
- #11: Heap-alloc large arrays (>128 bytes) in UI callbacks.
- #13: Guard `for i := 0 to uint32_count - 1` when count may be 0.
- #6: ISR-visible flags via pointer dereference.
- #12: Verify `end.` placement after edits.
- #2: All errors need visible in-app feedback.
