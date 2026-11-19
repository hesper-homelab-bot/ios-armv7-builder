/*
 * pgrep/pkill for armv7 iOS 10.x -- Darwin adaptation of OpenBSD pkill.c
 * (usr.bin/pkill 1.44, NetBSD lineage).
 *
 * Why an adaptation instead of procps: Darwin has NO procfs, so every
 * /proc-based implementation is dead on arrival.  This file talks to the
 * kernel the way Apple's own killall does: sysctl(KERN_PROC_ALL) for the
 * process table and sysctl(KERN_PROCARGS2, pid) for full command lines
 * (needs root or same-uid; without it -f falls back to p_comm, the same
 * shape as the upstream kvm_getargv()==NULL path).
 *
 * Differences from the OpenBSD original, all forced by the platform:
 *   - kvm_openfiles/kvm_getprocs -> sysctl(KERN_PROC_ALL) with Darwin's
 *     struct kinfo_proc (fields live under kp_proc/kp_eproc; e_pcred and
 *     e_ucred are embedded BY VALUE in eproc, dot access).
 *   - kvm_getargv -> KERN_PROCARGS2 parsing.
 *   - pledge() is OpenBSD-only: dropped.
 *   - -T rtable is OpenBSD routing-table-only: dropped from the option set.
 *   - uid_from_user/gid_from_group -> getpwnam/getgrnam.
 *   - -s sid dropped: Darwin's eproc does not expose the session id via
 *     sysctl (no e_sid field in struct eproc).
 *   - strlcpy is provided by iOS libSystem.
 *
 * Build: pgrep/build.sh (SDK sysroot mode, cc-wrapper).  One binary, two
 * names: basename "pgrep" lists, anything else kills.
 */

#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/signal.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/time.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <regex.h>
#include <ctype.h>
#include <err.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>

#define STATUS_MATCH	0
#define STATUS_NOMATCH	1
#define STATUS_BADUSAGE	2
#define STATUS_ERROR	3

enum listtype {
	LT_GENERIC,
	LT_USER,
	LT_GROUP,
	LT_TTY,
	LT_PGRP
};

struct list {
	struct list *li_next;
	long	li_number;
};

struct listhead { struct list *lh_first; };

static struct kinfo_proc	*plist;
static char			*selected;
static int			nproc;
static int			pgrep;
static int			signum = SIGTERM;
static int			newest;
static int			oldest;
static int			quiet;
static int			inverse;
static int			longfmt;
static int			matchargs;
static int			fullmatch;
static int			confirmkill;
static pid_t			mypid;
static const char		*delim = "\n";

static struct listhead euidlist, ruidlist, rgidlist, pgrplist, ppidlist,
	tdevlist;

static int	killact(struct kinfo_proc *, int);
static int	grepact(struct kinfo_proc *, int);
static void	makelist(struct listhead *, enum listtype, char *);
static const char *getcomm(struct kinfo_proc *);
static char	*getargv(struct kinfo_proc *);
static void	freelist(struct listhead *);
static void	usage(void) __attribute__((__noreturn__));

static int (*action)(struct kinfo_proc *, int);

