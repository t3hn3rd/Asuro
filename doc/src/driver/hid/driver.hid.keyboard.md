# driver.hid.keyboard

Keyboard event abstraction and modifier state tracking.

## Overview

This unit provides a hardware-independent keyboard event interface. Lower-level keyboard drivers (PS/2, USB HID) translate raw scan codes or HID keycodes into `TKeyInfo` records and call `reportKeyEvent`. This unit maintains global modifier key state and dispatches events to a registered hook callback.

## Dependencies

- (none — foundational HID unit)

## Types

### TKeyInfo

Describes a single key event.

| Field | Type | Description |
|---|---|---|
| `key_code` | `char` | ASCII character produced by this key |
| `is_down_code` | `boolean` | `true` if the key was pressed, `false` if released |
| `SHIFT_DOWN` | `boolean` | State of the Shift modifier at event time |
| `CTRL_DOWN` | `boolean` | State of the Ctrl modifier at event time |
| `ALT_DOWN` | `boolean` | State of the Alt modifier at event time |

## Functions and Procedures

### hook
```pascal
procedure hook(proc: pp_hook_method);
```
Registers a callback to receive `TKeyInfo` events. Only one hook is active at a time; calling `hook` again replaces the previous registration.

### reportKeyEvent
```pascal
procedure reportKeyEvent(info: TKeyInfo);
```
Called by a lower-level keyboard driver to report a key press or release. Updates the global modifier state (`is_shift`, `is_ctrl`, `is_alt`) based on the event, then invokes the registered hook callback if one is set.

## Notes

- `is_shift`, `is_ctrl`, and `is_alt` are module-level globals updated on every event and can be read directly to check current modifier state.
- The single-hook design means only one consumer (typically the terminal or a foreground application) receives keyboard input at a time.
