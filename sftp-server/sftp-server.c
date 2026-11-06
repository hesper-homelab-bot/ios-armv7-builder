/*
 * db-sftp-server -- the SFTP subsystem for Dropbear, built here.
 *
 * Why this file exists
 * -------------------
 * Dropbear does not ship an sftp server.  All it has is a *path*, chosen at
 * compile time, that the server execs when a client asks for the "sftp"
 * subsystem:
 *
 *     src/default_options.h:  #define SFTPSERVER_PATH "/usr/libexec/sftp-server"
 *     src/svr-chansession.c: execs it (expanding a leading ~/ against the
 *                             user's home directory) when the subsystem
 *                             request is exactly "sftp"
 *
 * The default path is OpenSSH's, and on this device that file belongs to the
 * openssh dpkg package -- dpkg -S /usr/libexec/sftp-server answers "openssh":
 * -- so leaving it alone made Dropbear's sftp depend on openssh staying
 * installed, and it broke the day openssh was removed.  db-scp was never
 * affected because it execs a path of our own.
 *
 * Reusing the OpenSSH sftp-server binary only moves the problem: it is the
 * program that package owns, and it is linked against libcrypto.  So this is
 * a from-scratch implementation of the server side of the SFTP protocol, in
 * plain C over POSIX syscalls: no OpenSSH, no OpenSSL, no /usr/libexec, and
 * it is installed as /var/mobile/tools/db-sftp-server to match the rest of
 * the kit's db- prefix.
 *
 * Protocol
 * --------
 * SSH_FILEXFER draft-ietf-secsh-filexfer-02, "protocol version 3", which is
 * what every sftp client speaks and what the device's own OpenSSH 6.7p1
 * client uses.  Dropbear execs this program on a session channel, so the SSH
 * packet layer (encryption, MAC, channel framing) is Dropbear's job and what
 * travels on stdin/stdout is the bare SFTP message layer -- the same split
 * OpenSSH's sftp-server uses:
 *
 *     uint32  length       of the payload, not counting itself
 *     byte    type
 *     ...    type-specific fields
 *
 * Version 3 rather than a newer draft, on purpose: it is the lowest common
 * denominator, none of the newer machinery (attribute counts in ATTRS
 * replies, extended READ/WRITE replies, version 6's own-group attribute
 * flags) is needed, and answering 3 keeps the client's assumptions exact.
 * Extended requests are refused with SSH_FX_OP_UNSUPPORTED as the
 * specification requires, which is what makes a modern client fall back to
 * plain v3 behaviour instead of guessing.
 *
 * Privileges and paths: the process runs as the logged-in user (Dropbear
 * drops privileges before exec), so file access is that user's own -- there
 * is no chroot and no setuid, exactly like OpenSSH's sftp-server.  The
 * working directory is the user's home, which Dropbear already chdir'ed to.
 *
 * Build: ../sftp-server/build.sh  (tools/cc-wrapper.sh, no configure step)
 */

#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#define PROGRAM_NAME	"db-sftp-server"
#define PROGRAM_VERSION	"1.0"

/* The protocol version we speak and advertise. */
#define OUR_SFTP_VERSION	3

/* Big enough for the largest READ the client will ask for, plus the
 * protocol overhead; the length prefix itself is not counted. */
#define MAX_MSG_LENGTH		(256 * 1024)
#define MAX_READ_LENGTH		(MAX_MSG_LENGTH - 1024)

/* Entries per READDIR reply, and the message size we stop growing a reply
 * at -- both are what keeps one directory read from blowing the channel. */
#define MAX_READDIR_ENTRIES	100
#define MAX_READDIR_BYTES	32768

/* Open handles: files (int fd) and directories (DIR * plus its path, which
 * READDIR needs to lstat each entry).  More than any client will hold. */
#define MAX_HANDLES		32

/* realpath()'s answer; Darwin's PATH_MAX is 1024 but the buffer is cheap. */
#define PATH_BUF		4096

/* ------------------------------------------------------------------ wire */

#define SSH2_FXP_INIT			1
#define SSH2_FXP_VERSION		2
#define SSH2_FXP_OPEN			3
#define SSH2_FXP_CLOSE			4
#define SSH2_FXP_READ			5
#define SSH2_FXP_WRITE			6
#define SSH2_FXP_LSTAT			7
#define SSH2_FXP_FSTAT			8
#define SSH2_FXP_SETSTAT		9
#define SSH2_FXP_FSETSTAT		10
#define SSH2_FXP_OPENDIR		11
#define SSH2_FXP_READDIR		12
#define SSH2_FXP_REMOVE			13
#define SSH2_FXP_MKDIR			14
#define SSH2_FXP_RMDIR			15
#define SSH2_FXP_REALPATH		16
#define SSH2_FXP_STAT			17
#define SSH2_FXP_RENAME			18
#define SSH2_FXP_READLINK		19
#define SSH2_FXP_SYMLINK		20

#define SSH2_FXP_STATUS			101
#define SSH2_FXP_HANDLE			102
#define SSH2_FXP_DATA			103
#define SSH2_FXP_NAME			104
#define SSH2_FXP_ATTRS			105

#define SSH2_FXP_EXTENDED		200
#define SSH2_FXP_EXTENDED_REPLY	201

#define SSH2_FILEXFER_ATTR_SIZE		0x00000001
#define SSH2_FILEXFER_ATTR_UIDGID	0x00000002
#define SSH2_FILEXFER_ATTR_PERMISSIONS	0x00000004
#define SSH2_FILEXFER_ATTR_ACMODTIME	0x00000008
#define SSH2_FILEXFER_ATTR_EXTENDED	0x80000000

#define SSH2_FXF_READ			0x00000001
#define SSH2_FXF_WRITE			0x00000002
#define SSH2_FXF_APPEND		0x00000004
#define SSH2_FXF_CREAT			0x00000008
#define SSH2_FXF_TRUNC			0x00000010
#define SSH2_FXF_EXCL			0x00000020

