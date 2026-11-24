# Storage benchmark commands

Both i386 and x86-64 provide these commands in the terminal.

## STORBENCH

Run `STORBENCH list` to identify the disk by ID and capacity. If the USB disk is disk 4, the following reads 4 MiB sequentially in 128 KiB requests at queue depth one.

```text
STORBENCH run 4 4 128 1 seq
```

Use `STORBENCH auto [disk] [MiB]` for the six-profile suite (default 32 MiB per profile), or `STORBENCH compare [disk] [MiB]` for twelve sequential cases. A manual run accepts the disk, MiB to read, KiB per request, queue depth, access pattern (`seq` or `random`) and optional starting LBA, in that order.

Reads bypass the Asuro filesystem cache. Host and drive caches can affect repeated reads. The benchmark reports hardware queue depth alongside the requested workload.

## STORPERF

Run `STORPERF` to check storage request handling on a memory-backed device. It exercises adjacent-request merging, command-size limits and failure callbacks. Results go to the serial log. For the boot-time USB read test, see the [native storage validation guide](../../../planning/x86_64.md#native-xhci-storage-validation).
