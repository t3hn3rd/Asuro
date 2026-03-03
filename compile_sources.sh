#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
fpc -Aelf -gw -g -gl -n -v0ew -O3 -OpPENTIUM3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ -Fusrc/* -Fusrc/include/* -Fusrc/driver/* -Fusrc/driver/net/* -Fusrc/driver/bus/* -Fusrc/driver/bus/usb/* -Fusrc/driver/hid/* src/kernel.pas