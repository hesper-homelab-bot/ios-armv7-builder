#ifndef _MACH_VM_STATISTICS_H_
#define _MACH_VM_STATISTICS_H_

/*
 * Minimal mach/vm_statistics.h for the iOS armv7 cross build: the
 * VM_MAKE_TAG spelling V8 uses to label its allocations, plus the handful
 * of VM_MEMORY_* tags.  Value from xnu-3789.70.16.
 */

#define VM_MAKE_TAG(tag)	((tag) << 24)

/* mach_vm_map/vm_map flags (xnu osfmk/mach/vm_statistics.h) */
#define VM_FLAGS_FIXED		0x0000
#define VM_FLAGS_ANYWHERE	0x0001
#define VM_FLAGS_PURGABLE	0x0002
#define VM_FLAGS_RANDOM_ADDR	0x0008
#define VM_FLAGS_NO_CACHE	0x0010
#define VM_FLAGS_RESILIENT_CODESIGN 0x0020
#define VM_FLAGS_RESILIENT_MEDIA 0x0040
#define VM_FLAGS_OVERWRITE	0x4000
#define VM_FLAGS_SUPERPAGE_MASK	0x70000

/*
 * Named-memory flags for mach_make_memory_entry_64.  Value taken from
 * cctools' foreign/mach/memory_object_types.h (the Apple open-source
 * spelling, matching XNU's private mman.h) -- NOT from memory: the
 * neighbouring MAP_MEM_ONLY is 0x10000 and PURGABLE 0x40000, so a
 * guessed 0x80000 would have collided with MAP_MEM_NAMED_REUSE.
 * V8 uses it only in CreateSharedMemoryHandleForTesting().
 */
#define MAP_MEM_NOOP		0
#define MAP_MEM_COPYBACK	1
#define MAP_MEM_IO		2
#define MAP_MEM_WTHRU		3
#define MAP_MEM_WCOMB		4
#define MAP_MEM_ONLY		0x10000
#define MAP_MEM_NAMED_CREATE	0x20000
#define MAP_MEM_PURGABLE	0x40000
#define MAP_MEM_NAMED_REUSE	0x80000

#endif
