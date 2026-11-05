/*
 * Minimal libkern/OSByteOrder.h for the cross sysroot.
 * Target is little-endian armv7, so the swaps map to builtins directly
 * (no dependency on libSystem's _OSSwap* symbols).
 */
#ifndef _LIBKERN_OSBYTEORDER_H
#define _LIBKERN_OSBYTEORDER_H

#include <stdint.h>

#define OSSwapConstInt16(x) ((uint16_t)(x))
#define OSSwapConstInt32(x) ((uint32_t)(x))
#define OSSwapConstInt64(x) ((uint64_t)(x))

static inline uint16_t OSSwapInt16(uint16_t x) { return __builtin_bswap16(x); }
static inline uint32_t OSSwapInt32(uint32_t x) { return __builtin_bswap32(x); }
static inline uint64_t OSSwapInt64(uint64_t x) { return __builtin_bswap64(x); }

#define OSSwapHostToLittleInt16(x) ((uint16_t)(x))
#define OSSwapHostToLittleInt32(x) ((uint32_t)(x))
#define OSSwapHostToLittleInt64(x) ((uint64_t)(x))
#define OSSwapLittleToHostInt16(x) ((uint16_t)(x))
#define OSSwapLittleToHostInt32(x) ((uint32_t)(x))
#define OSSwapLittleToHostInt64(x) ((uint64_t)(x))
#define OSSwapHostToBigInt16(x)    __builtin_bswap16((uint16_t)(x))
#define OSSwapHostToBigInt32(x)    __builtin_bswap32((uint32_t)(x))
#define OSSwapHostToBigInt64(x)    __builtin_bswap64((uint64_t)(x))
#define OSSwapBigToHostInt16(x)    __builtin_bswap16((uint16_t)(x))
#define OSSwapBigToHostInt32(x)    __builtin_bswap32((uint32_t)(x))
#define OSSwapBigToHostInt64(x)    __builtin_bswap64((uint64_t)(x))

#define HostToBigInt16(x)    OSSwapHostToBigInt16(x)
#define HostToBigInt32(x)    OSSwapHostToBigInt32(x)
#define HostToBigInt64(x)    OSSwapHostToBigInt64(x)
#define BigToHostInt16(x)    OSSwapBigToHostInt16(x)
#define BigToHostInt32(x)    OSSwapBigToHostInt32(x)
#define BigToHostInt64(x)    OSSwapBigToHostInt64(x)
#define HostToLittleInt16(x) OSSwapHostToLittleInt16(x)
#define HostToLittleInt32(x) OSSwapHostToLittleInt32(x)
#define HostToLittleInt64(x) OSSwapHostToLittleInt64(x)
#define LittleToHostInt16(x) OSSwapLittleToHostInt16(x)
#define LittleToHostInt32(x) OSSwapLittleToHostInt32(x)
#define LittleToHostInt64(x) OSSwapLittleToHostInt64(x)

#endif
