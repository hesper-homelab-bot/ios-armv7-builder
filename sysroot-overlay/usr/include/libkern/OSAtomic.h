#ifndef _LIBKERN_OSATOMIC_H_
#define _LIBKERN_OSATOMIC_H_

/*
 * <libkern/OSAtomic.h> for the iOS armv7 cross build.
 *
 * V8 includes this header from src/base/platform/platform-darwin.cc but
 * (checked across the whole tree, 2026-11-07) uses none of its symbols --
 * its atomics go through <atomic> and its own barriers.  The header is
 * therefore provided as a compatibility shell rather than a
 * transcription of Apple's.
 *
 * If something ever does need the real thing, note that the whole
 * OSSpinLock/OSAtomic family is deprecated and, for the barriers, the
 * modern equivalent on Darwin is
 *     __asm__ __volatile__("" ::: "memory")   (compiler barrier)
 *     sys_icache_invalidate()                  (instruction cache)
 * both of which are already reachable through this sysroot.
 */

#include <stdint.h>
#include <sys/cdefs.h>

__BEGIN_DECLS

/* Compiler barrier; the only OSAtomic entry point that is ever worth
 * spelling out, and it is one instruction of semantics. */
#define OSMemoryBarrier()	__asm__ __volatile__("" ::: "memory")

__END_DECLS

#endif
