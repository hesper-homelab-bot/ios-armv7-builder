#ifndef _STDLIB_H
#define _STDLIB_H

/*
 * Note on the include order below.  musl's <stdlib.h> opens extern "C"
 * *before* its #include lines; that is harmless when the C library is the
 * only thing in the include path, but here <features.h>,
 * <bits/alltypes.h>, <alloca.h> and <stdint.h> can reach libc++ headers
 * through #include_next.  Any template seen inside an extern "C" region is
 * a hard error, so libc++ dies with
 *     templates must have C++ linkage
 * on <new>/<optional>/__memory/addressof.h.
 *
 * Therefore: includes first, then ONE extern "C" block covering all the
 * declarations.  This matches what the SDK headers do too.
 */

#include <features.h>
/*
 * <stdint.h> is included here, before any extern "C" block opens, for the
 * uint32_t that the arc4random declarations below need.  Putting it inside
 * the block is what dragged libc++ headers into a C-linkage region and
 * broke <new>/<cstdlib> with "templates must have C++ linkage".
 */
#include <stdint.h>

#if __cplusplus >= 201103L
#define NULL nullptr
#elif defined(__cplusplus)
#define NULL 0L
#else
#define NULL ((void*)0)
#endif

#define __NEED_size_t
#define __NEED_wchar_t

#include <bits/alltypes.h>

#ifdef __cplusplus
extern "C" {
#endif

int atoi (const char *);
long atol (const char *);
long long atoll (const char *);
double atof (const char *);

float strtof (const char *__restrict, char **__restrict);
double strtod (const char *__restrict, char **__restrict);
long double strtold (const char *__restrict, char **__restrict);

long strtol (const char *__restrict, char **__restrict, int);
unsigned long strtoul (const char *__restrict, char **__restrict, int);
long long strtoll (const char *__restrict, char **__restrict, int);
unsigned long long strtoull (const char *__restrict, char **__restrict, int);

int rand (void);
void srand (unsigned);

void *malloc (size_t);
void *calloc (size_t, size_t);
void *realloc (void *, size_t);
void free (void *);
void *aligned_alloc(size_t, size_t);

_Noreturn void abort (void);
int atexit (void (*) (void));
_Noreturn void exit (int);
_Noreturn void _Exit (int);
int at_quick_exit (void (*) (void));
_Noreturn void quick_exit (int);

char *getenv (const char *);

int system (const char *);

void *bsearch (const void *, const void *, size_t, size_t, int (*)(const void *, const void *));
void qsort (void *, size_t, size_t, int (*)(const void *, const void *));

int abs (int);
long labs (long);
long long llabs (long long);

typedef struct { int quot, rem; } div_t;
typedef struct { long quot, rem; } ldiv_t;
typedef struct { long long quot, rem; } lldiv_t;

div_t div (int, int);
ldiv_t ldiv (long, long);
lldiv_t lldiv (long long, long long);

int mblen (const char *, size_t);
int mbtowc (wchar_t *__restrict, const char *__restrict, size_t);
int wctomb (char *, wchar_t);
size_t mbstowcs (wchar_t *__restrict, const char *__restrict, size_t);
size_t wcstombs (char *__restrict, const wchar_t *__restrict, size_t);

#define EXIT_FAILURE 1
#define EXIT_SUCCESS 0

/* MB_CUR_MAX: musl routes this through a function, __ctype_get_mb_cur_max(),
   which is a glibc internal.  Darwin has no such function -- it exports a
   plain int variable instead:
   
       extern int __mb_cur_max;         -- measured on the device: 1
   
   Verified on an iPad 4 (iOS 10.3.3) by resolving both names: the function
   form aborts with
       dyld: lazy symbol binding failed: Symbol not found:
             ___ctype_get_mb_cur_max
   while reading __mb_cur_max as data returns 1 and keeps working after
   setlocale().  Calling the data symbol as a function instead bus-errors,
   which is how the difference was pinned down.
   
   Any program calling MB_CUR_MAX therefore died at first use, not at link
   time -- the link test cannot see it because the kit links with
   -undefined dynamic_lookup. */
extern int __mb_cur_max;
#define MB_CUR_MAX (__mb_cur_max)

#define RAND_MAX (0x7fffffff)


#if defined(_POSIX_SOURCE) || defined(_POSIX_C_SOURCE) \
 || defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) \
 || defined(_BSD_SOURCE)

