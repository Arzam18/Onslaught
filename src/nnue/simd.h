#ifndef SIMD_H
#define SIMD_H

// Defines a standard API for SIMD instructions.
// Implemented for AVX-512, AVX2, ARM NEON, and a scalar fallback.
// VEPI - vector of extended packed integer

#include <cstdint>

#if defined(__AVX512BW__)
#include <immintrin.h>
using vepi16 = __m512i;
using vepi32 = __m512i;
constexpr int VEC_I16 = 32;

inline vepi16 vecLoad(const int16_t* p) noexcept { return _mm512_load_si512(reinterpret_cast<const void*>(p)); }
inline void vecStore(int16_t* p, vepi16 v) noexcept { _mm512_store_si512(reinterpret_cast<void*>(p), v); }

inline vepi16 vecAdd(vepi16 a, vepi16 b) noexcept { return _mm512_add_epi16(a, b); }
inline vepi16 vecSub(vepi16 a, vepi16 b) noexcept { return _mm512_sub_epi16(a, b); }
inline vepi16 vecMin(vepi16 a, vepi16 b) noexcept { return _mm512_min_epi16(a, b); }
inline vepi16 vecMax(vepi16 a, vepi16 b) noexcept { return _mm512_max_epi16(a, b); }
inline vepi16 vecMullo(vepi16 a, vepi16 b) noexcept { return _mm512_mullo_epi16(a, b); }

inline vepi32 vecMAdd(vepi16 a, vepi16 b) noexcept { return _mm512_madd_epi16(a, b); }
inline vepi32 vecAdd32(vepi32 a, vepi32 b) noexcept { return _mm512_add_epi32(a, b); }

inline vepi16 vecSet1(int16_t x) noexcept { return _mm512_set1_epi16(x); }
inline vepi32 vecZero32() noexcept { return _mm512_setzero_si512(); }

inline int32_t vecReduce(vepi32 v) noexcept { return _mm512_reduce_add_epi32(v); }

#elif defined(__aarch64__) || defined(__ARM_NEON)
#include <arm_neon.h>
using vepi16 = int16x8_t;
using vepi32 = int32x4_t;
constexpr int VEC_I16 = 8;

// AArch64 Advanced SIMD (NEON): 8x int16 lanes and 4x int32 lanes.
inline vepi16 vecLoad(const int16_t* p) noexcept { return vld1q_s16(p); }
inline void vecStore(int16_t* p, vepi16 v) noexcept { vst1q_s16(p, v); }

inline vepi16 vecAdd(vepi16 a, vepi16 b) noexcept { return vaddq_s16(a, b); }
inline vepi16 vecSub(vepi16 a, vepi16 b) noexcept { return vsubq_s16(a, b); }
inline vepi16 vecMin(vepi16 a, vepi16 b) noexcept { return vminq_s16(a, b); }
inline vepi16 vecMax(vepi16 a, vepi16 b) noexcept { return vmaxq_s16(a, b); }
inline vepi16 vecMullo(vepi16 a, vepi16 b) noexcept { return vmulq_s16(a, b); }

// Match x86 pmaddwd semantics: multiply signed 16-bit lanes into 32-bit
// products, then sum adjacent products into four signed 32-bit lanes.
inline vepi32 vecMAdd(vepi16 a, vepi16 b) noexcept {
    const int32x4_t lo = vmull_s16(vget_low_s16(a), vget_low_s16(b));
    const int32x4_t hi = vmull_s16(vget_high_s16(a), vget_high_s16(b));
    return vpaddq_s32(lo, hi);
}
inline vepi32 vecAdd32(vepi32 a, vepi32 b) noexcept { return vaddq_s32(a, b); }

inline vepi16 vecSet1(int16_t x) noexcept { return vdupq_n_s16(x); }
inline vepi32 vecZero32() noexcept { return vdupq_n_s32(0); }