#define SSH2_FX_OK				0
#define SSH2_FX_EOF				1
#define SSH2_FX_NO_SUCH_FILE			2
#define SSH2_FX_PERMISSION_DENIED		3
#define SSH2_FX_FAILURE				4
#define SSH2_FX_BAD_MESSAGE			5
#define SSH2_FX_NO_CONNECTION			6
#define SSH2_FX_CONNECTION_LOST		7
#define SSH2_FX_OP_UNSUPPORTED			8
#define SSH2_FX_INVALID_HANDLE			9
#define SSH2_FX_NO_SUCH_PATH			10
#define SSH2_FX_FILE_ALREADY_EXISTS		11
#define SSH2_FX_WRITE_PROTECT			12
#define SSH2_FX_NO_MEDIA			13
#define SSH2_FX_MAX				13

/* ---------------------------------------------------------------- state */

struct attrib {
	uint32_t	flags;
	uint64_t	size;
	uint32_t	uid;
	uint32_t	gid;
	uint32_t	perm;
	uint32_t	atime;
	uint32_t	mtime;
};

struct handle {
	int	 fd;		/* regular file, or -1 for a directory */
	DIR	*dir;		/* open directory, or NULL for a file */
	char	*path;		/* directory path, for lstat(2) on entries */
};

/* A growable byte buffer.  "off" and "limit" are only meaningful for the
 * input buffer: off is the parse cursor, limit the end of the current
 * message, so a handler reading past its own message is caught instead of
 * eating the next one. */
struct buf {
	unsigned char	*d;
	size_t		 len;
	size_t		 cap;
	size_t		 off;
	size_t		 limit;
};

static struct buf	in;	/* bytes read from the client */
static struct buf	out;	/* bytes waiting to be written to the client */
static struct buf	msg;	/* reply being assembled */
static struct handle	handles[MAX_HANDLES];
static int		log_stderr;	/* -e */

/* ----------------------------------------------------------------- error */

/* Abandon the session.  Upstream's sftp-server does the same for messages it
 * cannot parse; the alternative -- guessing where the next message starts --
 * corrupts the stream for every later request. */
static void
cleanup_exit(int code)
{
	int i;

	for (i = 0; i < MAX_HANDLES; i++) {
		if (handles[i].dir != NULL)
			closedir(handles[i].dir);
		if (handles[i].fd >= 0)
			close(handles[i].fd);
		free(handles[i].path);
	}
	closelog();
	_exit(code);
}

static void
xlog(int level, const char *fmt, va_list ap)
{
	char line[512];

	if (vsnprintf(line, sizeof(line), fmt, ap) < 0)
		line[0] = '\0';
	syslog(level, "%s", line);
	if (log_stderr) {
		fprintf(stderr, "%s: %s\n", PROGRAM_NAME, line);
		fflush(stderr);
	}
}

static void
logit(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	xlog(LOG_INFO, fmt, ap);
	va_end(ap);
}

static void
verbose_f(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	xlog(LOG_DEBUG, fmt, ap);
	va_end(ap);
}

static void
fatal(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	xlog(LOG_ERR, fmt, ap);
	va_end(ap);
	cleanup_exit(255);
}

/* ---------------------------------------------------------------- buffers */

static void
buf_reserve(struct buf *b, size_t extra)
{
	size_t cap = b->cap ? b->cap : 4096;
	unsigned char *p;

	if (b->len + extra <= b->cap)
		return;
	while (cap < b->len + extra)
		cap *= 2;
	p = realloc(b->d, cap);
	if (p == NULL)
		fatal("out of memory");
	b->d = p;
	b->cap = cap;
}

static void
buf_append(struct buf *b, const void *p, size_t n)
{
	if (n == 0)
		return;
	buf_reserve(b, n);
	memcpy(b->d + b->len, p, n);
	b->len += n;
}

/* Drop "n" bytes from the front of a buffer.  A fully consumed input buffer
 * is rewound, so the window never grows without bound. */
static void
buf_consume(struct buf *b, size_t n)
{
	if (n > b->len - b->off)
		n = b->len - b->off;
	b->off += n;
	if (b->off == b->len) {
		b->off = 0;
		b->len = 0;
	}
}

static void
put_raw(struct buf *b, const void *p, size_t n)
{
	buf_append(b, p, n);
}

static void
put_u8(struct buf *b, uint8_t v)
{
	put_raw(b, &v, 1);
}

static void
put_u32(struct buf *b, uint32_t v)
{
	unsigned char d[4];

	d[0] = (v >> 24) & 0xff;
	d[1] = (v >> 16) & 0xff;
	d[2] = (v >> 8) & 0xff;
	d[3] = v & 0xff;
	put_raw(b, d, sizeof d);
}

static void
put_u64(struct buf *b, uint64_t v)
{
	put_u32(b, (uint32_t)(v >> 32));
	put_u32(b, (uint32_t)v);
}

/* Overwrite a u32 already written at "off" (used to back-patch counts). */
static void
patch_u32(struct buf *b, size_t off, uint32_t v)
{
	unsigned char d[4];

	if (off + sizeof(d) > b->len)
		fatal("internal: back-patch outside the message");
	d[0] = (v >> 24) & 0xff;
	d[1] = (v >> 16) & 0xff;
	d[2] = (v >> 8) & 0xff;
	d[3] = v & 0xff;
	memcpy(b->d + off, d, sizeof d);
}

/* ------------------------------------------------------- reading a request */

static void
parse_fail(void)
{
	logit("malformed message from client, abandoning session");
	cleanup_exit(2);
}

static uint8_t
p_u8(void)
{
	uint8_t v;

	if (in.off + 1 > in.limit)
		parse_fail();
	v = in.d[in.off];
	in.off += 1;
	return v;
}

static uint32_t
p_u32(void)
{
	const unsigned char *d;
	uint32_t v;

	if (in.off + 4 > in.limit)
		parse_fail();
	d = in.d + in.off;
	in.off += 4;
	v = ((uint32_t)d[0] << 24) | ((uint32_t)d[1] << 16) |
	    ((uint32_t)d[2] << 8) | (uint32_t)d[3];
	return v;
}

static uint64_t
p_u64(void)
{
	uint64_t hi = p_u32();
	uint64_t lo = p_u32();

	return (hi << 32) | lo;
}

/* Returns a pointer into the input buffer; the data stays valid until the
 * buffer is consumed, which is long enough for every caller here. */
static const unsigned char *
p_string(size_t *lenp)
{
	uint32_t l = p_u32();
	const unsigned char *p;

	if (l > in.limit - in.off)
		parse_fail();
	p = in.d + in.off;
	in.off += l;
	*lenp = l;
	return p;
}

