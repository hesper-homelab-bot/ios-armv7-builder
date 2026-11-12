/*
 * machine/endian.h -- clean-room compatibility stub.
 *
 * Apple ships <machine/endian.h> (it is the historical home of the
 * __BYTE_ORDER / __LITTLE_ENDIAN / __BIG_ENDIAN macros, and <sys/endian.h>
 * merely includes it), but this device's /usr/include has *neither* file,
 * and the hand-made musl-derived sysroot only ever had the musl-style
 * top-level <endian.h>.  Autoconf-visible code that tests for the BSD
 * spelling therefore fails to compile:
 *
 *   protobuf 3.20.3 src/google/protobuf/stubs/port.h:61 does
 *       #ifdef __APPLE__
 *       #include <machine/endian.h>  // __BYTE_ORDER
 *   and dies with "fatal error: 'machine/endian.h' file not found".
 *
 * Nothing at runtime needs this header -- __BYTE_ORDER is a pure
 * preprocessor fact -- so forwarding to the sysroot's existing <endian.h>
 * is sufficient and no Apple file is copied.
 */
#ifndef _IOS_MACHINE_ENDIAN_H_STUB
#define _IOS_MACHINE_ENDIAN_H_STUB

#include <endian.h>

#endif /* _IOS_MACHINE_ENDIAN_H_STUB */
