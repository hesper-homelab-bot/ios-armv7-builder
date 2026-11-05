/*
 * xlocale.h -- clean-room compatibility stub.
 *
 * Apple removed the standalone <xlocale.h> header years ago; its contents
 * (locale_t, uselocale, newlocale, duplocale, freelocale and the _l()
 * variants) moved into <locale.h>, and MB_CUR_MAX_L became an alias for
 * MB_CUR_MAX.  iOS 10.3 has no <xlocale.h> on disk at all.
 *
 * gnulib still assumes the old layout.  lib/localcharset.c defines DARWIN7
 * whenever __APPLE__ && __MACH__ && HAVE_LANGINFO_CODESET, and then does
 *
 *     #if defined DARWIN7
 *     # include <xlocale.h>
 *     #endif
 *     ...
 *     MB_CUR_MAX_L (uselocale (NULL))
 *
 * which dies with "fatal error: 'xlocale.h' file not found" on the musl
 * derived sysroot.  This stub gives it the two things it actually needs.
 *
 * No Apple header is copied: the declarations below come from musl's own
 * <locale.h> and <stdlib.h>, which this file simply includes.
 */
#ifndef _IOS_XLOCALE_H_STUB
#define _IOS_XLOCALE_H_STUB

#include <locale.h>   /* locale_t, uselocale(), newlocale(), duplocale() */
#include <stdlib.h>   /* MB_CUR_MAX                                   */

/* Apple's <xlocale.h> spelled the current-locale MB_CUR_MAX this way. */
#ifndef MB_CUR_MAX_L
#define MB_CUR_MAX_L(loc) MB_CUR_MAX
#endif

#endif /* _IOS_XLOCALE_H_STUB */
