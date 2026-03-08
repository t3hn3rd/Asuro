# driver.storage.vol.gpt

GUID Partition Table (GPT) parsing and validation.

## Overview

This unit provides types and functions for reading and validating GPT headers and partition entries. The volume manager uses it when a protective MBR entry (type `$EE`) is detected. The unit reads the primary GPT header from LBA 1, validates its signature and CRC32, then reads the partition entry array and validates its CRC. If the primary header fails, it attempts to fall back to the backup header at the last LBA of the device.

## Dependencies

- `core.enc.crc`
- `memory.heap`
- `driver.storage.types`
- `io.syslog`
- `debug.tracer`
- `core.util`, `arch.x86.util`
- `driver.storage.mgr` (implementation)

## Constants

| Constant | Value | Description |
|---|---|---|
| `GPT_SIGNATURE` | `'EFI PART'` | 8-byte GPT header signature |
| `GPT_HEADER_LBA` | `1` | LBA of the primary GPT header |
| `GPT_STANDARD_ENTRY_SIZE` | `128` | Standard partition entry size in bytes |
| `GPT_STANDARD_ENTRY_COUNT` | `128` | Standard number of partition entries |
| `MBR_TYPE_GPT_PROTECTIVE` | `$EE` | MBR partition type indicating a GPT protective entry |

## Types

### TGPTHeader / PGPTHeader

GPT header structure (packed). The kernel operates in 32-bit mode; 64-bit LBA fields are split into low and high `uint32` components. The high halves are checked for zero before use to ensure the LBA is within 32-bit addressable range.

| Field | Description |
|---|---|
| `Signature` | 8-byte `'EFI PART'` signature |
| `Revision` | GPT version |
| `HeaderSize` | Size of this header in bytes |
| `HeaderCRC32` | CRC32 of header bytes (this field zeroed during calculation) |
| `MyLBA` / `MyLBA_Hi` | LBA of this header |
| `AlternateLBA` / `AlternateLBA_Hi` | LBA of backup header |
| `FirstUsableLBA` / `LastUsableLBA` | Range of usable LBAs |
| `DiskGUID` | Disk GUID |
| `PartEntryLBA` / `PartEntry_Hi` | LBA of the partition entry array |
| `NumPartEntries` | Number of partition entries |
| `PartEntrySize` | Size of each partition entry |
| `PartArrayCRC32` | CRC32 of the partition entry array |

### TGPTPartitionEntry / PGPTPartitionEntry

One GPT partition entry (128 bytes, packed).

| Field | Description |
|---|---|
| `TypeGUID` | Partition type GUID (all-zero = empty slot) |
| `UniqueGUID` | Unique partition GUID |
| `StartLBA` / `StartLBA_Hi` | First LBA of partition |
| `EndLBA` / `EndLBA_Hi` | Last LBA of partition (inclusive) |
| `Attributes` | Partition attribute flags |
| `Name` | UTF-16LE partition name (36 code units) |

## Functions and Procedures

### gpt_guid_is_zero

```pascal
function gpt_guid_is_zero(const g : TGuid) : boolean;
```

Returns true if all fields of the GUID are zero. Used to detect empty partition entries.

### gpt_validate_header

```pascal
function gpt_validate_header(header : PGPTHeader) : boolean;
```

Validates a GPT header by checking the `'EFI PART'` signature and computing the CRC32 of the header bytes (with the `HeaderCRC32` field zeroed during calculation). Returns true if both checks pass. Logs diagnostics to `io.syslog` on failure.

### gpt_validate_entries

```pascal
function gpt_validate_entries(header : PGPTHeader; entryBuf : puint8) : boolean;
```

Validates the partition entry array CRC32 against `header^.PartArrayCRC32`. Returns true if the CRC matches.

### gpt_read_header

```pascal
function gpt_read_header(device : PStorage_Device) : PGPTHeader;
```

Reads and validates the GPT header from `device`. Tries the primary header at LBA 1 first; if validation fails, attempts the backup header at `AlternateLBA`. Returns a heap-allocated `TGPTHeader` on success (caller must `kfree`), or nil on failure.

### gpt_read_entries

```pascal
function gpt_read_entries(device : PStorage_Device; header : PGPTHeader) : PGPTPartitionEntry;
```

Reads the partition entry array from disk based on the location and count in `header`. Validates the array CRC. Returns a heap-allocated buffer on success (caller must `kfree`), or nil on failure.

## Notes

- All 64-bit LBA fields are stored as two `uint32` components. The volume manager skips any partition whose high LBA word is non-zero.
- CRC32 computation is delegated to `core.enc.crc.CRC32`.
