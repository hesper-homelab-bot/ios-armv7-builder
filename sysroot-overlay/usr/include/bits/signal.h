#if defined(_POSIX_SOURCE) || defined(_POSIX_C_SOURCE) \
 || defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)

#if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
#define MINSIGSTKSZ 2048
#define SIGSTKSZ 8192
#endif

#if defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
typedef int greg_t, gregset_t[18];
typedef struct sigcontext {
	unsigned long trap_no, error_code, oldmask;
	unsigned long arm_r0, arm_r1, arm_r2, arm_r3;
	unsigned long arm_r4, arm_r5, arm_r6, arm_r7;
	unsigned long arm_r8, arm_r9, arm_r10, arm_fp;
	unsigned long arm_ip, arm_sp, arm_lr, arm_pc;
	unsigned long arm_cpsr, fault_address;
} mcontext_t;
#else
typedef struct {
	unsigned long __regs[21];
} mcontext_t;
#endif

struct sigaltstack {
	void *ss_sp;
	int ss_flags;
	size_t ss_size;
};

typedef struct __ucontext {
	unsigned long uc_flags;
	struct __ucontext *uc_link;
	stack_t uc_stack;
	mcontext_t uc_mcontext;
	sigset_t uc_sigmask;
	unsigned long long uc_regspace[64];
} ucontext_t;

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

