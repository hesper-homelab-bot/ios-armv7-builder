#ifndef _OS_OBJECT_H_MINIMAL_
#define _OS_OBJECT_H_MINIMAL_

/*
 * Minimal <os/object.h> for the iOS armv7 cross build.  Apple's real header
 * is a large SDK file built on objc-independent-class attributes; V8's
 * darwin semaphore only needs the declaration context.  Deliberately tiny
 * and self-contained -- the Apple libdispatch copy references SDK-only
 * macros (OS_OBJECT_DECL_CLASS, swift availability spellings) that the
 * sysroot does not have.
 */

#include <sys/cdefs.h>

__BEGIN_DECLS

/* Placeholder so <dispatch/dispatch.h>'s os_object_t references resolve. */
typedef struct os_object_s *os_object_t;

__END_DECLS

#endif