#define WNOHANG    1
#define WUNTRACED  2

#define WEXITSTATUS(s) (((s) & 0xff00) >> 8)
#define WTERMSIG(s) ((s) & 0x7f)
#define WSTOPSIG(s) WEXITSTATUS(s)
#define WIFEXITED(s) (!WTERMSIG(s))
#define WIFSTOPPED(s) ((short)((((s)&0xffff)*0x10001U)>>8) > 0x7f00)
#define WIFSIGNALED(s) (((s)&0xffff)-1U < 0xffu)

int posix_memalign (void **, size_t, size_t);
int setenv (const char *, const char *, int);
int unsetenv (const char *);
int mkstemp (char *);
int mkostemp (char *, int);
char *mkdtemp (char *);
int getsubopt (char **, char *const *, char **);
int rand_r (unsigned *);

#endif


#if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) \
 || defined(_BSD_SOURCE)
char *realpath (const char *__restrict, char *__restrict);
long int random (void);
void srandom (unsigned int);
char *initstate (unsigned int, char *, size_t);
char *setstate (char *);
int putenv (char *);
int posix_openpt (int);
int grantpt (int);
int unlockpt (int);
char *ptsname (int);
char *l64a (long);
long a64l (const char *);
void setkey (const char *);
double drand48 (void);
double erand48 (unsigned short [3]);
long int lrand48 (void);
long int nrand48 (unsigned short [3]);
long mrand48 (void);
long jrand48 (unsigned short [3]);
void srand48 (long);
unsigned short *seed48 (unsigned short [3]);
void lcong48 (unsigned short [7]);
#endif

#if defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
#include <alloca.h>
char *mktemp (char *);
int mkstemps (char *, int);
int mkostemps (char *, int, int);
void *valloc (size_t);
void *memalign(size_t, size_t);
int getloadavg(double *, int);
int clearenv(void);
#define WCOREDUMP(s) ((s) & 0x80)
#define WIFCONTINUED(s) ((s) == 0xffff)
void *reallocarray (void *, size_t, size_t);
void qsort_r (void *, size_t, size_t, int (*)(const void *, const void *, void *), void *);
#endif

#ifdef _GNU_SOURCE
int ptsname_r(int, char *, size_t);
char *ecvt(double, int, int *, int *);
char *fcvt(double, int, int *, int *);
char *gcvt(double, int, char *);
char *secure_getenv(const char *);
struct __locale_struct;
float strtof_l(const char *__restrict, char **__restrict, struct __locale_struct *);
double strtod_l(const char *__restrict, char **__restrict, struct __locale_struct *);
#endif /* _GNU_SOURCE */

/* ---- Darwin additions ----------------------------------------------
 * getprogname/setprogname and srandomdev (random(3) already declared by
 * musl above); srandomdev seeds from /dev/urandom and was verified on
 * device 2026-11-08.
 *
 * arc4random(): iOS's libSystem has always exported these but musl never
 * declared them, so OpenSSH, Dropbear and libedit compiled them as
 * implicit int-returning calls.  Device-verified 2026-11-08.
 */
const char *getprogname(void);
void setprogname(const char *);
void srandomdev(void);

uint32_t arc4random(void);
void arc4random_buf(void *, size_t);
uint32_t arc4random_uniform(uint32_t);
void arc4random_stir(void);
void arc4random_addrandom(void *, int);

#ifdef __cplusplus
}
#endif

#endif /* _STDLIB_H */