/* A NUL-terminated copy, since a path has to outlive the buffer. */
static char *
p_cstring(void)
{
	size_t len;
	const unsigned char *p = p_string(&len);
	char *s;

	if (memchr(p, '\0', len) != NULL)
		parse_fail();
	s = malloc(len + 1);
	if (s == NULL)
		fatal("out of memory");
	memcpy(s, p, len);
	s[len] = '\0';
	return s;
}

static void
p_attrib(struct attrib *a)
{
	uint32_t count, i;
	size_t len;

	memset(a, 0, sizeof(*a));
	a->flags = p_u32();
	if (a->flags & SSH2_FILEXFER_ATTR_SIZE)
		a->size = p_u64();
	if (a->flags & SSH2_FILEXFER_ATTR_UIDGID) {
		a->uid = p_u32();
		a->gid = p_u32();
	}
	if (a->flags & SSH2_FILEXFER_ATTR_PERMISSIONS)
		a->perm = p_u32();
	if (a->flags & SSH2_FILEXFER_ATTR_ACMODTIME) {
		a->atime = p_u32();
		a->mtime = p_u32();
	}
	if (a->flags & SSH2_FILEXFER_ATTR_EXTENDED) {
		/* Unused vendor extensions: read past them. */
		count = p_u32();
		if (count > 0x10000)
			parse_fail();
		for (i = 0; i < count; i++) {
			p_string(&len);
			p_string(&len);
		}
	}
}

/* ------------------------------------------------------ writing a response */

static void
send_msg(void)
{
	uint32_t len = (uint32_t)msg.len;

	if (len > MAX_MSG_LENGTH)
		fatal("internal: reply of %u bytes is too long", len);
	put_u32(&out, len);
	buf_append(&out, msg.d, msg.len);
	msg.len = 0;
}

static void
m_u8(uint8_t v)
{
	put_u8(&msg, v);
}

static void
m_u32(uint32_t v)
{
	put_u32(&msg, v);
}

static void
m_cstr(const char *s)
{
	uint32_t len = (uint32_t)strlen(s);

	put_u32(&msg, len);
	buf_append(&msg, s, len);
}

/* The attribute set every stat-like reply carries.  Only the four v3 fields
 * are sent: the newer sub-second and owner-by-name bits would need the
 * extended flags, and no v3 client asks for them. */
static void
m_attrib(const struct stat *st)
{
	m_u32(SSH2_FILEXFER_ATTR_SIZE | SSH2_FILEXFER_ATTR_UIDGID |
	    SSH2_FILEXFER_ATTR_PERMISSIONS | SSH2_FILEXFER_ATTR_ACMODTIME);
	put_u64(&msg, (uint64_t)st->st_size);
	m_u32((uint32_t)st->st_uid);
	m_u32((uint32_t)st->st_gid);
	m_u32((uint32_t)st->st_mode);
	m_u32((uint32_t)st->st_atime);
	m_u32((uint32_t)st->st_mtime);
}

static void
m_attrib_none(void)
{
	m_u32(0);
}

static const char *
fx_to_text(uint32_t status)
{
	static const char * const names[] = {
		"Success",			/* SSH2_FX_OK */
		"End of file",			/* SSH2_FX_EOF */
		"No such file",			/* SSH2_FX_NO_SUCH_FILE */
		"Permission denied",		/* SSH2_FX_PERMISSION_DENIED */
		"Failure",			/* SSH2_FX_FAILURE */
		"Bad message",			/* SSH2_FX_BAD_MESSAGE */
		"No connection",		/* SSH2_FX_NO_CONNECTION */
		"Connection lost",		/* SSH2_FX_CONNECTION_LOST */
		"Operation unsupported",	/* SSH2_FX_OP_UNSUPPORTED */
		"Invalid handle",		/* SSH2_FX_INVALID_HANDLE */
		"No such path",			/* SSH2_FX_NO_SUCH_PATH */
		"File already exists",		/* SSH2_FX_FILE_ALREADY_EXISTS */
		"Write protected",		/* SSH2_FX_WRITE_PROTECT */
		"No media"			/* SSH2_FX_NO_MEDIA */
	};

	if (status > SSH2_FX_MAX)
		return "Unknown error";
	return names[status];
}

static void
send_status(uint32_t id, uint32_t status, const char *errmsg)
{
	m_u8(SSH2_FXP_STATUS);
	m_u32(id);
	m_u32(status);
	/* Protocol version 3 carries the error text and a language tag. */
	m_cstr(errmsg != NULL ? errmsg : fx_to_text(status));
	m_cstr("");
	send_msg();
}

/* Map an errno onto the SFTP status codes.  EEXIST is reported as
 * FILE_ALREADY_EXISTS on top of what upstream does, because that is what an
 * SFTP client is expected to show for "put over an existing file with -a"
 * -- and O_EXCL is the only place it can arrive from. */
static uint32_t
errno_to_fx(int err)
{
	switch (err) {
	case 0:
		return SSH2_FX_OK;
	case ENOENT:
	case ENOTDIR:
	case EBADF:
	case ELOOP:
		return SSH2_FX_NO_SUCH_FILE;
	case EPERM:
	case EACCES:
	case EFAULT:
		return SSH2_FX_PERMISSION_DENIED;
	case ENAMETOOLONG:
	case EINVAL:
		return SSH2_FX_BAD_MESSAGE;
	case ENOSYS:
		return SSH2_FX_OP_UNSUPPORTED;
	case EEXIST:
		return SSH2_FX_FILE_ALREADY_EXISTS;
	default:
		return SSH2_FX_FAILURE;
	}
}

static void
send_status_errno(uint32_t id, int err)
{
	send_status(id, errno_to_fx(err), strerror(err));
}

/* ------------------------------------------------------------------ names */

/* "drwxr-xr-x  3 mobile  mobile  4096 Jan  9  2016 name", the shape an
 * sftp client's "ls -l" prints verbatim as the long name. */