int
main(int argc, char **argv)
{
	char *base, *p, *q;
	int i, j, ch, rv, criteria;
	struct kinfo_proc *kp;
	struct list *li;
	struct timeval best;
	regex_t reg;
	regmatch_t regmatch;
	char errbuf[256];

	if ((base = strrchr(argv[0], '/')) == NULL)
		base = argv[0];
	else
		base++;

	if (strcmp(base, "pgrep") == 0) {
		action = grepact;
		pgrep = 1;
	} else {
		action = killact;
	}

	/* the signal-number prefix form only makes sense for pkill */
	if (!pgrep && argc > 1 && argv[1][0] == '-') {
		long v;
		p = argv[1] + 1;
		q = NULL;
		v = strtol(p, &q, 10);
		if (*q == '\0' && v > 0) {
			signum = (int)v;
			argv++; argc--;
		} else {
			if (strncasecmp(p, "sig", 3) == 0)
				p += 3;
			for (i = 1; i < NSIG; i++)
				if (strcasecmp(sys_signame[i], p) == 0)
					break;
			if (i != NSIG) {
				signum = i;
				argv++; argc--;
			}
		}
	}

	criteria = 0;
	while ((ch = getopt(argc, argv, "G:P:U:d:fg:Ilnou:vx")) != -1)
		switch (ch) {
		case 'G':
			makelist(&rgidlist, LT_GROUP, optarg);
			criteria = 1;
			break;
		case 'P':
			makelist(&ppidlist, LT_GENERIC, optarg);
			criteria = 1;
			break;
		case 'U':
			makelist(&ruidlist, LT_USER, optarg);
			criteria = 1;
			break;
		case 'd':
			if (!pgrep)
				usage();
			delim = optarg;
			break;
		case 'f':
			matchargs = 1;
			break;
		case 'g':
			makelist(&pgrplist, LT_PGRP, optarg);
			criteria = 1;
			break;
		case 'I':
			confirmkill = 1;
			break;
		case 'l':
			longfmt = 1;
			break;
		case 'n':
			newest = 1;
			criteria = 1;
			break;
		case 'o':
			oldest = 1;
			criteria = 1;
			break;
		case 'q':
			quiet = 1;
			break;
		case 't':
			makelist(&tdevlist, LT_TTY, optarg);
			criteria = 1;
			break;
		case 'u':
			makelist(&euidlist, LT_USER, optarg);
			criteria = 1;
			break;
		case 'v':
			inverse = 1;
			break;
		case 'x':
			fullmatch = 1;
			break;
		default:
			usage();
		}

	argc -= optind;
	argv += optind;
	if (argc != 0)
		criteria = 1;
	if (!criteria || (newest && oldest))
		usage();

	mypid = getpid();

	/*
	 * sysctl(KERN_PROC_ALL): two-phase size probe + read, the standard
	 * Darwin pattern.  The table can grow between the calls -- retry.
	 */
	plist = NULL;
	for (i = 0; i < 8; i++) {
		size_t len = 0;
		int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
		if (sysctl(mib, 3, NULL, &len, NULL, 0) == -1)
			err(STATUS_ERROR, "sysctl KERN_PROC_ALL (size)");
		free(plist);
		if ((plist = malloc(len)) == NULL)
			errx(STATUS_ERROR, "memory allocation failure");
		if (sysctl(mib, 3, plist, &len, NULL, 0) == -1) {
			if (errno == ENOMEM)
				continue;	/* grew: retry */
			err(STATUS_ERROR, "sysctl KERN_PROC_ALL");
		}
		nproc = (int)(len / sizeof(struct kinfo_proc));
		break;
	}
	if (i == 8)
		errx(STATUS_ERROR, "process table kept growing");

	if ((selected = calloc(nproc, 1)) == NULL)
		errx(STATUS_ERROR, "memory allocation failure");

	for (; *argv != NULL; argv++) {
		if ((rv = regcomp(&reg, *argv, REG_EXTENDED)) != 0) {
			regerror(rv, &reg, errbuf, sizeof(errbuf));
			errx(STATUS_BADUSAGE, "bad expression: %s", errbuf);
		}

		for (i = 0, kp = plist; i < nproc; i++, kp++) {
			const char *mstr;

			if (kp->kp_proc.p_pid == mypid)
				continue;

			mstr = matchargs ? getargv(kp) : getcomm(kp);

			rv = regexec(&reg, mstr, 1, &regmatch, 0);
			if (rv == 0) {
				if (fullmatch) {
					if (regmatch.rm_so == 0 &&
					    regmatch.rm_eo == strlen(mstr))
						selected[i] = 1;
				} else
					selected[i] = 1;
			} else if (rv != REG_NOMATCH) {
				regerror(rv, &reg, errbuf, sizeof(errbuf));
				errx(STATUS_ERROR, "regexec(): %s", errbuf);
			}
		}

		regfree(&reg);
	}

	for (i = 0, kp = plist; i < nproc; i++, kp++) {
		int skip = 0;

		if (kp->kp_proc.p_pid == mypid)
			continue;

		for (li = ruidlist.lh_first; li; li = li->li_next)
			if (kp->kp_eproc.e_pcred.p_ruid == (uid_t)li->li_number)
				break;
		if (ruidlist.lh_first && !li) skip = 1;
		for (li = rgidlist.lh_first; li && !skip; li = li->li_next)
			if (kp->kp_eproc.e_pcred.p_rgid == (gid_t)li->li_number)
				break;
		if (rgidlist.lh_first && !li) skip = 1;
		for (li = euidlist.lh_first; li && !skip; li = li->li_next)
			if (kp->kp_eproc.e_ucred.cr_uid == (uid_t)li->li_number)
				break;
		if (euidlist.lh_first && !li) skip = 1;
		for (li = ppidlist.lh_first; li && !skip; li = li->li_next)
			if (kp->kp_eproc.e_ppid == (pid_t)li->li_number)
				break;
		if (ppidlist.lh_first && !li) skip = 1;
		for (li = pgrplist.lh_first; li && !skip; li = li->li_next)
			if (kp->kp_eproc.e_pgid == (pid_t)li->li_number)
				break;
		if (pgrplist.lh_first && !li) skip = 1;
		for (li = tdevlist.lh_first; li && !skip; li = li->li_next) {
			if (li->li_number == -1 &&
			    (kp->kp_proc.p_flag & P_CONTROLT) == 0)
				break;
			if (kp->kp_eproc.e_tdev == (dev_t)li->li_number)
				break;
		}
		if (tdevlist.lh_first && !li) skip = 1;

		if (skip)
			selected[i] = 0;
		else if (argc == 0)
			selected[i] = 1;
	}

	if (newest || oldest) {
		int bestidx = -1;
		struct timeval best;

		if (newest)
			best.tv_sec = best.tv_usec = 0;
		else
			best.tv_sec = best.tv_usec = INT32_MAX;

		for (i = 0, kp = plist; i < nproc; i++, kp++) {
			struct timeval st = kp->kp_proc.p_starttime;
			if (!selected[i])
				continue;
			if ((newest && (st.tv_sec > best.tv_sec ||
			    (st.tv_sec == best.tv_sec && st.tv_usec > best.tv_usec)))
			 || (oldest && (st.tv_sec < best.tv_sec ||
			    (st.tv_sec == best.tv_sec && st.tv_usec < best.tv_usec)))) {
				best = st;
				bestidx = i;
			}
		}
		memset(selected, 0, nproc);
		if (bestidx != -1)
			selected[bestidx] = 1;
	}

	rv = STATUS_NOMATCH;
	for (i = 0, j = 0, kp = plist; i < nproc; i++, kp++) {
		if (kp->kp_proc.p_pid == mypid)
			continue;
		if (selected[i] == inverse)
			continue;

		switch ((*action)(kp, j++)) {
		case STATUS_MATCH:
			if (rv != STATUS_ERROR)
				rv = STATUS_MATCH;
			break;
		case STATUS_NOMATCH:
			j--;
			break;
		case STATUS_ERROR:
			rv = STATUS_ERROR;
			break;
		}
	}
	if (pgrep && j && !quiet)
		putchar('\n');

	freelist(&ruidlist); freelist(&rgidlist); freelist(&euidlist);
	freelist(&ppidlist); freelist(&pgrplist); freelist(&tdevlist);
	free(plist);
	free(selected);
	return rv;
}

