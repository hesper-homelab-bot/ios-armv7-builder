#if defined(_POSIX_SOURCE) || defined(_POSIX_C_SOURCE) \
 || defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)

#if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
#define MINSIGSTKSZ 2048
#define SIGSTKSZ 8192
#endif

/* musl's Linux mcontext_t (a sigcontext by value, two spellings) is left out
 * on purpose: Darwin defines mcontext_t in <ucontext.h> as a POINTER to the
 * _STRUCT_MCONTEXT block, and the two cannot coexist -- a second typedef of
 * the same name is a hard "typedef redefinition with different type" error.
 * Nothing in this sysroot reads sigcontext. */

struct sigaltstack {
	void *ss_sp;
	int ss_flags;
	size_t ss_size;
};

/*
 * ucontext_t is deliberately NOT defined here.  musl declares it in
 * bits/signal.h with a Linux sigcontext inside; on Darwin ucontext_t belongs
 * to <ucontext.h> alone (the arm32 _STRUCT_MCONTEXT layout), and two
 * definitions of struct __ucontext are a hard error.
 */

#define SA_NOCLDSTOP  1
#define SA_NOCLDWAIT  2
#define SA_SIGINFO    4
#define SA_ONSTACK    0x08000000
#define SA_RESTART    0x10000000
#define SA_NODEFER    0x40000000
#define SA_RESETHAND  0x80000000
#define SA_RESTORER   0x04000000

#endif

#define SIGHUP    1
#define SIGINT    2
#define SIGQUIT   3
#define SIGILL    4
#define SIGTRAP   5
#define SIGABRT   6
#define SIGIOT    SIGABRT
#define SIGBUS    7
#define SIGFPE    8
#define SIGKILL   9
#define SIGUSR1   10
#define SIGSEGV   11
#define SIGUSR2   12
#define SIGPIPE   13
#define SIGALRM   14
#define SIGTERM   15
#define SIGSTKFLT 16
#define SIGCHLD   17
#define SIGCONT   18
#define SIGSTOP   19
#define SIGTSTP   20
#define SIGTTIN   21
#define SIGTTOU   22
#define SIGURG    23
#define SIGXCPU   24
#define SIGXFSZ   25
#define SIGVTALRM 26
#define SIGPROF   27
#define SIGWINCH  28
#define SIGIO     29
#define SIGPOLL   29
#define SIGPWR    30
#define SIGSYS    31
#define SIGUNUSED SIGSYS

#define _NSIG 65

/* ===== DARWIN_OVERRIDES: iOS/Darwin signal numbers and flags ===== */
#undef SIGHUP
#define SIGHUP 1
#undef SIGINT
#define SIGINT 2
#undef SIGQUIT
#define SIGQUIT 3
#undef SIGILL
#define SIGILL 4
#undef SIGTRAP
#define SIGTRAP 5
#undef SIGABRT
#define SIGABRT 6
#undef SIGEMT
#define SIGEMT 7
#undef SIGFPE
#define SIGFPE 8
#undef SIGKILL
#define SIGKILL 9
#undef SIGBUS
#define SIGBUS 10
#undef SIGSEGV
#define SIGSEGV 11
#undef SIGSYS
#define SIGSYS 12
#undef SIGPIPE
#define SIGPIPE 13
#undef SIGALRM
#define SIGALRM 14
#undef SIGTERM
#define SIGTERM 15
#undef SIGURG
#define SIGURG 16
#undef SIGSTOP
#define SIGSTOP 17
#undef SIGTSTP
#define SIGTSTP 18
#undef SIGCONT
#define SIGCONT 19
#undef SIGCHLD
#define SIGCHLD 20
#undef SIGTTIN
#define SIGTTIN 21
#undef SIGTTOU
#define SIGTTOU 22
#undef SIGIO
#define SIGIO 23
#undef SIGXCPU
#define SIGXCPU 24
#undef SIGXFSZ
#define SIGXFSZ 25
#undef SIGVTALRM
#define SIGVTALRM 26
#undef SIGPROF
#define SIGPROF 27
#undef SIGWINCH
#define SIGWINCH 28
#undef SIGINFO
#define SIGINFO 29
#undef SIGUSR1
#define SIGUSR1 30
#undef SIGUSR2
#define SIGUSR2 31
#undef SIGIOT
#define SIGIOT 6

/*
 * SIGPWR does not exist on Darwin: the Linux table assigns it 30, which
 * Darwin uses for SIGUSR1.  Leaving it defined made the two macros collide
 * and broke Node's src/api/utils.cc with "duplicate case value '30'"
 * (it switches over every SIG* it knows, and two names mapping to one
 * number is a hard error in a case list).  Same story for SIGPOLL, which
 * Linux aliases to SIGIO (29) -- Darwin's SIGIO is 23 and SIGPOLL is not
 * provided at all.
 *
 * Undefining rather than redefining is deliberate: the identifiers must
 * disappear so that #ifdef SIGPWR takes the false branch, exactly as it
 * does on a real iOS SDK.
 */
#undef SIGPWR
#undef SIGPOLL

/*
 * SIGSTKFLT is Linux-only (16 there) and collides with Darwin's SIGURG,
 * which is also 16.  Node switches over every SIG* name it finds, so the
 * collision is a hard "duplicate case value '16'" error rather than a
 * silent misbehaviour.  Darwin has no stack-fault signal: the identifier
 * must not exist.
 *
 * SIGUNUSED is likewise a Linux alias (of SIGSYS in musl, but 31 in the
 * Linux table) with no Darwin counterpart.
 */
#undef SIGSTKFLT
#undef SIGUNUSED

#undef SIG_BLOCK
#define SIG_BLOCK 1
#undef SIG_UNBLOCK
#define SIG_UNBLOCK 2
#undef SIG_SETMASK
#define SIG_SETMASK 3
#undef SA_NOCLDSTOP
#define SA_NOCLDSTOP 0x0008
#undef SA_NOCLDWAIT
#define SA_NOCLDWAIT 0x0020
#undef SA_SIGINFO
#define SA_SIGINFO 0x0040
#undef SA_ONSTACK
#define SA_ONSTACK 0x0001
#undef SA_RESTART
#define SA_RESTART 0x0002
#undef SA_NODEFER
#define SA_NODEFER 0x0010
#undef SA_RESETHAND
#define SA_RESETHAND 0x0004
#undef SA_RESTORER
#undef SA_USERTRAMP
#define SA_USERTRAMP 0x0100
#undef MINSIGSTKSZ
#define MINSIGSTKSZ 32768
#undef SIGSTKSZ
#define SIGSTKSZ 131072
/* ===== end DARWIN_OVERRIDES ===== */