static char *
long_name(const char *name, const struct stat *st)
{
	const char *rwx = "rwxrwxrwx";
	char mode[11], tbuf[32], ubuf[32], gbuf[32], nbuf[32];
	const char *user, *group;
	struct passwd *pw;
	struct group *gr;
	struct tm *tm;
	time_t now;
	char *out;
	int i;

	mode[0] = S_ISDIR(st->st_mode) ? 'd' :
	    S_ISLNK(st->st_mode) ? 'l' :
	    S_ISCHR(st->st_mode) ? 'c' :
	    S_ISBLK(st->st_mode) ? 'b' :
	    S_ISFIFO(st->st_mode) ? 'p' :
	    S_ISSOCK(st->st_mode) ? 's' : '-';
	for (i = 0; i < 9; i++)
		mode[1 + i] = (st->st_mode & (0400 >> i)) ? rwx[i] : '-';
	if (st->st_mode & S_ISUID)
		mode[3] = (st->st_mode & 0100) ? 's' : 'S';
	if (st->st_mode & S_ISGID)
		mode[6] = (st->st_mode & 0010) ? 's' : 'S';
	if (st->st_mode & S_ISVTX)
		mode[9] = (st->st_mode & 0001) ? 't' : 'T';
	mode[10] = '\0';

	pw = getpwuid(st->st_uid);
	if (pw != NULL) {
		user = pw->pw_name;
	} else {
		snprintf(ubuf, sizeof(ubuf), "%u", (unsigned)st->st_uid);
		user = ubuf;
	}
	gr = getgrgid(st->st_gid);
	if (gr != NULL) {
		group = gr->gr_name;
	} else {
		snprintf(gbuf, sizeof(gbuf), "%u", (unsigned)st->st_gid);
		group = gbuf;
	}
	snprintf(nbuf, sizeof(nbuf), "%u", (unsigned)st->st_nlink);

	tbuf[0] = '\0';
	tm = localtime(&st->st_mtime);
	now = time(NULL);
	if (tm != NULL) {
		if (now - 365 * 24 * 60 * 60 / 2 < (time_t)st->st_mtime &&
		    now >= (time_t)st->st_mtime)
			(void)strftime(tbuf, sizeof(tbuf), "%b %e %H:%M", tm);
		else
			(void)strftime(tbuf, sizeof(tbuf), "%b %e  %Y", tm);
	}

	out = malloc(strlen(name) + 256);
	if (out == NULL)
		fatal("out of memory");
	snprintf(out, strlen(name) + 256, "%s %3s %-8s %-8s %8llu %s %s",
	    mode, nbuf, user, group, (unsigned long long)st->st_size,
	    tbuf, name);
	return out;
}

static char *
path_join(const char *dir, const char *name)
{
	size_t dlen = strlen(dir), nlen = strlen(name);
	int slash = dlen > 0 && dir[dlen - 1] != '/';
	char *p;

	p = malloc(dlen + slash + nlen + 1);
	if (p == NULL)
		fatal("out of memory");
	memcpy(p, dir, dlen);
	if (slash)
		p[dlen] = '/';
	memcpy(p + dlen + slash, name, nlen + 1);
	return p;
}

/* ---------------------------------------------------------------- handles */

static int
handle_new(void)
{
	int i;

	for (i = 0; i < MAX_HANDLES; i++) {
		if (handles[i].fd < 0 && handles[i].dir == NULL)
			return i;
	}
	return -1;
}

static void
send_handle(uint32_t id, int idx)
{
	char s[32];

	snprintf(s, sizeof(s), "%d", idx);
	m_u8(SSH2_FXP_HANDLE);
	m_u32(id);
	m_cstr(s);
	send_msg();
}

/* Handle strings are opaque bytes to the protocol; a decimal index is the
 * cheapest thing to hand out. */
static int
p_handle_index(void)
{
	size_t len;
	const unsigned char *p = p_string(&len);
	char s[32];
	long v;
	int i;

	if (len == 0 || len >= sizeof(s))
		return -1;
	memcpy(s, p, len);
	s[len] = '\0';
	if (s[0] < '0' || s[0] > '9')
		return -1;
	v = strtol(s, NULL, 10);
	if (v < 0 || v >= MAX_HANDLES)
		return -1;
	i = (int)v;
	if (handles[i].fd < 0 && handles[i].dir == NULL)
		return -1;
	return i;
}

/* ------------------------------------------------------------- attributes */

/* Apply an SFTP attribute set to a path (or an open fd).  Symlinks are
 * followed: lstat/SETSTAT on a symlink itself is a v6 refinement and not
 * worth half a dozen lchown/lutimes probes here.  Order matters -- the
 * timestamp is applied last so the other changes do not reset it. */
static int
apply_attrib_path(const char *path, const struct attrib *a)
{
	if (a->flags & SSH2_FILEXFER_ATTR_SIZE) {
		if (truncate(path, (off_t)a->size) < 0)
			return errno;
	}
	if (a->flags & SSH2_FILEXFER_ATTR_PERMISSIONS) {
		if (chmod(path, (mode_t)(a->perm & 07777)) < 0)
			return errno;
	}
	if (a->flags & SSH2_FILEXFER_ATTR_UIDGID) {
		if (chown(path, (uid_t)a->uid, (gid_t)a->gid) < 0)
			return errno;
	}
	if (a->flags & SSH2_FILEXFER_ATTR_ACMODTIME) {
		struct timeval tv[2];

		tv[0].tv_sec = (time_t)a->atime;
		tv[0].tv_usec = 0;
		tv[1].tv_sec = (time_t)a->mtime;
		tv[1].tv_usec = 0;
		if (utimes(path, tv) < 0)
			return errno;
	}
	return 0;
}

static int
apply_attrib_fd(int fd, const struct attrib *a)
{
	if (a->flags & SSH2_FILEXFER_ATTR_SIZE) {
		if (ftruncate(fd, (off_t)a->size) < 0)
			return errno;
	}
	if (a->flags & SSH2_FILEXFER_ATTR_PERMISSIONS) {
		if (fchmod(fd, (mode_t)(a->perm & 07777)) < 0)
			return errno;
	}
	if (a->flags & SSH2_FILEXFER_ATTR_UIDGID) {
		if (fchown(fd, (uid_t)a->uid, (gid_t)a->gid) < 0)
			return errno;
	}
	if (a->flags & SSH2_FILEXFER_ATTR_ACMODTIME) {
		struct timeval tv[2];

		tv[0].tv_sec = (time_t)a->atime;
		tv[0].tv_usec = 0;
		tv[1].tv_sec = (time_t)a->mtime;
		tv[1].tv_usec = 0;
		if (futimes(fd, tv) < 0)
			return errno;
	}
	return 0;
}

