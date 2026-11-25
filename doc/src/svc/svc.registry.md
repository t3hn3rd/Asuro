# Settings registry

The registry discovers `/disk/<mount>/sys/asuro.db` after the boot
volume mount pass. Boot media also accepts `asuro.db.cbor` when
`asuro.db` is absent. The ISO build packages
`iso/sys/asuro.db.cbor` as `/sys/asuro.db`. A seed database is a
definite-length CBOR map. Nested maps form directories and
tagged scalars or untagged byte strings form files. Keys are non-empty
UTF-8 path components of up to 255 bytes. Duplicate keys, NULs, slashes,
and dot components are rejected.

Volumes load in ascending mount-name order. Later volumes override earlier
ones. The alphabetically first writable volume with offset writes takes
highest precedence. Directories merge recursively. A file and directory
collision is resolved in favor of the higher layer. A malformed database is
ignored as a whole. With no valid database or writable volume, `/cfg` stays unmounted.

The registry mounts a device-less filesystem at `/cfg` through
`driver.storage.fs.registry`. It explicitly opts into VFS dispatch
without a block device. The filesystem driver owns the VFS callbacks, translates typed filenames
into logical key paths, and tracks pending keys in per-open state.
The service owns the tree and accepts path-based operations. A first write
creates and validates the key in one service call. The driver holds no
pointers into the tree.
`/sys` links to the boot volume's system files through `mount.asr`.

The service scans CBOR headers with bounded buffers and keeps names and
file offsets in memory. `SetCacheBudget` controls the shared value cache
before discovery. It defaults to 50 MiB. Values outside the cache budget
are read from their source file on demand. Index memory is separate.

## Value types and writes

The registry uses application-specific CBOR tags numbered `65000 + ID`
for IDs 1–12. Each tag wraps a native CBOR value. In CBOR diagnostic
notation, a key named `bpp` with value `65002(32)` appears as `bpp.u8`
in the VFS. The CBOR key stays `bpp`. Raw values remain untagged on disk
and appear under their original names.

A tagged text entry such as `"target": 65011("/cfg/example/bpp.u8")`
appears as `target.txt`. Reading that file returns the UTF-8 bytes
of `/cfg/example/bpp.u8`.

| ID | Type | VFS suffix | CBOR payload | File bytes |
| --- | --- | --- | --- | --- |
| 1 | UINT32 | `.u32` | Unsigned integer | 4 bytes |
| 2 | UINT8 | `.u8` | Unsigned integer | 1 byte |
| 3 | UINT16 | `.u16` | Unsigned integer | 2 bytes |
| 4 | UINT64 | `.u64` | Unsigned integer | 8 bytes |
| 5 | INT8 | `.i8` | Integer | 1 byte |
| 6 | INT16 | `.i16` | Integer | 2 bytes |
| 7 | INT32 | `.i32` | Integer | 4 bytes |
| 8 | INT64 | `.i64` | Integer | 8 bytes |
| 9 | FLOAT32 | `.f32` | Binary32 float | 4 bytes |
| 10 | FLOAT64 | `.f64` | Binary64 float | 8 bytes |
| 11 | TEXT | `.txt` | Definite-length text string | UTF-8 |
| 12 | BOOLEAN | `.bool` | False or true | 1 byte with value 0 or 1 |
| 13 | Bytes | None added | Untagged byte string | Unchanged |

The listed suffixes are reserved for typed files. Raw keys and directory
names can contain dots and must avoid those exact suffixes.

Numeric file bytes are little-endian. Signed integers use two's complement.
Floats use the indicated IEEE 754 width. Preserve that width when editing
the CBOR file. Text reads return UTF-8 bytes without a terminator.

Writes to existing files replace the complete payload in one write at
offset zero. A read or write of `bpp.u8` uses one byte, so `20` sets it
to 32. A write to a `.txt` file uses plain UTF-8. The published file
determines the type. Invalid writes return zero and leave the setting intact.
In-memory overrides have their own budget equal to the value cache limit.

The [Settings Service schema](svc.settings.md#schema) defines how the
Settings layer interprets the `/cfg/settings` subtree.

## Runtime creation and saving

Create a parent directory with `CreateDirectory` and then open the new
filename with `OpenFile(..., omCreate)` or `OpenFileAsync`. Write the
complete initial payload at offset zero. For example, create
`/cfg/example`, open `/cfg/example/volume.u32`, and write four
little-endian bytes. A new key becomes visible after the first valid
write. Closing an unwritten handle discards it. A filename with no
recognized type suffix stores raw bytes. Existing keys continue to
use the ordinary write and batch Apply paths.

The registry waits one second after the last successful mutation
before saving. It uses regular VFS file operations on the first
alphabetical writable volume that supports offset reads and writes.
Without such a volume, changes last for the session. Failed saves
remain pending and are retried after another quiet interval.

The writable database is `/sys/asuro.db`. The service writes the next
generation to `/sys/~asuro.db` before replacing the primary. A saved
generation is a CBOR array containing the generation number, the
writable key map, and a matching completion marker. On boot, the service
tries the newest generation first and falls back to the other file if
validation fails. After a successful save only the primary is needed.

On the first load from older builds, the service can merge the newest
valid legacy save (`asuroa.cbr`, `asurob.cbr`, or
`asuro-save-*.cbor`) over the writable base database. It retains the
legacy files. The next dirty save uses the new names and preserves the
writable base keys. Writable data is restored into the existing
override budget. If the primary can be read only as a streamed source,
the service keeps it intact and disables disk saves for that session.

## Storage and VFS gaps

- Registry deletion and truncation are pending.
- The VFS has no general file flush operation. A completed save cannot
  guarantee power-loss durability. Compression and checksums are pending.
- Offset reads are required for uncached values. Hotplug rediscovery is pending.

## Startup readiness

A scheduled process can call `svc.registry.WaitReady` before reading
`/cfg`, or use `IsReady` to check without waiting. Readiness means the
initial discovery completed, including when no database was found. A
boot-manager dependency on `svc.registry` orders worker creation only.

The graphics service waits for readiness with the splash still visible.
The GPU reads the mode from `/cfg/asuro/driver/video/gpu` and tries the
available drivers in priority order, just as it does for `SETRES`.
`resolution/width.u32` and `resolution/height.u32` are UINT32 values,
and `bpp.u8` is UINT8. The desktop accepts 16 or 32 bits per pixel.
If the settings are incomplete or the mode is unavailable, startup uses
the existing display mode.

The desktop reads the UTF-8 path at
`/cfg/asuro/driver/video/desktop/background.txt`, prepares the image
on the desktop screen, then tears down the splash. The ISO seed points to
`/sys/background.tga`. The loader accepts uncompressed 24-bit and 32-bit
true-colour TGA. A 1920×1080 image is loaded in one buffered VFS read.
Other sizes are cropped and scaled using one source row at a time.
The wallpaper is centred, uniformly enlarged when needed to cover the
display, and clipped at the desktop edges. Display mode changes update
the scale.
Missing or invalid settings keep the gradient.
