#!/usr/bin/env bash
set -euo pipefail

CXX=${1:?usage: verify-android-dotprod-toolchain.sh <ndk-clang++> <llvm-objdump>}
OBJDUMP=${2:?usage: verify-android-dotprod-toolchain.sh <ndk-clang++> <llvm-objdump>}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/dotprod-probe.cpp" <<'CPP'
#include <arm_neon.h>
extern "C" int32x4_t onslaught_dotprod_probe(int32x4_t acc, int8x16_t lhs, int8x16_t rhs) {
    return vdotq_s32(acc, lhs, rhs);
}
CPP

MACROS=$(printf '\n' | "$CXX" -march=armv8.2-a+dotprod -dM -E -x c++ -)
grep -q '^#define __aarch64__' <<<"$MACROS" || { echo "FAIL: NDK compiler is not targeting AArch64" >&2; exit 1; }
grep -q '^#define __ARM_FEATURE_DOTPROD' <<<"$MACROS" || { echo "FAIL: compiler did not enable __ARM_FEATURE_DOTPROD" >&2; exit 1; }

"$CXX" -O3 -march=armv8.2-a+dotprod -c "$TMP_DIR/dotprod-probe.cpp" -o "$TMP_DIR/dotprod-probe.o"
"$OBJDUMP" -d "$TMP_DIR/dotprod-probe.o" > "$TMP_DIR/dotprod-probe.dis"
grep -Eq '\bsdot\b' "$TMP_DIR/dotprod-probe.dis" || { echo "FAIL: compiler probe did not emit SDOT" >&2; cat "$TMP_DIR/dotprod-probe.dis" >&2; exit 1; }
echo "PASS: NDK compiler supports ARMv8.2-A DotProd and emits SDOT."
echo "NOTE: This verifies toolchain capability only; Onslaught's current int16/squared-ReLU NNUE has no compatible fast SDOT inference kernel."