inline int32_t vecReduce(vepi32 v) noexcept {
#if defined(__aarch64__)
    return vaddvq_s32(v);
#else
    int32x2_t sum = vadd_s32(vget_low_s32(v), vget_high_s32(v));
    sum = vpadd_s32(sum, sum);
    return vget_lane_s32(sum, 0);
#endif
}

#elif defined(__AVX2__)
#include <immintrin.h>
using vepi16 = __m256i;
using vepi32 = __m256i;
constexpr int VEC_I16 = 16;
inline vepi16 vecLoad(const int16_t* p) noexcept { return _mm256_load_si256(reinterpret_cast<const __m256i*>(p)); }
inline void vecStore(int16_t* p, vepi16 v) noexcept { _mm256_store_si256(reinterpret_cast<__m256i*>(p), v); }

inline vepi16 vecAdd(vepi16 a, vepi16 b) noexcept { return _mm256_add_epi16(a, b); }
inline vepi16 vecSub(vepi16 a, vepi16 b) noexcept { return _mm256_sub_epi16(a, b); }
inline vepi16 vecMin(vepi16 a, vepi16 b) noexcept { return _mm256_min_epi16(a, b); }
inline vepi16 vecMax(vepi16 a, vepi16 b) noexcept { return _mm256_max_epi16(a, b); }
inline vepi16 vecMullo(vepi16 a, vepi16 b) noexcept { return _mm256_mullo_epi16(a, b); }

inline vepi32 vecMAdd(vepi16 a, vepi16 b) noexcept { return _mm256_madd_epi16(a, b); }
inline vepi32 vecAdd32(vepi32 a, vepi32 b) noexcept { return _mm256_add_epi32(a, b); }

inline vepi16 vecSet1(int16_t x) noexcept { return _mm256_set1_epi16(x); }
inline vepi32 vecZero32() noexcept { return _mm256_setzero_si256(); }

// Horizontal sum of 8x int32 -> scalar
inline int32_t vecReduce(vepi32 v) noexcept {
    __m128i lo = _mm256_castsi256_si128(v); // lanes 0..3
    __m128i hi = _mm256_extracti128_si256(v, 1); // lanes 4..7
    __m128i s = _mm_add_epi32(lo, hi); // 4x int32
    s = _mm_add_epi32(s, _mm_shuffle_epi32(s, _MM_SHUFFLE(1, 0, 3, 2)));
    s = _mm_add_epi32(s, _mm_shuffle_epi32(s, _MM_SHUFFLE(2, 3, 0, 1)));
    return _mm_cvtsi128_si32(s);
}
#else // No SIMD - scalar fallback
using vepi16 = int16_t;
using vepi32 = int32_t;
constexpr int VEC_I16 = 1;
inline vepi16 vecLoad(const int16_t* p) noexcept { return *p; }
inline void vecStore(int16_t* p, vepi16 v) noexcept { *p = v; }

inline vepi16 vecAdd(vepi16 a, vepi16 b) noexcept { return static_cast<vepi16>(a + b); }
inline vepi16 vecSub(vepi16 a, vepi16 b) noexcept { return static_cast<vepi16>(a - b); }
inline vepi16 vecMin(vepi16 a, vepi16 b) noexcept { return a < b ? a : b; }
inline vepi16 vecMax(vepi16 a, vepi16 b) noexcept { return a > b ? a : b; }
inline vepi16 vecMullo(vepi16 a, vepi16 b) noexcept { return static_cast<vepi16>(a * b); }

inline vepi32 vecMAdd(vepi16 a, vepi16 b) noexcept { return static_cast<vepi32>(a) * static_cast<vepi32>(b); }
inline vepi32 vecAdd32(vepi32 a, vepi32 b) noexcept { return a + b; }

inline vepi16 vecSet1(int16_t x) noexcept { return x; }
inline vepi32 vecZero32() noexcept { return 0; }

inline int32_t vecReduce(vepi32 v) noexcept { return v; }
#endif

#endif // SIMD_H
