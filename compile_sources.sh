#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling FPC Sources..."
echo " "
fpc -Aelf -gw -g -gl -n -vlewn -O3 -OpPENTIUM3 -Si -Sc -Sg -Xd -CX -XXs -CfSSE -CfSSE2 -Rintel -Pi386 -Tlinux -FElib/ -Fusrc/* -Fusrc/driver/* -Fusrc/driver/net/* src/kernel.pas