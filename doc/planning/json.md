# JSON Library Plan — `core.fmt.json.pas`

## General Rules

- Always keep `doc/src/core/fmt/core.fmt.json.md` up-to-date with any changes to the implementation.
- Add any generic utility code that isn't specific to the JSON unit to the appropriate place (e.g. `doubleToStr` in `core.strings.pas`, number-related helpers in `core.util.pas`) and update the corresponding documentation accordingly.

## Spec Compliance

Full RFC 8259 compliance:
- All 6 value types: `null`, `true`, `false`, number, string, object, array
- **Numbers**: full JSON number grammar — integer, fractional, and exponent parts, stored as `Double`
- **Strings**: full escape support including `\uXXXX` (codepoints U+0000-U+007F emitted as bytes; higher codepoints emit `?` in v1 since the OS is ASCII-only)
- **Whitespace**: skip `$20`, `$09`, `$0A`, `$0D` between tokens

## Data Model — Unified with `JSON_ERROR`

```pascal
TJSONType = (
    JSON_NULL,
    JSON_BOOL,
    JSON_NUMBER,
    JSON_STRING,
    JSON_ARRAY,
    JSON_OBJECT,
    JSON_ERROR
);

PJSONValue = ^TJSONValue;
TJSONValue = record
    Kind : TJSONType;
    case TJSONType of
        JSON_BOOL:   (boolVal   : boolean);
        JSON_NUMBER: (numberVal : Double);
        JSON_STRING: (stringVal : pchar);
        JSON_ARRAY:  (arrayVal  : PDList);
        JSON_OBJECT: (objectVal : PHashMap);
        JSON_ERROR:  (errPos    : uint32;
                      errMsg    : pchar);
end;
```

`parse()` always returns `PJSONValue`. The caller checks `result^.Kind = JSON_ERROR` for failure. The error carries the byte offset and a human-readable message.

## Public API

```pascal
{ --- Parsing --- }
function  parse(buf : pchar; len : uint32) : PJSONValue;

{ --- Path accessors --- }
function  getByPath(root : PJSONValue; path : pchar) : PJSONValue;
function  getStringByPath(root : PJSONValue; path : pchar; default : pchar) : pchar;
function  getNumberByPath(root : PJSONValue; path : pchar; default : Double) : Double;
function  getBoolByPath(root : PJSONValue; path : pchar; default : boolean) : boolean;
function  getObjectByPath(root : PJSONValue; path : pchar) : PJSONValue;
function  getArrayByPath(root : PJSONValue; path : pchar) : PJSONValue;

{ --- Direct accessors --- }
function  getType(val : PJSONValue) : TJSONType;
function  getBool(val : PJSONValue) : boolean;
function  getNumber(val : PJSONValue) : Double;
function  getString(val : PJSONValue) : pchar;
function  getArraySize(val : PJSONValue) : uint32;
function  getArrayItem(val : PJSONValue; idx : uint32) : PJSONValue;
function  getObjectItem(val : PJSONValue; key : pchar) : PJSONValue;

{ --- Builders --- }
function  newNull : PJSONValue;
function  newBool(b : boolean) : PJSONValue;
function  newNumber(n : Double) : PJSONValue;
function  newString(s : pchar) : PJSONValue;
function  newArray : PJSONValue;
function  newObject : PJSONValue;

{ --- Mutation --- }
procedure arrayAppend(arr : PJSONValue; item : PJSONValue);
procedure objectSet(obj : PJSONValue; key : pchar; item : PJSONValue);

{ --- Serialization --- }
function  stringify(val : PJSONValue) : pchar;

{ --- Cleanup --- }
procedure freeValue(val : PJSONValue);

{ --- Tests --- }
procedure UnitTest;
```

## Parser Internals

Recursive-descent with a parser state record:

```pascal
TJSONParser = record
    buf    : pchar;
    len    : uint32;
    pos    : uint32;
    hasErr : boolean;
    errPos : uint32;
    errMsg : pchar;
end;
```

