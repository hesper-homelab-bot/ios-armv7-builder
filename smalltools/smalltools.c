/*
 * smalltools.c — tree / watch / realpath / hexdump, one binary four names.
 *
 * These were the last small file utilities missing on the device (probed
 * 2026-11-20: patch/xxd/hexdump/watch/realpath/tree absent; xxd actually
 * ships with vim under tools/bin but PATH-hidden).  argv[0] dispatch keeps
 * it one deb; /usr/bin symlinks expose the four names.
 *
 * Everything is deliberately dependency-free C (SDK sysroot mode): tree and
 * hexdump are hand-rolled, watch just execs the command in a loop, realpath
 * wraps the SDK's realpath(3) (confirmed present).
 */
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ tree */

static int opt_all, opt_dirs_only, opt_depth = 32;
static int dir_count, file_count;

/* Recursive listing with ├── └── glyphs; returns nothing, prints in place. */
static void
walk(const char *path, const char *prefix, int depth)
{
	struct dirent **names;
	int n, i;

	if (depth > opt_depth)
		return;
	n = scandir(path, &names, NULL, alphasort);
	if (n < 0) {
		printf("%s[error: %s]\n", prefix, strerror(errno));
		return;
	}
	for (i = 0; i < n; i++) {
		const char *name = names[i]->d_name;
		struct stat st;
		char sub[4096];
		int is_dir, last;

		if (!opt_all && name[0] == '.')
			goto next;
		if (!strcmp(name, ".") || !strcmp(name, ".."))
			goto next;
		snprintf(sub, sizeof(sub), "%s%s%s", path,
		    path[strlen(path) - 1] == '/' ? "" : "/", name);
		is_dir = (lstat(sub, &st) == 0 && S_ISDIR(st.st_mode));
		if (opt_dirs_only && !is_dir)
			goto next;
		last = (i == n - 1);
		while (i + 1 < n) {	/* skip to real last emitted entry */
			const char *nx = names[i + 1]->d_name;
			int nx_dir;
			char sub2[4096];
			if (!opt_all && nx[0] == '.') { i++; goto next; }
			snprintf(sub2, sizeof(sub2), "%s%s%s", path,
			    path[strlen(path) - 1] == '/' ? "" : "/", nx);
			nx_dir = (lstat(sub2, &st) == 0 && S_ISDIR(st.st_mode));
			if (!opt_dirs_only || nx_dir)
				break;
			i++;
		}
		last = (i == n - 1);
		printf("%s%s-- %s\n", prefix, last ? "`" : "|", name);
		if (is_dir) {
			char subprefix[4096];
			snprintf(subprefix, sizeof(subprefix), "%s%s   ",
			    prefix, last ? " " : "|");
			dir_count++;
			walk(sub, subprefix, depth + 1);
			continue;
		}
		file_count++;
next:
		free(names[i]);
	}
	free(names);
}

static int
do_tree(int argc, char **argv)
{
	int ch, i;
	const char *start = ".";

	while ((ch = getopt(argc, argv, "aL:")) != -1) {
		switch (ch) {
		case 'a': opt_all = 1; break;
		case 'd': opt_dirs_only = 1; break;
		case 'L': opt_depth = atoi(optarg); break;
		default:
			fprintf(stderr, "usage: tree [-a] [-d] [-L depth] [dir]\n");
			return 1;
		}
	}
	argc -= optind;
	argv += optind;
	if (argc > 0)
		start = argv[0];
	printf("%s\n", start);
	walk(start, "", 1);
	printf("\n%d directories, %d files\n", dir_count, file_count);
	return 0;
}

/* ----------------------------------------------------------------- watch */

