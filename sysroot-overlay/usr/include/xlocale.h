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

/*
 * locale_t must exist no matter how we got here.
 *
 * musl's <locale.h> only asks bits/alltypes.h for locale_t when one of
 * _POSIX_SOURCE / _POSIX_C_SOURCE / _XOPEN_SOURCE / _GNU_SOURCE /
 * _BSD_SOURCE is defined.  libc++ (LLVM 15 headers) reaches this file from
 * <ios> -> <__locale> line 37 for the __APPLE__ case, i.e. *before* any of
 * those feature macros is in play, so the type is not defined yet and every
 * prototype below fails with "unknown type name 'locale_t'".  (Observed
 * building protobuf 3.20.3: the very first C++ TU that pulls in <string>
 * dies.)  Declaring it here is not a workaround -- Apple's own <xlocale.h>
 * always provided locale_t -- it just makes this stub independent of
 * include order.  <bits/alltypes.h> guards with __DEFINED_locale_t, so a
 * later <locale.h> re-definition is harmless.
 */
#ifndef __DEFINED_locale_t
#define __NEED_locale_t
#include <bits/alltypes.h>
#endif

/* Apple's <xlocale.h> spelled the current-locale MB_CUR_MAX this way. */
#ifndef MB_CUR_MAX_L
#define MB_CUR_MAX_L(loc) MB_CUR_MAX
#endif

/*
 * What libc++ (LLVM 6.0.1) expects <xlocale.h> to provide on Darwin:
 * __uint32_t and the _CTYPE_* classification masks used to build the
 * classic-locale table in <__locale>.  Values are copied from Apple's
 * Libc-1244.30.3 (the iOS 10.3-era Libc) include/ctype.h, where they sit
 * behind _DARWIN_C_SOURCE.  Order matters -- do not renumber.
 */
#ifndef __uint32_t
typedef unsigned int __uint32_t;
#endif

#ifndef _CTYPE_A
#define _CTYPE_A	0x00000100L		/* Alpha */
#define _CTYPE_C	0x00000200L		/* Control */
#define _CTYPE_D	0x00000400L		/* Digit */
#define _CTYPE_G	0x00000800L		/* Graph */
#define _CTYPE_L	0x00001000L		/* Lower */
#define _CTYPE_P	0x00002000L		/* Punct */
#define _CTYPE_S	0x00004000L		/* Space */
#define _CTYPE_U	0x00008000L		/* Upper */
#define _CTYPE_X	0x00010000L		/* X digit */
#define _CTYPE_B	0x00020000L		/* Blank */
#define _CTYPE_R	0x00040000L		/* Print */
#define _CTYPE_I	0x00080000L		/* Ideogram */
#define _CTYPE_T	0x00100000L		/* Special */
#define _CTYPE_Q	0x00200000L		/* Phonogram */
#endif

/*
 * The _l() locale functions libc++ (LLVM 6.0.1) calls via
 * __bsd_locale_defaults.h, plus the strtod family from <locale> numeric
 * parsing.  All 20 were verified present in the device's libSystem at
 * runtime: a probe took the address of each, linked with -undefined
 * dynamic_lookup and ran (rc=0, none null) -- 2026-11-07, iPad 4 iOS 10.3.3.
 */
#include <locale.h>   /* locale_t, struct lconv */
#include <wchar.h>    /* wchar_t, wint_t, mbstate_t, size_t */

long	strtol_l(const char *, char **, int, locale_t);
unsigned long strtoul_l(const char *, char **, int, locale_t);
long long	strtoll_l(const char *, char **, int, locale_t);
unsigned long long strtoull_l(const char *, char **, int, locale_t);
double	strtod_l(const char *, char **, locale_t);
long double strtold_l(const char *, char **, locale_t);
float	strtof_l(const char *, char **, locale_t);

wint_t	 btowc_l(int, locale_t);
int	 wctob_l(wint_t, locale_t);
size_t	 wcsnrtombs_l(char * __restrict, const wchar_t ** __restrict, size_t, size_t, mbstate_t * __restrict, locale_t);
size_t	 wcrtomb_l(char * __restrict, wchar_t, mbstate_t * __restrict, locale_t);
size_t	 mbsnrtowcs_l(wchar_t * __restrict, const char ** __restrict, size_t, size_t, mbstate_t * __restrict, locale_t);
size_t	 mbrtowc_l(wchar_t * __restrict, const char * __restrict, size_t, mbstate_t * __restrict, locale_t);
int	 mbtowc_l(wchar_t * __restrict, const char * __restrict, size_t, locale_t);
size_t	 mbrlen_l(const char * __restrict, size_t, mbstate_t * __restrict, locale_t);
struct lconv *	localeconv_l(locale_t);
size_t	 mbsrtowcs_l(wchar_t * __restrict, const char ** __restrict, size_t, mbstate_t * __restrict, locale_t);
int	 snprintf_l(char * __restrict, size_t, locale_t, const char * __restrict, ...);
int	 asprintf_l(char ** __restrict, locale_t, const char * __restrict, ...);
int	 sscanf_l(const char * __restrict, locale_t, const char * __restrict, ...);

#endif /* _IOS_XLOCALE_H_STUB */
