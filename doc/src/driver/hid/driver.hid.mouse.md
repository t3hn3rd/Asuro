# driver.hid.mouse

Mouse event abstraction, state tracking, and hook dispatch.

## Overview

This unit provides a hardware-independent mouse interface. Lower-level mouse drivers (PS/2, USB HID) call the event functions here after decoding raw packet data. This unit maintains global cursor position, button state, and scroll accumulator, clamping coordinates to the framebuffer dimensions. Up to 8 hooks can be registered to receive mouse events.

## Dependencies

- `driver.video` (for `frontBufferWidth`/`frontBufferHeight` clamping bounds)

## Types

### TMouseEventType

Enumeration of mouse event types:

| Value | Description |
|---|---|
| `MOVE` | Cursor position changed |
| `LMB_DOWN` | Left button pressed |
| `LMB_UP` | Left button released |
| `LMB_CLICK` | Left button clicked (down then up) |
| `RMB_DOWN` | Right button pressed |
| `RMB_UP` | Right button released |
| `RMB_CLICK` | Right button clicked |

## Functions and Procedures

### registerMouseHook
```pascal
procedure registerMouseHook(hook: TMouseHookProc);
```
Adds a callback to the hook list (up to 8 hooks). The callback receives the event type, current X/Y position, and scroll delta.

### removeMouseHook
```pascal
procedure removeMouseHook(hook: TMouseHookProc);
```
Removes a previously registered hook callback.

### setMousePos
```pascal
procedure setMousePos(x, y: sint32);
```
Sets the cursor position, clamping to `[0, frontBufferWidth-1]` and `[0, frontBufferHeight-1]`.

### getMouseScroll
```pascal
function getMouseScroll: sint32;
```
Returns the accumulated scroll wheel delta since the last call and resets the accumulator to zero.

### fireMouseEvent
```pascal
procedure fireMouseEvent(event: TMouseEventType; x, y: sint32; scroll: sint32);
```
Updates internal state (position, button flags, scroll accumulator) for the given event type and dispatches to all registered hooks.

## Notes

- `MouseX`, `MouseY`, `MouseLMB`, `MouseRMB`, and `ScrollAccum` are module-level globals accessible directly for polling-style consumers.
- Coordinate clamping relies on `driver.video.frontBufferWidth` and `driver.video.frontBufferHeight`, so those must be valid before mouse events are processed.