static int
do_watch(int argc, char **argv)
{
	double interval = 2.0;
	int ch;
	char cmd[4096];
	size_t o = 0;
	int i;

	while ((ch = getopt(argc, argv, "n:")) != -1) {
		if (ch == 'n')
			interval = atof(optarg);
		else {
			fprintf(stderr, "usage: watch [-n seconds] command\n");
			return 1;
		}
	}
	argc -= optind;
	argv += optind;
	if (argc < 1) {
		fprintf(stderr, "usage: watch [-n seconds] command\n");
		return 1;
	}
	for (i = 0; i < argc; i++)
		o += (size_t)snprintf(cmd + o, sizeof(cmd) - o, "%s%s",
		    i ? " " : "", argv[i]);
	for (;;) {
		printf("\033[2J\033[H");	/* clear + home */
		printf("Every %.1fs: %s\n\n", interval, cmd);
		fflush(stdout);
		(void)system(cmd);
		usleep((useconds_t)(interval * 1000000.0));
	}
	/* not reached */
	return 0;
}

/* -------------------------------------------------------------- realpath */

static int
do_realpath(int argc, char **argv)
{
	int ch, i, rc = 0;

	while ((ch = getopt(argc, argv, "")) != -1)
		;
	argc -= optind;
	argv += optind;
	if (argc < 1) {
		fprintf(stderr, "usage: realpath path ...\n");
		return 1;
	}
	for (i = 0; i < argc; i++) {
		char resolved[4096];
		if (realpath(argv[i], resolved) == NULL) {
			fprintf(stderr, "realpath: %s: %s\n", argv[i], strerror(errno));
			rc = 1;
			continue;
		}
		printf("%s\n", resolved);
	}
	return rc;
}

/* --------------------------------------------------------------- hexdump */

static int
do_hexdump(int argc, char **argv)
{
	FILE *f = stdin;
	int ch, i;
	unsigned char line[16];
	size_t len = 0;
	unsigned long offset = 0;

	if (argc > 2) {
		fprintf(stderr, "usage: hexdump [file]\n");
		return 1;
	}
	if (argc == 2) {
		f = fopen(argv[1], "rb");
		if (f == NULL) {
			fprintf(stderr, "hexdump: %s: %s\n", argv[1], strerror(errno));
			return 1;
		}
	}
	while ((ch = fgetc(f)) != EOF) {
		line[len++] = (unsigned char)ch;
		if (len == 16) {
			printf("%08lx ", offset);
			for (i = 0; i < 16; i++)
				printf(i == 8 ? " %02x" : " %02x", line[i]);
			printf("  |");
			for (i = 0; i < 16; i++)
				putchar(line[i] >= 0x20 && line[i] < 0x7f ? line[i] : '.');
			printf("|\n");
			offset += 16;
			len = 0;
		}
	}
	if (len) {
		printf("%08lx ", offset);
		for (i = 0; i < 16; i++)
			printf(i < (int)len ? (i == 8 ? " %02x" : " %02x") : "   ",
			    i < (int)len ? line[i] : 0);
		printf("  |");
		for (i = 0; i < (int)len; i++)
			putchar(line[i] >= 0x20 && line[i] < 0x7f ? line[i] : '.');
		printf("|\n");
	}
	if (f != stdin)
		fclose(f);
	return 0;
}

/* ------------------------------------------------------------------ main */

int
main(int argc, char **argv)
{
	const char *base = strrchr(argv[0], '/');

	base = base ? base + 1 : argv[0];
	if (!strcmp(base, "tree"))		return do_tree(argc, argv);
	if (!strcmp(base, "watch"))		return do_watch(argc, argv);
	if (!strcmp(base, "realpath"))		return do_realpath(argc, argv);
	if (!strcmp(base, "hexdump"))		return do_hexdump(argc, argv);
	if (!strcmp(base, "smalltools")) {
		fprintf(stderr, "usage: invoke as tree|watch|realpath|hexdump "
		    "(argv[0] dispatch)\n");
		return 2;
	}
	fprintf(stderr, "smalltools: unknown name %s\n", base);
	return 2;
}