static const char *
getcomm(struct kinfo_proc *kp)
{
	static char buf[MAXCOMLEN + 1];
	strlcpy(buf, kp->kp_proc.p_comm, sizeof(buf));
	return buf;
}

/*
 * KERN_PROCARGS2 layout: int32 argc, then NUL-terminated strings -- the
 * exec path first, then argv[0..argc-1], then the environment.  Needs root
 * or the same uid as the target; on EPERM/ESRCH the caller falls back to
 * p_comm (the same shape as the upstream kvm_getargv()==NULL path).
 */
static char *
getargv(struct kinfo_proc *kp)
{
	static char out[64 * 1024];
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROCARGS2, kp->kp_proc.p_pid };
	size_t len = sizeof(out);
	int argc, i;
	char *p, *end;
	size_t o = 0;

	if (sysctl(mib, 4, out, &len, NULL, 0) == -1)
		return getcomm(kp);	/* EPERM/ESRCH: fall back */
	memcpy(&argc, out, sizeof(argc));
	if (argc < 0 || argc > 4096)
		return getcomm(kp);
	p = out + sizeof(argc);
	end = out + len;
	p += strlen(p) + 1;		/* skip the exec path */
	for (i = 0; i < argc && p < end; i++) {
		size_t l = strlen(p);
		if (o + l + 2 >= sizeof(out))
			break;
		if (i) out[o++] = ' ';
		memmove(out + o, p, l);
		o += l;
		p += l + 1;
	}
	out[o] = '\0';
	return out;
}

