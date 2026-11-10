#!/usr/bin/env bash
set -euo pipefail

BIN=${1:?usage: verify-android-neon.sh <engine> [llvm-readelf] [llvm-objdump]}
READELF=${2:-readelf}
OBJDUMP=${3:-objdump}

[[ -f "$BIN" ]] || { echo "FAIL: missing engine: $BIN" >&2; exit 1; }

HEADER=$("$READELF" -h "$BIN")
grep -q 'Class:.*ELF64' <<<"$HEADER" || { echo "FAIL: expected ELF64" >&2; exit 1; }
grep -q 'Machine:.*AArch64' <<<"$HEADER" || { echo "FAIL: expected AArch64 binary" >&2; exit 1; }
echo "PASS: ELF64 AArch64 executable."

PROGRAM_HEADERS=$("$READELF" -l "$BIN")
grep -q '/system/bin/linker64' <<<"$PROGRAM_HEADERS" || { echo "FAIL: not an Android dynamic executable (linker64 missing)" >&2; exit 1; }
echo "PASS: Android linker64 target."

DYNAMIC=$("$READELF" -d "$BIN" 2>/dev/null || true)
if grep -q 'libc++_shared.so' <<<"$DYNAMIC"; then
    echo "FAIL: binary depends on libc++_shared.so" >&2
    exit 1
fi
echo "PASS: no libc++_shared.so dependency."

DISASM=$(mktemp)
trap 'rm -f "$DISASM"' EXIT
"$OBJDUMP" -d "$BIN" > "$DISASM"
if ! grep -Eq '\b(add|sub|smin|smax|mul|smull|saddp|smax|smin)\s+v[0-9]+\.[0-9]+[bhsd]' "$DISASM"; then
    echo "FAIL: no expected Advanced SIMD vector instructions found" >&2
    exit 1
fi
echo "PASS: AArch64 Advanced SIMD instructions found in engine disassembly."

if grep -Eq '\bsdot\b|\budot\b' "$DISASM"; then
    echo "INFO: dot-product instructions are present in this binary."
else
    echo "INFO: no SDOT/UDOT in active engine code; current Onslaught NNUE uses int16 weights and squared activations, so this build is NEON, not a DotProd-specialized engine."
fi