/* Turn SFTP's portable open flags into open(2) flags.  The ACCMODE mapping
 * is the one the protocol specifies: READ+WRITE means O_RDWR, and a bare
 * WRITE means O_WRONLY, so a file can be opened write-only without also
 * being read. */
static int
open_flags(uint32_t pflags)
{
	int flags;

	if ((pflags & SSH2_FXF_READ) && (pflags & SSH2_FXF_WRITE))
		flags = O_RDWR;
	else if (pflags & SSH2_FXF_READ)
		flags = O_RDONLY;
	else if (pflags & SSH2_FXF_WRITE)
		flags = O_WRONLY;
	else
		flags = O_RDONLY;
	if (pflags & SSH2_FXF_APPEND)
		flags |= O_APPEND;
	if (pflags & SSH2_FXF_CREAT)
		flags |= O_CREAT;
	if (pflags & SSH2_FXF_TRUNC)
		flags |= O_TRUNC;
	if (pflags & SSH2_FXF_EXCL)
		flags |= O_EXCL;
	return flags;
}

/* ---------------------------------------------------------------- requests */

static void
process_init(void)
{
	uint32_t their_version;

	their_version = p_u32();
	logit("client protocol version %u, serving %u",
	    their_version, OUR_SFTP_VERSION);

	m_u8(SSH2_FXP_VERSION);
	m_u32(OUR_SFTP_VERSION);
	/* Extension names are optional "name, version" pairs padded onto the
	 * end of this reply.  A version 3 client will not send an extended
	 * request it was not told about, so advertising exactly what is
	 * implemented here keeps "ls -l" on the client's own formatting (which
	 * prints full paths) and still lets everything else fall back to plain
	 * version 3 operations. */
	m_cstr("hardlink@openssh.com");
	m_cstr("1");
	m_cstr("users-groups-by-id@openssh.com");
	m_cstr("1");
	send_msg();
}

static void
process_open(uint32_t id)
{
	char *name;
	uint32_t pflags;
	struct attrib a;
	struct handle *h;
	int fd, idx, mode;

	name = p_cstring();
	pflags = p_u32();
	p_attrib(&a);

	mode = (a.flags & SSH2_FILEXFER_ATTR_PERMISSIONS) ?
	    (int)(a.perm & 07777) : 0666;
	fd = open(name, open_flags(pflags), mode);
	if (fd < 0) {
		verbose_f("open \"%s\" failed: %s", name, strerror(errno));
		send_status_errno(id, errno);
		free(name);
		return;
	}
	idx = handle_new();
	if (idx < 0) {
		close(fd);
		send_status(id, SSH2_FX_FAILURE, "too many open handles");
		free(name);
		return;
	}
	h = &handles[idx];
	h->fd = fd;
	h->dir = NULL;
	h->path = NULL;
	verbose_f("open \"%s\" -> handle %d", name, idx);
	send_handle(id, idx);
	free(name);
}

static void
process_close(uint32_t id)
{
	struct handle *h;
	int idx = p_handle_index();

	if (idx < 0) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "invalid handle");
		return;
	}
	h = &handles[idx];
	if (h->dir != NULL)
		closedir(h->dir);
	if (h->fd >= 0)
		close(h->fd);
	free(h->path);
	h->fd = -1;
	h->dir = NULL;
	h->path = NULL;
	send_status(id, SSH2_FX_OK, NULL);
}

static void
process_read(uint32_t id)
{
	unsigned char *data;
	struct handle *h;
	uint64_t off;
	uint32_t len;
	ssize_t n;
	int idx = p_handle_index();

	if (idx < 0) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "invalid handle");
		return;
	}
	off = p_u64();
	len = p_u32();
	if (len > MAX_READ_LENGTH)
		len = MAX_READ_LENGTH;
	h = &handles[idx];
	if (h->fd < 0 || h->dir != NULL) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "not a file handle");
		return;
	}
	data = malloc(len ? len : 1);
	if (data == NULL)
		fatal("out of memory");
	n = pread(h->fd, data, len, (off_t)off);
	if (n < 0) {
		send_status_errno(id, errno);
	} else if (n == 0) {
		send_status(id, SSH2_FX_EOF, NULL);
	} else {
		m_u8(SSH2_FXP_DATA);
		m_u32(id);
		put_u32(&msg, (uint32_t)n);
		buf_append(&msg, data, (size_t)n);
		send_msg();
	}
	free(data);
}

static void
process_write(uint32_t id)
{
	const unsigned char *data;
	struct handle *h;
	uint64_t off;
	size_t len;
	int idx = p_handle_index();

	if (idx < 0) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "invalid handle");
		return;
	}
	off = p_u64();
	data = p_string(&len);
	h = &handles[idx];
	if (h->fd < 0 || h->dir != NULL) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "not a file handle");
		return;
	}
	/* v3 replies STATUS, not a byte count: the write either happened or
	 * the client gets an error. */
	if (pwrite(h->fd, data, len, (off_t)off) < 0)
		send_status_errno(id, errno);
	else {
		verbose_f("write %zu bytes at %llu to handle %d",
		    len, (unsigned long long)off, idx);
		send_status(id, SSH2_FX_OK, NULL);
	}
}

static void
process_stat_path(uint32_t id, int follow)
{
	struct stat st;
	char *name = p_cstring();

	if ((follow ? stat(name, &st) : lstat(name, &st)) < 0) {
		send_status_errno(id, errno);
		free(name);
		return;
	}
	m_u8(SSH2_FXP_ATTRS);
	m_u32(id);
	m_attrib(&st);
	send_msg();
	free(name);
}

static void
process_stat_fd(uint32_t id)
{
	struct stat st;
	int idx = p_handle_index();

	if (idx < 0) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "invalid handle");
		return;
	}
	if (fstat(handles[idx].fd, &st) < 0) {
		send_status_errno(id, errno);
		return;
	}
	m_u8(SSH2_FXP_ATTRS);
	m_u32(id);
	m_attrib(&st);
	send_msg();
}

/* Write big-endian u32 / cstring into a caller-owned buffer that is sized
 * for the worst case ("4 + count * 300" covers 4 + strlen(name) per entry). */
