#ifndef _UUID_UUID_H
#define _UUID_UUID_H

/*
 * Minimal uuid/uuid.h for the iOS armv7 cross build.  sys/proc_info.h
 * only needs the uuid_t type (embedded byte arrays); no uuid_* functions
 * are used by anything compiled against this sysroot so far.
 *
 * Type verified against the macOS SDK definition.
 */

typedef unsigned char uuid_t[16];

#endif