| Internal function | Role |
|---|---|
| `skipWS` | Skip `$20`, `$09`, `$0A`, `$0D` |
| `peek` | Return current char without advancing |
| `advance` | Return current char and increment `pos` |
| `expect` | Consume expected char or call `setError` |
| `setError` | Record `pos` + message, set `hasErr` flag |
| `parseValue` | Dispatch on first non-WS char |
| `parseString` | `"..."` with full `\` escape + `\uXXXX` handling |
| `parseNumber` | Full JSON number grammar -> `Double` |
| `parseArray` | `[` value (`,` value)* `]` |
| `parseObject` | `{` string `:` value (`,` ...) `}` |
| `parseLiteral` | `true` / `false` / `null` |

Every sub-parser checks `hasErr` on entry and bails immediately if set — errors propagate cleanly to the top without exceptions.

## Number Parsing (RFC 8259 compliant)

```
number = [ "-" ] int [ frac ] [ exp ]
int    = "0" / ( digit1-9 *DIGIT )
frac   = "." 1*DIGIT
exp    = ( "e" / "E" ) [ "+" / "-" ] 1*DIGIT
```

All arithmetic in `Double` via x87 FPU. Leading zeros rejected per spec (`01` is invalid).

## Number Serialization (internal `doubleToStr`)

`doubleToStr` is generic string utility code and belongs in `core.strings.pas` (not the JSON unit).

- If no fractional part -> emit as integer (via int64 -> digit extraction)
- Otherwise -> emit integer part, `.`, then fractional digits (up to 15 significant digits), trim trailing zeros
- Very large/small numbers -> scientific notation (`1.23e+10`)
- Negative -> leading `-`
- Zero -> `0`

## String Escapes (full spec)

**Parse:**

| Sequence | Byte |
|---|---|
| `\"` | `$22` |
| `\\` | `$5C` |
| `\/` | `$2F` |
| `\b` | `$08` |
| `\f` | `$0C` |
| `\n` | `$0A` |
| `\r` | `$0D` |
| `\t` | `$09` |
| `\uXXXX` | Emit byte if U+0000-U+007F, `?` otherwise |

**Stringify:** reverse mapping — emit `\n`, `\t`, etc. for control chars; `\\` and `\"` for those literals.

## Path Accessor Internals

Path syntax: `"key.nested[0].deep"` — dot-separated keys with `[N]` for array indices.

`getByPath` walks left to right:
1. Accumulate chars until `.`, `[`, or end-of-string -> object key lookup via `hashmap.get`
2. On `[` -> parse digits until `]` -> array index lookup via `DL_Get`
3. Continue until path exhausted or lookup returns nil

## `freeValue` — Recursive Cleanup

| Kind | Action |
|---|---|
| `JSON_STRING` | `kfree(stringVal)` |
| `JSON_ARRAY` | Iterate DList, `freeValue` each `PJSONValue`, then `DL_Free` |
| `JSON_OBJECT` | `hashmap.forEach` -> `freeValue` each value, then free the map |
| `JSON_ERROR` | `kfree(errMsg)` |
| All | `kfree` the `TJSONValue` record itself |

## Test Suite (`UnitTest`)

Follows the same pattern as `core.strings.pas` — nested `Assert` procedure, pass/fail counters, `PrintSummary` at end, log tag `'JSON'`.

**Test categories:**

| Category | What's tested |
|---|---|
| **Literals** | `null`, `true`, `false` |
| **Numbers** | Integer, negative, fractional, exponent, negative exponent, leading-zero rejection |
| **Strings** | Simple, escapes (`\n`, `\t`, `\\`, `\"`), `\uXXXX`, empty string |
| **Arrays** | Empty `[]`, nested, mixed types |
| **Objects** | Empty `{}`, nested, duplicate keys |
| **Path accessors** | Dot navigation, array indexing, combined, missing paths return default |
| **Error handling** | Unterminated string, trailing comma, missing colon, unexpected EOF, leading zeros |
| **Builders** | Construct values programmatically, verify with accessors |
| **Stringify** | Round-trip: `parse -> stringify -> parse` equivalence for each type |
| **freeValue** | Ensure no crashes on deeply nested structures (smoke test) |

## Dependencies

```pascal
uses
    memory.heap,
    core.strings,
    core.ds.lists,
    core.ds.hashmap,
    core.util;
```

## Files

```
src/core/fmt/core.fmt.json.pas     <- implementation + UnitTest
doc/src/core/fmt/core.fmt.json.md  <- documentation (keep up-to-date)
```
