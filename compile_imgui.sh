#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Compiling ImGui (cimgui)..."
echo " "

IMGUI_DIR=/cimgui
IMGUI_SRC=$IMGUI_DIR/imgui
BRIDGE_SRC=src/driver/video/imgui

# Flags shared by all C/C++ compilation units:
#   -m32              -> i386 target
#   -ffreestanding    -> no implicit stdlib inclusion
#   -fno-builtin      -> don't inline memcpy/memset/etc. so our stubs are used
#   -O2               -> optimise for speed
#   -ffunction-sections -fdata-sections -> allow --gc-sections in linker
C_FLAGS="-m32 -ffreestanding -fno-builtin -O2 -ffunction-sections -fdata-sections"

# Extra flags for C++ translation units (cimgui/imgui sources):
#   -fno-exceptions         -> no stack-unwinding machinery
#   -fno-rtti               -> no typeinfo / dynamic_cast
#   -fno-use-cxa-atexit     -> don't emit __cxa_atexit calls for static dtors
#   -fno-threadsafe-statics -> no guard-variable emission for local statics
# NOTE: *not* -ffreestanding / -fno-builtin here — imgui includes <cmath> and
#       other hosted headers that refuse to compile in freestanding mode.
#       The object files are archived into a static lib and linked freestanding;
#       any hosted-stdlib calls (malloc/free/sin/cos/…) resolve to crtshim.c.
CPP_FLAGS="-m32 -O2 -ffunction-sections -fdata-sections -fno-exceptions -fno-rtti -fno-use-cxa-atexit -fno-threadsafe-statics -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -DNDEBUG -DIMGUI_ENABLE_STB_TRUETYPE"

INCLUDE="-I$IMGUI_DIR -I$IMGUI_SRC"

echo "Compiling C runtime shim..."
gcc $C_FLAGS $INCLUDE \
    -c $BRIDGE_SRC/crtshim.c \
    -o lib/imgui_crtshim.o || { echo "Failed: crtshim.c"; exit 1; }

echo "Compiling render bridge..."
# imgbridge is compiled as C++ so it sees cimgui.h function declarations
# (C++ mode is required; the .c extension is overridden with -x c++)
g++ $CPP_FLAGS $INCLUDE \
    -x c++ \
    -DCIMGUI_DEFINE_ENUMS_AND_STRUCTS \
    -c $BRIDGE_SRC/imgbridge.c \
    -o lib/imgui_bridge.o || { echo "Failed: imgbridge.c"; exit 1; }

echo "Compiling cimgui wrapper..."
g++ $CPP_FLAGS $INCLUDE \
    -c $IMGUI_DIR/cimgui.cpp \
    -o lib/imgui_cimgui.o || { echo "Failed: cimgui.cpp"; exit 1; }

echo "Compiling imgui core..."
g++ $CPP_FLAGS $INCLUDE \
    -c $IMGUI_SRC/imgui.cpp \
    -o lib/imgui_core.o || { echo "Failed: imgui.cpp"; exit 1; }

echo "Compiling imgui draw..."
g++ $CPP_FLAGS $INCLUDE \
    -c $IMGUI_SRC/imgui_draw.cpp \
    -o lib/imgui_draw.o || { echo "Failed: imgui_draw.cpp"; exit 1; }

echo "Compiling imgui tables..."
g++ $CPP_FLAGS $INCLUDE \
    -c $IMGUI_SRC/imgui_tables.cpp \
    -o lib/imgui_tables.o || { echo "Failed: imgui_tables.cpp"; exit 1; }

echo "Compiling imgui widgets..."
g++ $CPP_FLAGS $INCLUDE \
    -c $IMGUI_SRC/imgui_widgets.cpp \
    -o lib/imgui_widgets.o || { echo "Failed: imgui_widgets.cpp"; exit 1; }

echo "Compiling imgui demo..."
g++ $CPP_FLAGS $INCLUDE \
    -c $IMGUI_SRC/imgui_demo.cpp \
    -o lib/imgui_demo.o || { echo "Failed: imgui_demo.cpp"; exit 1; }

echo "Archiving cimgui.a..."
# NOTE: imgui_bridge.o and imgui_crtshim.o are NOT in the archive because
# compile_link.sh already picks them up individually via find lib/ -name "*.o".
# Including them here would cause duplicate symbol errors.
ar rcs lib/cimgui.a \
    lib/imgui_cimgui.o \
    lib/imgui_core.o \
    lib/imgui_draw.o \
    lib/imgui_tables.o \
    lib/imgui_widgets.o \
    lib/imgui_demo.o || { echo "Failed: ar"; exit 1; }

echo "ImGui compiled successfully."
exit 0