static void
put_u32_at(unsigned char *d, size_t *len, uint32_t v)
{
	d[(*len)++] = (v >> 24) & 0xff;
	d[(*len)++] = (v >> 16) & 0xff;
	d[(*len)++] = (v >> 8) & 0xff;
	d[(*len)++] = v & 0xff;
}

static void
put_cstr_at(unsigned char *d, size_t *len, const char *s)
{
	size_t n = strlen(s);

	put_u32_at(d, len, (uint32_t)n);
	memcpy(d + *len, s, n);
	*len += n;
}

/* Read a big-endian u32 out of a raw buffer (the request payload is a
 * string containing "count, count * u32", and the parse cursor is not used
 * for its contents). */
static uint32_t
get_u32_raw(const unsigned char *d)
{
	return ((uint32_t)d[0] << 24) | ((uint32_t)d[1] << 16) |
	    ((uint32_t)d[2] << 8) | (uint32_t)d[3];
}

/*
 * "users-groups-by-id@openssh.com" (version 1).
 *
 * The client asks for every uid and gid a directory listing contains at
 * once, in the order it will display them, and gets back the names in that
 * same order -- an empty string for an id the system has no name for.  It is
 * worth answering because it is what decides whether "ls -l" formats the
 * lines itself (full paths, as on a real sftp server) or takes the long
 * names from the READDIR replies instead.
 */
static void
ids_to_names(const unsigned char *buf, size_t len, int is_user,
    unsigned char **outp, size_t *outlenp)
{
	unsigned char *out;
	size_t olen = 0, i, count;
	const char *name;
	char numbuf[32];

	/* The list is bare "id, id, ..." -- no count field on either side. */
	if (len % 4 != 0)
		parse_fail();
	count = len / 4;

	out = malloc(count * 300 + 1);
	if (out == NULL)
		fatal("out of memory");
	for (i = 0; i < count; i++) {
		uint32_t n = get_u32_raw(buf + i * 4);

		if (is_user) {
			struct passwd *pw = getpwuid((uid_t)n);

			name = pw != NULL ? pw->pw_name : NULL;
		} else {
			struct group *gr = getgrgid((gid_t)n);

			name = gr != NULL ? gr->gr_name : NULL;
		}
		if (name == NULL) {
			/* Unresolvable ids come back as numbers rather than an
			 * empty string, so "ls -l" still shows something useful
			 * when the client cannot resolve them locally. */
			snprintf(numbuf, sizeof(numbuf), "%u", (unsigned)n);
			name = numbuf;
		}
		put_cstr_at(out, &olen, name);
	}
	*outp = out;
	*outlenp = olen;
}

static void
process_extended_users_groups_by_id(uint32_t id)
{
	unsigned char *unames = NULL, *gnames = NULL;
	size_t ulen, glen, unlen = 0, gnlen = 0;
	const unsigned char *ubuf, *gbuf;

	ubuf = p_string(&ulen);
	gbuf = p_string(&glen);

	ids_to_names(ubuf, ulen, 1, &unames, &unlen);
	ids_to_names(gbuf, glen, 0, &gnames, &gnlen);

	m_u8(SSH2_FXP_EXTENDED_REPLY);
	m_u32(id);
	put_u32(&msg, (uint32_t)unlen);
	buf_append(&msg, unames, unlen);
	put_u32(&msg, (uint32_t)gnlen);
	buf_append(&msg, gnames, gnlen);
	send_msg();
	free(unames);
	free(gnames);
}

static void
process_setstat(uint32_t id, int fd_based)
{
	struct attrib a;
	char *name = NULL;
	int err, idx = -1, fd = -1;
	if (fd_based) {
		idx = p_handle_index();
		if (idx < 0) {
			send_status(id, SSH2_FX_INVALID_HANDLE,
			    "invalid handle");
			return;
		}
		fd = handles[idx].fd;
		if (fd < 0) {
			send_status(id, SSH2_FX_INVALID_HANDLE,
			    "not a file handle");
			return;
		}
	} else {
		name = p_cstring();
	}
	p_attrib(&a);

	err = fd_based ? apply_attrib_fd(fd, &a) :
	    apply_attrib_path(name, &a);
	if (err != 0)
		send_status_errno(id, err);
	else
		send_status(id, SSH2_FX_OK, NULL);
	free(name);
}

static void
process_opendir(uint32_t id)
{
	DIR *dir;
	char *name = p_cstring();
	struct handle *h;
	int idx;

	dir = opendir(name);
	if (dir == NULL) {
		send_status_errno(id, errno);
		free(name);
		return;
	}
	idx = handle_new();
	if (idx < 0) {
		closedir(dir);
		send_status(id, SSH2_FX_FAILURE, "too many open handles");
		free(name);
		return;
	}
	h = &handles[idx];
	h->fd = -1;
	h->dir = dir;
	h->path = name;		/* kept: READDIR needs it to lstat entries */
	verbose_f("opendir \"%s\" -> handle %d", name, idx);
	send_handle(id, idx);
}

static void
process_readdir(uint32_t id)
{
	struct dirent *de;
	struct handle *h;
	struct stat st;
	const char *path;
	char *full, *longn;
	size_t count_off;
	uint32_t count = 0;
	int idx = p_handle_index();

	if (idx < 0) {
		send_status(id, SSH2_FX_INVALID_HANDLE, "invalid handle");
		return;
	}
	h = &handles[idx];
	if (h->dir == NULL || h->path == NULL) {
		send_status(id, SSH2_FX_INVALID_HANDLE,
		    "not a directory handle");
		return;
	}
	path = h->path;

	/* Count is back-patched: entries are appended until the batch is
	 * full, and a directory is read across several requests. */
	m_u8(SSH2_FXP_NAME);
	m_u32(id);
	count_off = msg.len;
	m_u32(0);

	while (count < MAX_READDIR_ENTRIES && msg.len < MAX_READDIR_BYTES) {
		errno = 0;
		de = readdir(h->dir);
		if (de == NULL) {
			if (errno != 0)
				logit("readdir \"%s\" failed: %s", path,
				    strerror(errno));
			break;
		}
		full = path_join(path, de->d_name);
		if (lstat(full, &st) < 0) {
			verbose_f("lstat \"%s\" failed: %s", full,
			    strerror(errno));
			free(full);
			continue;
		}
		longn = long_name(de->d_name, &st);
		m_cstr(de->d_name);
		m_cstr(longn);
		m_attrib(&st);
		free(longn);
		free(full);
		count++;
	}

	if (count == 0) {
		msg.len = 0;	/* discard the empty NAME reply */
		send_status(id, SSH2_FX_EOF, NULL);
		return;
	}
	patch_u32(&msg, count_off, count);
	send_msg();
}

