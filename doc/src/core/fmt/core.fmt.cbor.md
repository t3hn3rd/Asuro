# core.fmt.cbor

`core.fmt.cbor` reads and writes the [RFC 8949 wire format](https://www.rfc-editor.org/rfc/rfc8949.html) using caller-owned byte buffers. It supports every major type, definite and indefinite lengths, all three float widths, arbitrary tag numbers, and simple values. The codec performs no heap allocation or I/O.

## Read and write

Initialize a `SizeUInt` offset to zero. Pass the buffer capacity when writing and the available byte count when reading. Each successful call advances the offset by the bytes it consumed or produced. Failed calls preserve the offset, output parameters, and destination bytes.

| API | Behavior |
| --- | --- |
| `ReadHead`, `WriteHead` | Read or write one header. String payload bytes, container children, and tagged items follow the header. |
| `ReadString`, `WriteString` | Read or write a complete definite-length byte or UTF-8 text string. `ReadString` returns a borrowed view valid while the input is intact. `WriteString` takes a source that does not overlap the encoded destination. |
| `SkipItem` | Check and consume one complete item, including nested values and text chunks. Useful for reading a sequence or skipping an unrecognised field. |
| `Validate` | Check that the buffer contains exactly one complete item with valid UTF-8. |
| `MakeHead`, `IntegerHead` | Construct a header from its kind and wire argument, or from an `Int64`. |
| `SingleHead`, `DoubleHead` | Construct a binary32 or binary64 header from a native float. |
| `TryGetInteger`, `TryGetFloat` | Convert a matching header to `Int64` or `Double`. Integer conversion can fail for values outside the native signed range. |

This example encodes a one-pair map whose key is the text string `id` and whose value is the integer 42. The result is `a1626964182a`.

```pascal
var
    buffer : array[0..15] of Byte;
    key : array[0..1] of Byte;
    offset : SizeUInt;
    status : TCBORStatus;
begin
    key[0] := Ord('i');
    key[1] := Ord('d');
    offset := 0;
    status := WriteHead(@buffer[0], SizeOf(buffer), offset, MakeHead(cborMap, 1));
    if status = cborOK then
        status := WriteString(@buffer[0], SizeOf(buffer), offset, @key[0], 2, cborText);
    if status = cborOK then
        status := WriteHead(@buffer[0], SizeOf(buffer), offset, IntegerHead(42));
end;
```

## Header arguments and streaming

| Kind | Meaning of `Argument` |
| --- | --- |
| `cborUnsigned`, `cborNegative` | Unsigned integer value, or the unsigned argument `n` representing `-1 - n`. |
| `cborBytes`, `cborText` | Payload length in bytes. |
| `cborArray`, `cborMap` | Element count or key/value pair count. |
| `cborTag` | Tag number. Exactly one item follows. |
| `cborSimple` | Simple value number in 0–19 or 32–255. |
| `cborFloat16`, `cborFloat32`, `cborFloat64` | Raw IEEE 754 bits. Use these to preserve float width, signed zero, and NaN payloads. |
| Booleans, null, undefined, indefinite-length starts, break | Zero. |

Use `ReadHead` and `WriteHead` for buffers that contain only part of a payload. Keep the unread payload length in a `QWord` and process as many bytes as each buffer holds. The largest header is nine bytes. For indefinite-length strings, process each definite-length chunk of the same kind until `cborBreak`. Each text chunk must contain complete UTF-8 code points. Map breaks are allowed between pairs.

The header functions operate on individual tokens. Use `Validate` to check the structure of a complete item before accepting it. Applications define tag semantics, check map-key uniqueness, and enforce any schema or deterministic encoding profile they require. The writer uses shortest integer, tag, and length encodings. Float width and map order are controlled by the caller.

## Status codes

| Status | Meaning |
| --- | --- |
| `cborOK` | The operation completed. |
| `cborNeedInput` | More bytes are required. Treat this as truncation at end of input. |
| `cborNeedOutput` | The destination has insufficient capacity. |
| `cborInvalid` | Invalid encoding, item structure, text, or API argument. |
| `cborUnsupported` | `ReadString` encountered an indefinite-length string. Use the header API to read its chunks. |
| `cborDepthLimit` | Complete-item traversal exceeded `CBOR_MAX_DEPTH` open containers or tags. Header reads remain available to callers with other depth limits. |

## Boot tests

`test.runAllTests` calls `core.fmt.cbor.tests.UnitTest`. The suite covers the examples in RFC 8949 Appendix A, malformed and truncated cases from Appendix F.1, UTF-8 errors, native number conversion, and buffer and nesting limits. Results appear under the `CBOR` syslog label.

## Owned values and map lookup

Use `core.fmt.cbor.values` when you need repeated lookups in a complete CBOR
document. `Parse` returns a status and an owned root. The input buffer can be
reused once parsing finishes. Release the root with `FreeValue`. Child values
and string data borrowed through the accessors remain valid until then.

```pascal
if core.fmt.cbor.values.Parse(buffer, size, root) = cborOK then begin
    gateway := GetMapItem(root, 'default-gateway');
    if GetString(gateway, data, length) then begin
        { Use data and length while root is alive. }
    end;
    FreeValue(root);
end;
```

Map keys are UTF-8 text without embedded NULs. Unsupported keys return
`cborUnsupported` and duplicate keys return `cborInvalid`. The wire codec
can still read maps with arbitrary key types. Text and byte values preserve
their lengths and embedded NULs. Chunked strings and indefinite containers
are materialised as their definite counterparts. Use `GetArraySize` and
`GetArrayItem` for arrays and the header helpers for numeric conversions.
