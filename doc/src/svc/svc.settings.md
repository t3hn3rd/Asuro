# Settings Service

The Settings Service (`svc.settings`) is the planned layer that interprets
settings definitions and will notify consumers when settings change. The
Settings app currently reads these definitions and applies edits. The
[registry service](svc.registry.md) provides the CBOR-backed database,
typed values, and VFS access used by both.

## Schema

A settings definition tells the Settings app how to display and edit an
existing configuration value. The registry database has a top-level
`settings` key containing a map. Each child of that map is a section.
For example, `/cfg/settings/display/items/resolution` describes a control
whose live values are under `/cfg/asuro/driver/video/gpu`.

### Formal structure

The grammar describes the `settings` entry within the larger database
map. Names in quotes are exact, case-sensitive keys or literal Text
values. A field followed by `?` is optional. `|` denotes alternatives.
`&` combines fields into the same map, and map order has no meaning.
`map<Id, T>` has zero or more entries and `nonempty-map<Id, T>` has at
least one. A map cannot contain duplicate keys. Only the fields shown
for that map are part of the schema.

```text
SettingsEntry = { "settings": map<Id, Section> }

Section = SectionFields & { "items": map<Id, Item> }
SectionFields = { "label"?: Text, "description"?: Text, "order"?: UInt32 }
ItemFields = SectionFields

Item = ItemFields & (Dropdown | Toggle | TextInput | FilePicker | Slider)
Dropdown = { "control": "dropdown" } & (SharedTarget | PerChoiceTargets | FileBacked)
SharedTarget = {
  "target": TypedTarget,
  "choices": nonempty-map<Id, ChoiceFields & { "value": TypedValue }>
}
PerChoiceTargets = { "choices": nonempty-map<Id, MultiTargetChoice> }
MultiTargetChoice = ChoiceFields & { "changes": nonempty-map<Id, Change> }
ChoiceFields = { "label"?: Text, "order"?: UInt32 }
Change = { "target": TypedTarget, "value": TypedValue }

Toggle    = { "control": "toggle", "target": BoolTarget }
TextInput = { "control": "text",   "target": TextTarget }
FilePicker = { "control": "file",  "target": TextTarget }
Slider = {
  "control": "slider", "target": UInt32Target,
  "min": UInt32, "max": UInt32, "step": UInt32
}
```

- `Id` is a registry path component. Use stable IDs across database layers
  so a higher layer can update a section, item, choice, or change by ID.
  IDs are scoped to their containing map. For example, `label` within
  `items` is an item ID, while `label` directly within an item is a field.