static void
process_remove(uint32_t id)
{
	char *name = p_cstring();

	if (unlink(name) < 0)
		send_status_errno(id, errno);
	else
		send_status(id, SSH2_FX_OK, NULL);
	free(name);
}

static void
process_mkdir(uint32_t id)
{
	struct attrib a;
	char *name = p_cstring();
	mode_t mode;

	p_attrib(&a);
	mode = (a.flags & SSH2_FILEXFER_ATTR_PERMISSIONS) ?
	    (a.perm & 07777) : 0777;
	if (mkdir(name, mode) < 0)
		send_status_errno(id, errno);
	else
		send_status(id, SSH2_FX_OK, NULL);
	free(name);
}

static void
process_rmdir(uint32_t id)
{
	char *name = p_cstring();

	if (rmdir(name) < 0)
		send_status_errno(id, errno);
	else
		send_status(id, SSH2_FX_OK, NULL);
	free(name);
}

static void
process_realpath(uint32_t id)
{
	struct stat st;
	char *name = p_cstring();
	char resolved[PATH_BUF];

	if (realpath(name, resolved) == NULL) {
		send_status_errno(id, errno);
		free(name);
		return;
	}
	if (stat(resolved, &st) < 0) {
		send_status_errno(id, errno);
		free(name);
		return;
	}
	verbose_f("realpath \"%s\" -> \"%s\"", name, resolved);
	m_u8(SSH2_FXP_NAME);
	m_u32(id);
	m_u32(1);
	m_cstr(resolved);	/* short name */
	m_cstr(resolved);	/* long name */
	m_attrib(&st);
	send_msg();
	free(name);
}

static void
process_rename(uint32_t id)
{
	char *oldpath = p_cstring();
	char *newpath = p_cstring();

	if (rename(oldpath, newpath) < 0)
		send_status_errno(id, errno);
	else
		send_status(id, SSH2_FX_OK, NULL);
	free(oldpath);
	free(newpath);
}

static void
process_readlink(uint32_t id)
{
	struct stat st;
	char buf[PATH_BUF];
	char *name = p_cstring();
	ssize_t len;

	len = readlink(name, buf, sizeof(buf) - 1);
	if (len < 0) {
		send_status_errno(id, errno);
		free(name);
		return;
	}
	buf[len] = '\0';
	if (lstat(name, &st) == 0)
		verbose_f("readlink \"%s\" -> \"%s\"", name, buf);

	m_u8(SSH2_FXP_NAME);
	m_u32(id);
	m_u32(1);
	m_cstr(buf);	/* short name */
	m_cstr(buf);	/* long name */
	m_attrib_none();
	send_msg();
	free(name);
}

static void
process_symlink(uint32_t id)
{
	char *linkpath = p_cstring();		/* the target to point at */
	char *newpath = p_cstring();		/* where the link is made */

	verbose_f("symlink \"%s\" -> \"%s\"", newpath, linkpath);
	if (symlink(linkpath, newpath) < 0)
		send_status_errno(id, errno);
	else
		send_status(id, SSH2_FX_OK, NULL);
	free(linkpath);
	free(newpath);
}

static void
process_extended(uint32_t id)
{
	char *request = p_cstring();

	/* The one extension worth answering: protocol version 3 has no LINK
	 * message at all (draft 02 leaves hard links to the later drafts), and
	 * "hardlink@openssh.com" is what an sftp client uses for "ln".  Both
	 * operands arrive as plain strings. */
	if (strcmp(request, "users-groups-by-id@openssh.com") == 0) {
		process_extended_users_groups_by_id(id);
		free(request);
		return;
	}
	if (strcmp(request, "hardlink@openssh.com") == 0) {
		char *oldpath = p_cstring();
		char *newpath = p_cstring();

		verbose_f("hardlink \"%s\" -> \"%s\"", oldpath, newpath);
		if (link(oldpath, newpath) < 0)
			send_status_errno(id, errno);
		else
			send_status(id, SSH2_FX_OK, NULL);
		free(oldpath);
		free(newpath);
		free(request);
		return;
	}

	/* Refuse everything else, as the specification demands, so a modern
	 * client falls back to plain version 3 requests instead of guessing
	 * (statvfs, posix-rename, limits, ...). */
	verbose_f("unsupported extended request \"%s\"", request);
	send_status(id, SSH2_FX_OP_UNSUPPORTED, "not supported");
	free(request);
}

