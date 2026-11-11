#ifndef _MACH_O_GETSECT_H_
#define _MACH_O_GETSECT_H_

/*
 * Minimal <mach-o/getsect.h> for the iOS armv7 cross build: section
 * lookup on a loaded image, which V8 uses to find its own __TEXT,__text.
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-07): walking the dyld
 * image list with getsectiondata(header, "__TEXT", "__text", &size) found
 * a 150-byte __text in the probe binary itself.
 */

#include <stdint.h>
#include <mach-o/loader.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SEG_TEXT	"__TEXT"
#define SECT_TEXT	"__text"
#define SEG_DATA	"__DATA"
#define SECT_DATA	"__data"
#define SEG_LINKEDIT	"__LINKEDIT"

/*
 * On Darwin these are NOT plain functions in the public spelling: the SDK
 * header defines `getsectiondata`/`getsegmentdata` as macros that pick the
 * 32- or 64-bit symbol from the pointer type of the first argument
 * (_getsectiondata for mach_header, _getsectiondata_64 for
 * mach_header_64).  V8 relies on exactly that: it calls getsectiondata()
 * with a mach_header* on 32-bit hosts and with a mach_header_64* on 64-bit
 * ones, under one name.  Reproducing the macro is therefore required, not
 * cosmetic.
 */
uint8_t *	getsectiondata(const struct mach_header *mhp, const char *segname,
		    const char *sectname, unsigned long *size);
uint8_t *	getsectiondata_64(const struct mach_header_64 *mhp, const char *segname,
		    const char *sectname, unsigned long *size);
uint8_t *	getsegmentdata(const struct mach_header *mhp, const char *segname,
		    unsigned long *size);
uint8_t *	getsegmentdata_64(const struct mach_header_64 *mhp, const char *segname,
		    unsigned long *size);

#define getsectiondata(mhp, segname, sectname, size) \
	((mhp)->magic == MH_MAGIC_64 \
	     ? getsectiondata_64((const struct mach_header_64 *)(mhp), segname, \
				 sectname, size) \
	     : getsectiondata((const struct mach_header *)(mhp), segname, \
			      sectname, size))
#define getsegmentdata(mhp, segname, size) \
	((mhp)->magic == MH_MAGIC_64 \
	     ? getsegmentdata_64((const struct mach_header_64 *)(mhp), segname, size) \
	     : getsegmentdata((const struct mach_header *)(mhp), segname, size))

/*
 * Deprecated 3-argument spellings.  Note these are a DIFFERENT identifier
 * from getsectiondata above -- no "ion" -- and they take no header pointer:
 * they walk the process's loaded images on their own.  The 4-value variant
 * additionally names a framework (dylib) by short name.
 *
 * Both are used by postject (Node's Single-Executable-Application support,
 * deps/postject/postject-api.h), which is why they are here rather than in
 * a "nobody calls this" file.
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-08):
 *   getsectdata("__TEXT", "__text", &size)             -> 0xbf04, 84 bytes
 *   getsectdatafromFramework("CoreFoundation", ...)    -> NULL (not linked)
 *   getsectdatafromFramework("", ...)                  -> NULL
 * The first is what gives back this binary's own __TEXT,__text; the others
 * return NULL for frameworks that are not loaded, which is correct
 * behaviour, and the function does not crash on such input.  (It does
 * crash on a NULL framework pointer, but postject only takes that branch
 * when the name is non-NULL.)
 */
char *	getsectdata(const char *segname, const char *sectname,
	    unsigned long *size);
char *	getsectdatafromFramework(const char *frameworkName,
	    const char *segname, const char *sectname, unsigned long *size);

#ifdef __cplusplus
}
#endif

#endif
