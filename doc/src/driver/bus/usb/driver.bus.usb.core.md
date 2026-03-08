# driver.bus.usb.core

USB host controller management and device enumeration core.

## Overview

This unit is the central coordination layer of the USB subsystem. It manages a list of registered host controllers, drives device enumeration, dispatches transfers, and provides a completion hook system for asynchronous notifications. Upper-layer drivers interact with attached USB devices exclusively through this unit's transfer API.

## Dependencies

- `driver.bus.usb.types`
- `driver.mgr`
- `syslog`
- `core.memory`

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises internal host controller and completion hook tables.

### register_hc / unregister_hc
```pascal
procedure register_hc(hc: PUSBHCDriver);
procedure unregister_hc(hc: PUSBHCDriver);
```
Adds or removes a host controller from the managed list. Called by UHCI/OHCI/EHCI/xHCI drivers after they have initialised their hardware.

### get_hc_count
```pascal
function get_hc_count: uint32;
```
Returns the number of currently registered host controllers.

### get_hc
```pascal
function get_hc(index: uint32): PUSBHCDriver;
```
Returns a pointer to the host controller at the given index.

### scan_ports
```pascal
procedure scan_ports;
```
Iterates all registered host controllers and triggers port scanning on each. For each populated port, calls `enumerate_device`.

### poll_all
```pascal
procedure poll_all;
```
Calls the poll callback on every registered host controller. Intended to be called periodically from the kernel main loop or a timer interrupt.

### enumerate_device
```pascal
procedure enumerate_device(hc: PUSBHCDriver; port: uint32; speed: uint32);
```
Runs the USB enumeration sequence for a newly detected device: assigns an address, reads descriptors, sets the active configuration, and calls `driver.mgr.register_device` with a USB bus identifier so that class drivers are loaded.

### usb_rescan_port
```pascal
procedure usb_rescan_port(hc: PUSBHCDriver; port: uint32);
```
Re-enumerates a single port, used for hotplug events.

### usb_remove_device
```pascal
procedure usb_remove_device(device: PUSBDevice);
```
Tears down a device: cancels pending transfers, notifies class drivers via completion hooks, and frees device memory.

### register_completion_hook / fire_completion_hooks
```pascal
procedure register_completion_hook(hook: TUSBCompletionHook);
procedure fire_completion_hooks(transfer: PUSBTransfer);
```
Registers a callback to be invoked whenever a transfer completes. `fire_completion_hooks` iterates all registered hooks and calls each with the completed transfer.

### usb_control_msg
```pascal
function usb_control_msg(device: PUSBDevice; setup: TUSBSetupPacket; data: pointer; length: uint32): TUSBTransferStatus;
```
Executes a synchronous USB control transfer using the provided setup packet.

### usb_get_descriptor
```pascal
function usb_get_descriptor(device: PUSBDevice; desc_type, desc_index: uint8; buf: pointer; length: uint16): TUSBTransferStatus;
```
Convenience wrapper around `usb_control_msg` for standard GET_DESCRIPTOR requests.

### usb_set_address
```pascal
function usb_set_address(device: PUSBDevice; address: uint8): TUSBTransferStatus;
```
Issues a SET_ADDRESS control request to assign the device its bus address.

### usb_set_configuration
```pascal
function usb_set_configuration(device: PUSBDevice; config: uint8): TUSBTransferStatus;
```
Issues a SET_CONFIGURATION control request to activate a configuration.

### usb_interrupt_transfer
```pascal
function usb_interrupt_transfer(device: PUSBDevice; endpoint: PUSBEndpoint; data: pointer; length: uint32): PUSBTransfer;
```
Queues an asynchronous interrupt IN transfer. Returns a transfer handle whose status can be polled.

### usb_bulk_transfer
```pascal
function usb_bulk_transfer(device: PUSBDevice; endpoint: PUSBEndpoint; data: pointer; length: uint32): PUSBTransfer;
```
Queues an asynchronous bulk transfer.

### usb_bulk_transfer_wait
```pascal
function usb_bulk_transfer_wait(device: PUSBDevice; endpoint: PUSBEndpoint; data: pointer; length: uint32): TUSBTransferStatus;
```
Performs a synchronous bulk transfer, blocking until completion.

### usb_clear_halt
```pascal
function usb_clear_halt(device: PUSBDevice; endpoint: PUSBEndpoint): TUSBTransferStatus;
```
Issues a CLEAR_FEATURE(ENDPOINT_HALT) request to clear a stalled endpoint.

### usb_find_interface / usb_find_interface_n
```pascal
function usb_find_interface(device: PUSBDevice; class_code, subclass, protocol: uint8): PUSBInterfaceDescriptor;
function usb_find_interface_n(device: PUSBDevice; class_code, subclass, protocol: uint8; n: uint8): PUSBInterfaceDescriptor;
```
Searches the device's configuration descriptor for an interface matching the given class, subclass, and protocol. `_n` returns the nth match.

### usb_count_endpoints / usb_find_endpoint
```pascal
function usb_count_endpoints(iface: PUSBInterfaceDescriptor): uint8;
function usb_find_endpoint(iface: PUSBInterfaceDescriptor; direction: TUSBDirection; transfer_type: TUSBPipeType): PUSBEndpointDescriptor;
```
Counts endpoints on an interface or finds the first endpoint matching a direction and transfer type.

## Notes

- The enumeration pipeline assigns device addresses starting from 1 and increments for each newly attached device.
- Class driver loading is performed by calling `driver.mgr.register_device` with `bus = biUSB` and identifier fields set from the interface descriptor (class, subclass, protocol).
- `poll_all` must be called regularly; it is the mechanism by which interrupt transfer completions are detected for host controllers that do not use hardware interrupts.
