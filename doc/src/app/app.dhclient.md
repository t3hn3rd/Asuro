# app.dhclient

Terminal command for initiating DHCP network configuration.

## Overview

`app.dhclient` registers the `DHClient` shell command, which triggers a DHCP discovery process to automatically configure the system's network interface. It is a thin wrapper around the `driver.net.proto.dhcp.DHCPDiscover` function.

## Dependencies

- `io.stdio`
- `core.util`, `arch.x86.util`
- `core.strings`
- `debug.tracer`
- `driver.net.proto.dhcp`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `DHClient` command with `io.stdio`. Must be called once at startup from `app.mgr.init`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Calls `DHCPDiscover()` unconditionally. No parameters are required or examined. All output (lease acknowledgements, errors) is handled within the DHCP driver itself.

## Notes

This is a minimal command stub. Network interface selection and lease management are delegated entirely to `driver.net.proto.dhcp`.
