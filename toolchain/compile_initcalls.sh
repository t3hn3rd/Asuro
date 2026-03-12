#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Generating INITFINAL table..."
echo " "

# ---------------------------------------------------------------------------
# compile_initcalls.sh
#
# Scans every compiled FPC object file (lib/*.o) for INIT$_$* symbols.
# FPC emits these for every unit that has an 'initialization' section.
# We generate a small C source file that builds an INITFINAL table
# (matching the TInitFinalTable layout in system.pas) and compile it
# to lib/initcalls.o.  FPC_INITIALIZEUNITS in system.pas walks this
# table at boot to call each unit's initialization code.
# ---------------------------------------------------------------------------

INIT_SYMBOLS=()

for obj in lib/*.o; do
    # Skip non-FPC objects that will never contain Pascal init sections
    case "$(basename "$obj")" in
        stub.o|splash_tga.o|initcalls.o) continue ;;
    esac

    # nm --defined-only: only symbols defined in this object (not extern refs)
    # grep ' T INIT\$_\$': global text symbols matching FPC's naming convention
    # awk '{print $3}': extract the symbol name (third field)
    while IFS= read -r sym; do
        [ -n "$sym" ] && INIT_SYMBOLS+=("$sym")
    done < <(nm --defined-only "$obj" 2>/dev/null | grep ' T INIT\$_\$' | awk '{print $3}')
done

COUNT=${#INIT_SYMBOLS[@]}
echo "Found $COUNT unit initialization section(s)."

CFILE="/tmp/initcalls.c"

# ---- Generate the C source file ----

cat > "$CFILE" <<'HEADER'
/* initcalls.c — Auto-generated INITFINAL dispatch table.
 * DO NOT EDIT — regenerated on every build by compile_initcalls.sh.
 *
 * Provides the INITFINAL symbol expected by FPC_INITIALIZEUNITS in
 * system.pas.  Each unit with a Pascal 'initialization' section gets
 * an entry so its init code runs during system.init(). */

typedef void (*initproc_t)(void);

typedef struct {
    initproc_t init;
    initproc_t fini;
} __attribute__((packed)) TInitFinalRec;

HEADER

# Emit extern declarations — use asm("INIT$_$UNIT.NAME") labels so
# GCC references the exact FPC-generated symbol names (which contain
# $ and . characters that are valid in ELF but not in C identifiers).
IDX=0
for sym in "${INIT_SYMBOLS[@]}"; do
    echo "  -> $sym"
    printf 'extern void initcall_%d(void) asm("%s");\n' "$IDX" "$sym" >> "$CFILE"
    IDX=$((IDX + 1))
done

# Emit the INITFINAL table struct
if [ "$COUNT" -eq 0 ]; then
    cat >> "$CFILE" <<'ZEROTABLE'

/* No initialization sections found — emit an empty table */
struct __attribute__((packed)) {
    int count;
} INITFINAL = { 0 };
ZEROTABLE
else
    printf '\nstruct __attribute__((packed)) {\n' >> "$CFILE"
    printf '    int count;\n' >> "$CFILE"
    printf '    TInitFinalRec procs[%d];\n' "$COUNT" >> "$CFILE"
    printf '} INITFINAL = {\n' >> "$CFILE"
    printf '    %d,\n' "$COUNT" >> "$CFILE"
    printf '    {\n' >> "$CFILE"

    for ((i=0; i<COUNT; i++)); do
        COMMA=","
        [ "$i" -eq $((COUNT - 1)) ] && COMMA=""
        printf '        { initcall_%d, (initproc_t)0 }%s\n' "$i" "$COMMA" >> "$CFILE"
    done

    printf '    }\n' >> "$CFILE"
    printf '};\n' >> "$CFILE"
fi

echo " "
echo "--- Generated C source ---"
cat "$CFILE"
echo "--- End of generated C source ---"
echo " "

# Compile to a 32-bit ELF object file
gcc -m32 -c -fno-pic -ffreestanding -o lib/initcalls.o "$CFILE"
echo "Compiled lib/initcalls.o"