static void
process(void)
{
	uint32_t msg_len, id;
	size_t end;
	uint8_t type;

	if (in.len - in.off < 5)
		return;				/* not even a header yet */
	msg_len = ((uint32_t)in.d[in.off] << 24) |
	    ((uint32_t)in.d[in.off + 1] << 16) |
	    ((uint32_t)in.d[in.off + 2] << 8) |
	    (uint32_t)in.d[in.off + 3];
	if (msg_len > MAX_MSG_LENGTH) {
		logit("client message of %u bytes is too long", msg_len);
		cleanup_exit(11);
	}
	if (in.len - in.off < (size_t)msg_len + 4)
		return;				/* incomplete, wait for more */

	buf_consume(&in, 4);
	end = in.off + msg_len;
	in.limit = end;

	type = p_u8();
	if (type == SSH2_FXP_INIT) {
		process_init();
	} else {
		id = p_u32();
		switch (type) {
		case SSH2_FXP_OPEN:
			process_open(id);
			break;
		case SSH2_FXP_CLOSE:
			process_close(id);
			break;
		case SSH2_FXP_READ:
			process_read(id);
			break;
		case SSH2_FXP_WRITE:
			process_write(id);
			break;
		case SSH2_FXP_LSTAT:
			process_stat_path(id, 0);
			break;
		case SSH2_FXP_STAT:
			process_stat_path(id, 1);
			break;
		case SSH2_FXP_FSTAT:
			process_stat_fd(id);
			break;
		case SSH2_FXP_SETSTAT:
			process_setstat(id, 0);
			break;
		case SSH2_FXP_FSETSTAT:
			process_setstat(id, 1);
			break;
		case SSH2_FXP_OPENDIR:
			process_opendir(id);
			break;
		case SSH2_FXP_READDIR:
			process_readdir(id);
			break;
		case SSH2_FXP_REMOVE:
			process_remove(id);
			break;
		case SSH2_FXP_MKDIR:
			process_mkdir(id);
			break;
		case SSH2_FXP_RMDIR:
			process_rmdir(id);
			break;
		case SSH2_FXP_REALPATH:
			process_realpath(id);
			break;
		case SSH2_FXP_RENAME:
			process_rename(id);
			break;
		case SSH2_FXP_READLINK:
			process_readlink(id);
			break;
		case SSH2_FXP_SYMLINK:
			process_symlink(id);
			break;
		case SSH2_FXP_EXTENDED:
			process_extended(id);
			break;
		default:
			verbose_f("unknown message type %u", type);
			/* No id to answer: the message shape is unknown. */
			break;
		}
	}

	/* A handler may have left bytes unread (trailing garbage); drop the
	 * rest of this message so the stream stays aligned. */
	if (in.off < end)
		buf_consume(&in, end - in.off);
	else if (in.off > end)
		fatal("internal: handler read past the end of a message");
}

/* ------------------------------------------------------------------- main */

/* Move input into the buffer; returns 0 at end of stream. */
static int
read_more(void)
{
	unsigned char tmp[16384];
	ssize_t n;

	n = read(STDIN_FILENO, tmp, sizeof(tmp));
	if (n == 0)
		return 0;
	if (n < 0) {
		if (errno == EINTR || errno == EAGAIN)
			return 1;
		logit("read: %s", strerror(errno));
		cleanup_exit(1);
	}
	buf_append(&in, tmp, (size_t)n);
	return 1;
}

/* Push pending output out; returns 0 if the peer is gone. */
static int
flush_out(void)
{
	ssize_t n;

	while (out.len > out.off) {
		n = write(STDOUT_FILENO, out.d + out.off, out.len - out.off);
		if (n > 0) {
			buf_consume(&out, (size_t)n);
			continue;
		}
		if (n < 0 && (errno == EINTR || errno == EAGAIN))
			return 1;
		if (n < 0 && errno == EPIPE) {
			verbose_f("write: client closed the connection");
			return 0;
		}
		logit("write: %s", strerror(errno));
		return 0;
	}
	return 1;
}

static void
usage(void)
{
	fprintf(stderr, "usage: %s [-e]\n", PROGRAM_NAME);
	fprintf(stderr, "  -e   also log to stderr\n");
	exit(1);
}

int
main(int argc, char **argv)
{
	struct passwd *pw;
	struct pollfd pfd[2];
	int i, c, alive = 1;

	for (i = 0; i < MAX_HANDLES; i++) {
		handles[i].fd = -1;
		handles[i].dir = NULL;
		handles[i].path = NULL;
	}

	while ((c = getopt(argc, argv, "eh")) != -1) {
		switch (c) {
		case 'e':
			log_stderr = 1;
			break;
		case 'h':
		default:
			usage();
		}
	}

	openlog(PROGRAM_NAME, LOG_PID, LOG_DAEMON);

	/* Dropbear gives us a clean, closed-over environment, but be defensive
	 * if something runs this directly: fds 0/1/2 must be open. */
	for (i = 0; i < 3; i++) {
		if (fcntl(i, F_GETFD) == -1)
			(void)open("/dev/null", O_RDWR);
	}
	/* A vanished client writes SIGPIPE at us; that is a normal close. */
	signal(SIGPIPE, SIG_IGN);

	pw = getpwuid(getuid());
	if (pw != NULL && pw->pw_dir != NULL && pw->pw_dir[0] != '\0' &&
	    chdir(pw->pw_dir) < 0) {
		logit("chdir \"%s\" failed: %s", pw->pw_dir, strerror(errno));
		if (chdir("/") < 0)
			logit("chdir \"/\" failed: %s", strerror(errno));
	} else if (pw == NULL || pw->pw_dir == NULL) {
		if (chdir("/") < 0)
			logit("chdir \"/\" failed: %s", strerror(errno));
	}

	logit("session opened for local user %s from %s",
	    pw != NULL ? pw->pw_name : "?", getenv("SSH_CONNECTION") != NULL ?
	    getenv("SSH_CONNECTION") : "unknown");
	verbose_f("%s %s, protocol version %u", PROGRAM_NAME,
	    PROGRAM_VERSION, OUR_SFTP_VERSION);

	/*
	 * One request at a time, with back-pressure: read while the reply
	 * queue has room, write while it has bytes, and stop reading when a
	 * large reply is pending so a client that pipelines requests cannot
	 * deadlock us against its own receive window.
	 */
	while (alive) {
		memset(pfd, 0, sizeof(pfd));
		pfd[0].fd = -1;
		pfd[1].fd = -1;
		if (alive && out.len - out.off < MAX_MSG_LENGTH + 4) {
			pfd[0].fd = STDIN_FILENO;
			pfd[0].events = POLLIN;
		}
		if (out.len > out.off) {
			pfd[1].fd = STDOUT_FILENO;
			pfd[1].events = POLLOUT;
		}
		if (pfd[0].fd < 0 && pfd[1].fd < 0)
			break;			/* nothing left to do */

		if (poll(pfd, 2, -1) < 0) {
			if (errno == EINTR)
				continue;
			logit("poll: %s", strerror(errno));
			cleanup_exit(2);
		}

		if (pfd[0].revents & (POLLIN | POLLHUP))
			alive = read_more();
		if (pfd[1].revents & (POLLOUT | POLLHUP))
			alive = flush_out();
		if (alive && out.len - out.off < MAX_MSG_LENGTH + 4)
			process();
	}

	/* End of stream: drain what is still owed before going away.  Without
	 * this a client that pipelines a last request and then closes its
	 * input loses the reply to it. */
	while (out.len > out.off) {
		if (!flush_out())
			break;
	}

	logit("session closed");
	cleanup_exit(0);
}