- `Text` and `UInt32` are registry value types. The grammar uses CBOR keys
  and values. The registry reference defines their representation in the
  database and their VFS filenames.
  [Registry value types](svc.registry.md#value-types-and-writes)
- A `TypedTarget` is a Text value containing the full absolute VFS filename
  of an existing typed setting under `/cfg`, including its suffix.
  `BoolTarget`, `TextTarget`, and `UInt32Target` require `.bool`, `.txt`,
  and `.u32` respectively.
- `TypedValue` is a tagged registry value of the type specified by its
  target. In `SharedTarget` that target is on the item. In `Change` it
  is in the same map as the value.

### Nesting and presentation

In the tree below, angle-bracketed names are IDs. The two branches under
an item apply to dropdowns.

```text
settings
└── <section-id>
    └── items
        └── <item-id>
            ├── choices
            │   └── <choice-id>
            │       └── changes
            │           └── <change-id>
            └── choices-source
                └── columns
                    └── <column-id>
```

Sections are peers and cannot contain subsections. An item lives directly
under a section's `items` map and cannot contain other items. `All` is
provided by the app and lists matching items grouped by their sections.
A section heading in the results appears when at least one of its items
is visible. Search matches the section name, item name, and item
description without regard to case.

### Sections and items

| Map | Key | Type | Rule |
| --- | --- | --- | --- |
| Section | `label` | Text | Display name. Defaults to the section ID. |
| Section | `description` | Text | Optional text beneath the heading. |
| Section | `order` | UInt32 | Optional sort order. |
| Section | `items` | Map | Required. Item IDs mapped to item definitions. |
| Item | `label` | Text | Display name. Defaults to the item ID. |
| Item | `description` | Text | Optional help text. |
| Item | `order` | UInt32 | Optional sort order. |
| Item | `control` | Text | Required. Use a control from the table below. |
| Item | `target` | Text | Required for single-value controls. Also used by inline dropdowns with a shared target. |

Sections, items and inline choices sort by ascending `order`, then by ID.
Entries that omit `order` use the maximum UInt32 sort value.

| Control | Control-specific fields |
| --- | --- |
| `dropdown` | Use `choices` for inline choices or `choices-source` for file-backed choices. See the file-backed definition below. |
| `toggle` | `target` points to a `.bool` file. |
| `text` | `target` points to a `.txt` file. Settings accepts up to 4096 bytes of UTF-8. |
| `file` | `target` points to a `.txt` file that stores the path selected in the file picker. |
| `slider` | `target` points to a `.u32` file. Required UInt32 fields `min`, `max` and `step` define the range. Use `min < max <= 2147483647` and `step > 0`. The current value must lie in the range. |

### Single-value controls

- **Toggle** displays the current boolean. Switching it stages `true`
  or `false` for the target. A binary preference such as notifications
  fits this control.
- **Text** edits a UTF-8 value in a single-line field. Use it for names
  or other short strings. The stored value must contain no NUL bytes and
  the app accepts up to 4096 bytes.
- **File** displays the current path and opens the file picker. Choosing
  a file stages its path as text. The target stores the path and the
  owning component opens the selected file.
- **Slider** edits an unsigned integer between `min` and `max`
  inclusive. The step grid starts at `min`. Dragging snaps down to the
  nearest grid point, with `max` selectable even if it falls between
  steps. For example, a slider from 0 to 100 with a step of 5 offers
  0, 5, 10, and so on through 100.

This complete example places all four controls in one section. The
definitions describe the UI. The values under `example` initialize the
files that the controls edit.

```text
{
  "settings": {
    "preferences": {
      "label": 65011("Preferences"),
      "description": 65011("General preferences"),
      "order": 65001(10),
      "items": {
        "notifications": {
          "label": 65011("Notifications"),
          "order": 65001(10),
          "control": 65011("toggle"),
          "target": 65011("/cfg/example/notifications.bool")
        },
        "display-name": {
          "label": 65011("Display name"),
          "order": 65001(20),
          "control": 65011("text"),
          "target": 65011("/cfg/example/display-name.txt")
        },
        "background": {
          "label": 65011("Background image"),
          "order": 65001(30),
          "control": 65011("file"),
          "target": 65011("/cfg/example/background.txt")
        },
        "volume": {
          "label": 65011("Volume"),
          "order": 65001(40),
          "control": 65011("slider"),
          "target": 65011("/cfg/example/volume.u32"),
          "min": 65001(0),
          "max": 65001(100),
          "step": 65001(5)
        }
      }
    }
  },
  "example": {
    "notifications": 65012(true),
    "display-name": 65011("My Asuro"),
    "background": 65011("/sys/background.tga"),
    "volume": 65001(50)
  }
}
```

### Inline dropdown choices

Put inline choices in `items/<item-id>/choices/<choice-id>`. Each choice
may contain a Text `label` and a UInt32 `order`. The label defaults to the
choice ID. Keep dropdown labels on one line.

- **Shared target.** Put `target` on the item and put a tagged `value` in
  each choice. Its type must match the target suffix. For example, a
  choice for `bpp.u8` can use `"value": 65002(32)`.
- **Multiple targets.** Omit the item's `target` and give each choice a
  `changes` map. Every `changes/<change-id>` entry contains a Text
  `target` and a tagged `value` of the corresponding type. A choice
  must contain at least one change. Use each target once per choice.

A shared-target dropdown fits a setting such as colour depth. This item
belongs under `settings/display/items`.

```text
"colour-depth": {
  "label": 65011("Colour depth"),
  "control": 65011("dropdown"),
  "target": 65011("/cfg/asuro/driver/video/gpu/bpp.u8"),
  "choices": {
    "depth-16": { "label": 65011("16-bit"), "value": 65002(16) },
    "depth-32": { "label": 65011("32-bit"), "value": 65002(32) }
  }
}
```

For example, the following item changes both resolution dimensions in
one choice:

```text
"resolution": {
  "label": 65011("Resolution"),
  "control": 65011("dropdown"),
  "choices": {
    "1080p": {
      "label": 65011("1920 x 1080"),
      "changes": {
        "width": {
          "target": 65011("/cfg/asuro/driver/video/gpu/resolution/width.u32"),
          "value": 65001(1920)
        },
        "height": {
          "target": 65011("/cfg/asuro/driver/video/gpu/resolution/height.u32"),
          "value": 65001(1080)
        }
      }
    }
  }
}
```

### File-backed dropdown choices

`choices-source` is an item-level map that describes where choices come
from. Settings reads the source file when it loads the item and
converts each valid row into an ordinary dropdown choice with a change set.
The source file can live under `/dev`, and registry targets still live
under `/cfg`. The item omits `target` because the column mappings supply
the targets. If a merged item contains both `choices-source` and
`choices`, the source takes precedence. A missing, unreadable or empty
source leaves the dropdown unavailable, so static choices from a lower
layer cannot offer modes the machine may lack.

`FileBacked` defines the third form of `Dropdown`.

```text
FileBacked = { "choices-source": ChoiceSource }
ChoiceSource = {
  "source": Text, "format": "integer-rows-v1", "label": Text,
  "columns": nonempty-map<Id, Column>
}
Column = { "index": UInt32, "target": IntegerTarget }
```

An `IntegerTarget` is a `TypedTarget` ending in one of `.u8`, `.u16`,
`.u32`, `.u64`, `.i8`, `.i16`, `.i32`, or `.i64`.

| Map | Key | Type | Rule |
| --- | --- | --- | --- |
| `choices-source` | `source` | Text | Required absolute VFS path to the file. |
| `choices-source` | `format` | Text | Required format identifier. The first format is `integer-rows-v1`. |
| `choices-source` | `label` | Text | Required single-line template. Each `{column-id}` refers to a key in `columns`. |
| `choices-source` | `columns` | Map | Required nonempty map of column IDs to definitions. |
| Column | `index` | UInt32 | Required zero-based field position. Indexes must be unique and contiguous from zero. |
| Column | `target` | Text | Required existing registry filename with an integer suffix. Each target must be unique within the source. |

`integer-rows-v1` uses one row per line with decimal integers separated by
ASCII spaces or tabs. Signed targets accept a leading minus. Blank lines
are ignored. Each row must supply one field per declared column and every
integer must fit the type declared by its target suffix. Settings skips
malformed rows and preserves source order for valid rows. Source files
are limited to 64 KiB and definitions to 256 columns. The expanded label
must fit within 4096 bytes. An invalid source definition or a source with
no valid rows leaves the dropdown unavailable.

The GPU framework publishes `/dev/video/gpu/modes` after driver probing.
It lists distinct resolution and colour depth combinations that the
available drivers report for the desktop.

```text
"display-mode": {
  "label": 65011("Display mode"),
  "control": 65011("dropdown"),
  "choices-source": {
    "source": 65011("/dev/video/gpu/modes"),
    "format": 65011("integer-rows-v1"),
    "label": 65011("{width} x {height} ({bpp}-bit)"),
    "columns": {
      "width": {
        "index": 65001(0),
        "target": 65011("/cfg/asuro/driver/video/gpu/resolution/width.u32")
      },
      "height": {
        "index": 65001(1),
        "target": 65011("/cfg/asuro/driver/video/gpu/resolution/height.u32")
      },
      "bpp": {
        "index": 65001(2),
        "target": 65011("/cfg/asuro/driver/video/gpu/bpp.u8")
      }
    }
  }
}
```

The row `1920 1080 32` displays as **1920 x 1080 (32-bit)** and set
all three targets together. Keeping the three values in one row preserves
which colour depths are supported at each resolution.

### Matching and applying values

An item with an unknown control or missing required data can appear as
**Unavailable**. An inline dropdown skips choices whose value definitions
cannot be read. The schema describes valid definitions, and the current
Settings app reads the fields it needs without a separate validation pass.

Settings matches the current dropdown selection against the complete
change set for each choice. An unmatched current value appears as
**Custom**. Draft edits survive category changes and searches. Apply
validates the entire batch and publishes the in-memory values together.
Each target can appear once per batch. The registry saves applied values after one quiet second when a writable
volume is available. Without one, changes last for the session.
