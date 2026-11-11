#ifndef _MACH_O_LOADER_H_
#define _MACH_O_LOADER_H_

/*
 * Minimal <mach-o/loader.h> for the iOS armv7 cross build: just the
 * Mach-O file header, which dyld's image APIs return.  Field layout is
 * fixed by the Mach-O ABI (32-bit variant here: magic/cputype/cpusubtype
 * /filetype/ncmds/sizeofcmds/flags).
 */

#include <stdint.h>

struct mach_header {
	uint32_t	magic;
	int32_t		cputype;
	int32_t		cpusubtype;
	uint32_t	filetype;
	uint32_t	ncmds;
	uint32_t	sizeofcmds;
	uint32_t	flags;
};

struct mach_header_64 {
	uint32_t	magic;
	int32_t		cputype;
	int32_t		cpusubtype;
	uint32_t	filetype;
	uint32_t	ncmds;
	uint32_t	sizeofcmds;
	uint32_t	flags;
	uint32_t	reserved;
};

#define MH_MAGIC_64	0xfeedfacf
#define MH_MAGIC	0xfeedface
#define MH_EXECUTE	0x2
#define MH_DYLIB	0x6
#define MH_BUNDLE	0x8

#endif
