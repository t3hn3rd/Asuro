# driver.bus.usb.types

USB constants, descriptor structures, transfer types, and utility functions.

## Overview

This unit defines all shared types and constants used throughout the USB subsystem. It covers USB standard descriptor layouts, transfer abstractions, host controller driver vtables, and utility helpers for working with endpoints and setup packets. All USB subsystem units depend on this unit.

## Dependencies

- `core.memory`

## Constants

### Descriptor Types
`USB_DESC_DEVICE` (`$01`), `USB_DESC_CONFIG` (`$02`), `USB_DESC_STRING` (`$03`), `USB_DESC_INTERFACE` (`$04`), `USB_DESC_ENDPOINT` (`$05`), `USB_DESC_HUB` (`$29`).

### Request Codes
`USB_REQ_GET_STATUS`, `USB_REQ_CLEAR_FEATURE`, `USB_REQ_SET_FEATURE`, `USB_REQ_SET_ADDRESS`, `USB_REQ_GET_DESCRIPTOR`, `USB_REQ_SET_DESCRIPTOR`, `USB_REQ_GET_CONFIGURATION`, `USB_REQ_SET_CONFIGURATION`, `USB_REQ_GET_INTERFACE`, `USB_REQ_SET_INTERFACE`.

### Request Type Bits
`USB_REQTYPE_DIR_OUT` (`$00`), `USB_REQTYPE_DIR_IN` (`$80`), `USB_REQTYPE_TYPE_STANDARD` (`$00`), `USB_REQTYPE_TYPE_CLASS` (`$20`), `USB_REQTYPE_RECIPIENT_DEVICE` (`$00`), `USB_REQTYPE_RECIPIENT_INTERFACE` (`$01`), `USB_REQTYPE_RECIPIENT_ENDPOINT` (`$02`).

### Endpoint Direction and Type Masks
`USB_EP_DIR_IN` (`$80`), `USB_EP_DIR_OUT` (`$00`), `USB_EP_ATTR_CONTROL` (`$00`), `USB_EP_ATTR_ISOCHRONOUS` (`$01`), `USB_EP_ATTR_BULK` (`$02`), `USB_EP_ATTR_INTERRUPT` (`$03`).

### Speed Values
`USB_SPEED_LOW`, `USB_SPEED_FULL`, `USB_SPEED_HIGH`, `USB_SPEED_SUPER`.

### Class Codes
`USB_CLASS_HID` (`$03`), `USB_CLASS_HUB` (`$09`), `USB_CLASS_MASS_STORAGE` (`$08`), `USB_CLASS_CDC` (`$0A`).

### HC Type IDs
`HC_TYPE_UHCI`, `HC_TYPE_OHCI`, `HC_TYPE_EHCI`, `HC_TYPE_XHCI`.

## Types

### TUSBDeviceDescriptor
Standard USB device descriptor (18 bytes). Fields: `bLength`, `bDescriptorType`, `bcdUSB`, `bDeviceClass`, `bDeviceSubClass`, `bDeviceProtocol`, `bMaxPacketSize0`, `idVendor`, `idProduct`, `bcdDevice`, `iManufacturer`, `iProduct`, `iSerialNumber`, `bNumConfigurations`.

### TUSBConfigDescriptor
Standard USB configuration descriptor. Fields: `bLength`, `bDescriptorType`, `wTotalLength`, `bNumInterfaces`, `bConfigurationValue`, `iConfiguration`, `bmAttributes`, `bMaxPower`.

### TUSBInterfaceDescriptor
Standard USB interface descriptor. Fields: `bLength`, `bDescriptorType`, `bInterfaceNumber`, `bAlternateSetting`, `bNumEndpoints`, `bInterfaceClass`, `bInterfaceSubClass`, `bInterfaceProtocol`, `iInterface`.

### TUSBEndpointDescriptor
Standard USB endpoint descriptor. Fields: `bLength`, `bDescriptorType`, `bEndpointAddress`, `bmAttributes`, `wMaxPacketSize`, `bInterval`.

### TUSBHubDescriptor
USB hub class descriptor. Fields: `bDescLength`, `bDescriptorType`, `bNbrPorts`, `wHubCharacteristics`, `bPwrOn2PwrGood`, `bHubContrCurrent`, `DeviceRemovable`.

### TUSBSetupPacket
8-byte setup packet for control transfers. Fields: `bmRequestType`, `bRequest`, `wValue`, `wIndex`, `wLength`.

### TUSBTransferStatus
Enumeration of possible transfer outcomes: `tsPending`, `tsSuccess`, `tsError`, `tsStall`, `tsTimeout`, `tsCancelled`.

### TUSBDirection
`udIn`, `udOut`.

### TUSBPipeType
`uptControl`, `uptIsochronous`, `uptBulk`, `uptInterrupt`.

### TUSBEndpoint
Parsed endpoint descriptor with fields: `Address`, `Direction`, `PipeType`, `MaxPacketSize`, `Interval`.

### TUSBTransfer
Active transfer record. Fields: `Device`, `Endpoint`, `Data`, `Length`, `Status`, `HC_Private` (host controller internal use).

### TUSBDevice
Represents an enumerated USB device. Fields: `Address`, `Speed`, `HC` (host controller pointer), `DeviceDescriptor`, `ConfigDescriptor` (raw buffer), `ConfigLength`, `MaxPacketSize0`.

### TUSBHCDriver
Host controller vtable record. Function pointer fields:

| Field | Signature | Description |
|---|---|---|
| `HC_Type` | `uint32` | HC type identifier constant |
| `Init` | `function: boolean` | Hardware initialisation |
| `ScanPorts` | `procedure` | Detect connected devices |
| `Poll` | `procedure` | Process pending transfers |
| `ControlTransfer` | `function(...)` | Execute a control transfer |
| `InterruptTransfer` | `function(...)` | Queue an interrupt transfer |
| `BulkTransfer` | `function(...)` | Queue a bulk transfer |
| `CancelTransfer` | `procedure(...)` | Cancel a pending transfer |

## Functions and Procedures

### kalloc_aligned / kfree_aligned
```pascal
function kalloc_aligned(size, align: uint32): pointer;
procedure kfree_aligned(ptr: pointer);
```
Allocates or frees memory with the specified byte alignment. Required by host controller hardware that mandates aligned descriptor tables.

### make_setup_packet
```pascal
function make_setup_packet(bmRequestType, bRequest: uint8; wValue, wIndex, wLength: uint16): TUSBSetupPacket;
```
Constructs a `TUSBSetupPacket` from individual fields.

### usb_ep_number / usb_ep_is_in / usb_ep_transfer_type / usb_ep_pipe_type / usb_ep_direction
Helper functions that extract sub-fields from a raw `bEndpointAddress` or `bmAttributes` byte.

### usb_hc_init_record
```pascal
procedure usb_hc_init_record(hc: PUSBHCDriver);
```
Zero-initialises a `TUSBHCDriver` record before the host controller driver fills in its function pointers.

### UnitTest
```pascal
procedure UnitTest;
```
Verifies alignment behaviour of `kalloc_aligned` and correct construction of setup packets.
