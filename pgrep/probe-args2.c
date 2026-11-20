/*
 * probe-args2.c — 复测 KERN_PROCARGS2(iOS 10.3.3 armv7)。
 * 背景:pgrep 当年结论"KERN_PROCARGS2 连 root 也 ENOENT",但设备自带
 * /bin/ps 能读出 root 进程的完整 argv——结论必错,探针必有 bug。
 * 本探针按 Apple ps(print.c getproclline)的正宗姿势复测:
 *   1. KERN_ARGMAX 取缓冲大小;
 *   2. mib={CTL_KERN, KERN_PROCARGS2, pid} 取参数区;
 *   3. 解析 argc + exec_path + argv 串区。
 * 另测:无 KERN_ARGMAX 预取、固定 4KB 缓冲、KERN_PROCARGS(v1)——定位旧探针死因。
 */
#include <sys/types.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

static void dump_args2(pid_t pid, int tag) {
	int mib[3];
	size_t size = 0;
	int argmax = 0;

	mib[0] = CTL_KERN;
	mib[1] = KERN_ARGMAX;
	size = sizeof(argmax);
	if (sysctl(mib, 2, &argmax, &size, NULL, 0) == -1) {
		printf("[%d] KERN_ARGMAX fail errno=%d\n", tag, errno);
		return;
	}
	printf("[%d] KERN_ARGMAX=%d\n", tag, argmax);

	char *buf = malloc((size_t)argmax);
	mib[0] = CTL_KERN;
	mib[1] = KERN_PROCARGS2;
	mib[2] = pid;
	size = (size_t)argmax;
	if (sysctl(mib, 3, buf, &size, NULL, 0) == -1) {
		printf("[%d] PROCARGS2 pid=%d FAIL errno=%d\n", tag, pid, errno);
		free(buf);
		return;
	}
	int nargs = 0;
	memcpy(&nargs, buf, sizeof(nargs));
	char *cp = buf + sizeof(nargs);
	char *end = buf + size;
	while (cp < end && *cp == '\0') cp++;      /* skip padding */
	char *execpath = cp;
	while (cp < end && *cp) cp++;              /* skip exec_path */
	/* argv strings follow */
	char *argv1 = (cp < end) ? cp + 1 : end;
	printf("[%d] PROCARGS2 pid=%d OK argc=%d exec_path=%s argv0=%s\n",
	    tag, pid, nargs, execpath, argv1);
	free(buf);
}

int main(int argc, char **argv) {
	(void)argc;
	uid_t euid = geteuid();
	printf("euid=%d\n", euid);

	pid_t self = getpid();
	pid_t pid1 = atoi(argv[1]);   /* e.g. dropbear (root-owned) */
	pid_t pid2 = atoi(argv[2]);   /* e.g. SpringBoard (mobile)  */

	dump_args2(self, 1);
	dump_args2(pid1, 2);
	dump_args2(pid2, 3);

	/* 旧探针死因候选 A:固定小缓冲 */
	{
		int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid1 };
		char small[4096];
		size_t size = sizeof(small);
		int rc = sysctl(mib, 3, small, &size, NULL, 0);
		printf("[4] fixed-4k buffer rc=%d errno=%d size=%zu\n", rc, errno, size);
	}
	/* 旧探针死因候选 B:KERN_PROCARGS v1 */
	{
		int mib[3] = { CTL_KERN, KERN_PROCARGS, pid1 };
		char *big = malloc(1 << 20);
		size_t size = 1 << 20;
		int rc = sysctl(mib, 3, big, &size, NULL, 0);
		printf("[5] PROCARGS(v1) rc=%d errno=%d size=%zu\n", rc, errno, size);
		free(big);
	}
	return 0;
}