static void
usage(void)
{
	if (pgrep)
		fprintf(stderr, "usage: pgrep [-flnoqvx] [-d delim] [-G gid] [-g pgrp]"
		    " [-P ppid] [-t tty] [-u euid] [pattern ...]\n");
	else
		fprintf(stderr, "usage: pkill [-signal] [-fIlnoqvx] [-G gid] [-g pgrp]"
		    " [-P ppid] [-t tty] [-u euid] [pattern ...]\n");
	exit(STATUS_BADUSAGE);
}

static int
askyn(struct kinfo_proc *kp)
{
	int first, ch;

	printf("kill %d %.60s? ", (int)kp->kp_proc.p_pid, getcomm(kp));
	fflush(stdout);

	first = ch = getchar();
	while (ch != '\n' && ch != EOF)
		ch = getchar();
	return (first == 'y' || first == 'Y');
}

static int
killact(struct kinfo_proc *kp, int dummy)
{
	int doit;

	if (confirmkill) {
		doit = askyn(kp);
	} else {
		if (longfmt && !quiet)
			printf("%d %s\n", (int)kp->kp_proc.p_pid, getcomm(kp));
		doit = 1;
	}

	if (doit && kill(kp->kp_proc.p_pid, signum) == -1) {
		if (errno == ESRCH)
			return (STATUS_NOMATCH);
		warn("signalling pid %d", (int)kp->kp_proc.p_pid);
		return (STATUS_ERROR);
	}
	return (STATUS_MATCH);
}

static int
grepact(struct kinfo_proc *kp, int printdelim)
{
	if (quiet)
		return (STATUS_MATCH);
	if (printdelim)
		fputs(delim, stdout);
	if (longfmt && matchargs)
		printf("%d %s", (int)kp->kp_proc.p_pid, getargv(kp));
	else if (longfmt)
		printf("%d %s", (int)kp->kp_proc.p_pid, getcomm(kp));
	else
		printf("%d", (int)kp->kp_proc.p_pid);

	return (STATUS_MATCH);
}

static void
makelist(struct listhead *head, enum listtype type, char *src)
{
	struct list *li;
	struct stat st;
	char *sp, *p, buf[PATH_MAX];
	uid_t uid;
	gid_t gid;
	struct passwd *pw;
	struct group *gr;
	int empty = 1;

	while ((sp = strsep(&src, ",")) != NULL) {
		if (*sp == '\0')
			usage();

		if ((li = malloc(sizeof(*li))) == NULL)
			errx(STATUS_ERROR, "memory allocation failure");
		li->li_next = head->lh_first;
		head->lh_first = li;
		empty = 0;

		li->li_number = strtol(sp, &p, 0);
		if (*p == '\0') {
			switch (type) {
			case LT_PGRP:
				if (li->li_number == 0)
					li->li_number = getpgrp();
				break;
			default:
				break;
			}
			continue;
		}

		switch (type) {
		case LT_USER:
			if ((pw = getpwnam(sp)) == NULL)
				errx(STATUS_BADUSAGE, "unknown user `%s'", sp);
			li->li_number = pw->pw_uid;
			break;
		case LT_GROUP:
			if ((gr = getgrnam(sp)) == NULL)
				errx(STATUS_BADUSAGE, "unknown group `%s'", sp);
			li->li_number = gr->gr_gid;
			break;
		case LT_TTY:
			if (strcmp(sp, "-") == 0) {
				li->li_number = -1;
				break;
			}
			if (strncmp(sp, "tty", 3) == 0)
				p = sp;
			else
				p = NULL;

			if (p == NULL)
				snprintf(buf, sizeof(buf), "/dev/%s", sp);
			else
				snprintf(buf, sizeof(buf), "/dev/%s", p);

			if (stat(buf, &st) == -1) {
				if (errno == ENOENT)
					errx(STATUS_BADUSAGE,
					    "no such tty: `%s'", sp);
				err(STATUS_ERROR, "stat(%s)", sp);
			}

			if (!S_ISCHR(st.st_mode))
				errx(STATUS_BADUSAGE, "not a tty: `%s'", sp);

			li->li_number = (long)st.st_rdev;
			break;
		default:
			usage();
		}
	}

	if (empty)
		usage();
}

static void
freelist(struct listhead *head)
{
	struct list *li = head->lh_first;
	while (li) {
		struct list *next = li->li_next;
		free(li);
		li = next;
	}
	head->lh_first = NULL;
}
