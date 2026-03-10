# core.fmt.json

RFC 8259 compliant JSON parser, serializer, and accessor library.

## Overview

`core.fmt.json` provides a complete JSON implementation for the kernel. It can parse JSON text into an in-memory tree of `TJSONValue` nodes, serialize values back to JSON text, and navigate nested structures via dot/bracket path expressions (e.g. `"server.hosts[0].name"`).

All six JSON value types are supported (`null`, boolean, number, string, array, object), plus a `JSON_ERROR` variant that carries parse error details (byte offset and human-readable message). Numbers are stored as `Double` (64-bit IEEE 754) in full compliance with the JSON number grammar, including fractional and exponent parts.

Unicode escape sequences (`\uXXXX`) are supported for codepoints U+0000–U+007F; higher codepoints are emitted as `?` since the OS is ASCII-only.

## Dependencies

- `memory.heap` — `kalloc`, `kfree`
- `core.strings` — `stringCopy`, `stringNew`, `stringSize`, `stringConcat`, `stringSub`, `stringEquals`, `stringContains`, `intToString`, `doubleToStr`
- `core.ds.lists` — `DL_New`, `DL_Add`, `DL_Get`, `DL_Size`, `DL_Free`
- `core.ds.hashmap` — `new`, `add`, `get`, `forEach`
- `core.util` — architecture utilities
- `io.syslog` — test output (implementation section only)

## Types

### TJSONType
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
```
Discriminant enum for the value kinds. `JSON_ERROR` is used to report parse failures.

### TJSONValue / PJSONValue
```pascal
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
Tagged union representing any JSON value. Arrays store `PJSONValue` pointers in a `PDList` (element size = `sizeof(uint32)`). Objects store `PJSONValue` pointers in a `PHashMap` keyed by string.

On parse error, `Kind = JSON_ERROR`, `errPos` is the byte offset where the error occurred, and `errMsg` is a heap-allocated human-readable description.

## Functions and Procedures

### parse
```pascal
function parse(buf : pchar; len : uint32) : PJSONValue;
```
Parses `len` bytes of JSON text at `buf`. Returns a heap-allocated `PJSONValue` tree on success, or a `PJSONValue` with `Kind = JSON_ERROR` on failure. The caller must free the result with `freeValue` in both cases.

Trailing non-whitespace content after the root value is rejected as an error.

### getType
```pascal
function getType(val : PJSONValue) : TJSONType;
```
Returns the type of `val`, or `JSON_NULL` if `val` is `nil`.

### getBool
```pascal
function getBool(val : PJSONValue) : boolean;
```
Returns `val^.boolVal` if `val` is `JSON_BOOL`, otherwise `false`.

### getNumber
```pascal
function getNumber(val : PJSONValue) : Double;
```
Returns `val^.numberVal` if `val` is `JSON_NUMBER`, otherwise `0.0`.

### getString
```pascal
function getString(val : PJSONValue) : pchar;
```
Returns `val^.stringVal` if `val` is `JSON_STRING`, otherwise `nil`. The returned pointer is owned by the value — do not free it directly.

### getArraySize
```pascal
function getArraySize(val : PJSONValue) : uint32;
```
Returns the number of elements in the array, or `0` if `val` is not an array.

### getArrayItem
```pascal
function getArrayItem(val : PJSONValue; idx : uint32) : PJSONValue;
```
Returns the element at zero-based `idx`, or `nil` if out of range or not an array.

### getObjectItem
```pascal
function getObjectItem(val : PJSONValue; key : pchar) : PJSONValue;
```
Returns the value associated with `key`, or `nil` if the key is not present or `val` is not an object.

### getByPath
```pascal
function getByPath(root : PJSONValue; path : pchar) : PJSONValue;
```
Navigates a nested JSON structure using a dot/bracket path expression. Examples:
- `"name"` — object key lookup
- `"items[0]"` — array index
- `"server.hosts[2].ip"` — combined navigation

Returns `nil` if any segment of the path is not found or the type doesn't match (e.g. array index on a non-array).

### getStringByPath
```pascal
function getStringByPath(root : PJSONValue; path : pchar; default : pchar) : pchar;
```
Returns the string at `path`, or `default` if the path is missing or the value is not a string.

### getNumberByPath
```pascal
function getNumberByPath(root : PJSONValue; path : pchar; default : Double) : Double;
```
Returns the number at `path`, or `default` if the path is missing or the value is not a number.

### getBoolByPath
```pascal
function getBoolByPath(root : PJSONValue; path : pchar; default : boolean) : boolean;
```
Returns the boolean at `path`, or `default` if the path is missing or the value is not a boolean.

### getObjectByPath
```pascal
function getObjectByPath(root : PJSONValue; path : pchar) : PJSONValue;
```
Returns the object at `path`, or `nil` if the path is missing or the value is not an object.

### getArrayByPath
```pascal
function getArrayByPath(root : PJSONValue; path : pchar) : PJSONValue;
```
Returns the array at `path`, or `nil` if the path is missing or the value is not an array.

### newNull / newBool / newNumber / newString / newArray / newObject
```pascal
function newNull : PJSONValue;
function newBool(b : boolean) : PJSONValue;
function newNumber(n : Double) : PJSONValue;
function newString(s : pchar) : PJSONValue;
function newArray : PJSONValue;
function newObject : PJSONValue;
```
Builder functions for constructing JSON values programmatically. `newString` copies its argument. The caller owns the returned value and must eventually free it with `freeValue`.

### arrayAppend
```pascal
procedure arrayAppend(arr : PJSONValue; item : PJSONValue);
```
Appends `item` to the array `arr`. Does nothing if `arr` is not a `JSON_ARRAY`. Ownership of `item` transfers to the array — it will be freed when the array is freed.

### objectSet
```pascal
procedure objectSet(obj : PJSONValue; key : pchar; item : PJSONValue);
```
Sets `key` to `item` in the object `obj`. The key is copied internally. Ownership of `item` transfers to the object.

### stringify
```pascal
function stringify(val : PJSONValue) : pchar;
```
Serializes `val` to a heap-allocated JSON text string. String values are properly escaped. Returns `"null"` for `nil` or error values. The caller must free the result with `kfree`.

### freeValue
```pascal
procedure freeValue(val : PJSONValue);
```
Recursively frees a `PJSONValue` and all nested values it owns. Safe to call with `nil`. Handles all types including arrays (frees each element), objects (frees each key-value pair), strings, and error messages.

### UnitTest
```pascal
procedure UnitTest;
```
Runs the complete JSON test suite and logs a pass/fail summary to syslog under the `'JSON'` channel. Tests cover parsing of all value types, escape handling, error reporting, path accessors, builders, stringify, and round-trip equivalence.

## Notes

All functions returning `PJSONValue` return heap-allocated values. The caller is responsible for calling `freeValue` to avoid memory leaks.

The parser is a recursive-descent implementation. Maximum nesting depth is limited only by kernel stack size (practically 50–100 levels, which is sufficient for configuration-style JSON).

String values returned by `getString` and `getStringByPath` are owned by the JSON tree — do not free them directly. They become invalid after `freeValue` is called on the owning tree.
