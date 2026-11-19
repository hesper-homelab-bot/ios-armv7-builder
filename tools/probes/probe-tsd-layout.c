// probe-tsd-layout.c —— 实测 iOS 10.3.3 的 pthread TSD 布局（Go 移植 TLS 用）
//
// 回答三个问题：
//  1. TPIDRURO 与 pthread_self() 的关系；
//  2. pthread_key_create 返回的 key（预期 258，1.14 注释同款）与
//     pthread_setspecific 后 magic 实际落在哪个地址；
//  3. TPIDRURO ±4KB 哪些页可读（映射边界），magic 相对 TPIDRURO 的偏移。
//
// 输出全部走 printf（stdout），部署三件套照旧。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <pthread.h>
#include <unistd.h>

#define MAGIC 0xc476c475u

static sigjmp_buf jb;
static volatile sig_atomic_t faulted;

static void segv_handler(int sig __attribute__((unused))) {
	faulted = 1;
	siglongjmp(jb, 1);
}

static uint32_t mrc_tpidruro(void) {
	uint32_t v;
	__asm__ volatile("mrc p15, 0, %0, c13, c0, 3" : "=r"(v));
	return v;
}

// 安全读一个字：不可读返回 0xffffffff 并标记
static int try_read(uint32_t addr, uint32_t *out) {
	if (sigsetjmp(jb, 1) == 0) {
		faulted = 0;
		*out = *(volatile uint32_t *)addr;
		return faulted ? -1 : 0;
	}
	return -1;
}

int main(void) {
	signal(SIGSEGV, segv_handler);
	signal(SIGBUS, segv_handler);

	uint32_t tp = mrc_tpidruro();
	uint32_t self = (uint32_t)(uintptr_t)pthread_self();
	printf("TPIDRURO      = 0x%08x\n", tp);
	printf("pthread_self  = 0x%08x  (delta=%d)\n", self, (int32_t)(self - tp));

	pthread_key_t k;
	int err = pthread_key_create(&k, NULL);
	printf("key_create err=%d k=%d\n", err, k);

	pthread_setspecific(k, (void *)(uintptr_t)MAGIC);
	void *got = pthread_getspecific(k);
	printf("getspecific   = 0x%08x (expect magic)\n", (uint32_t)(uintptr_t)got);

	// 页映射图：TPIDRURO ±4KB，逐 4KB 页测首字可读性
	printf("readable pages around TPIDRURO (4KB each):\n");
	for (int d = -4; d <= 4; d++) {
		uint32_t page = (tp & ~0xfffu) + d * 0x1000;
		uint32_t v;
		int r = try_read(page, &v);
		printf("  [tp%+#6x] 0x%08x : %s\n", d * 0x1000, page,
		       r == 0 ? "READABLE" : "FAULT");
	}

	// 找 magic：TPIDRURO ±4KB 逐字扫描（只扫可读范围，try_read 保护）
	printf("scanning for magic within tp-4KB..tp+4KB:\n");
	int found = 0;
	for (uint32_t a = (tp & ~3u) - 0x1000; a <= (tp & ~3u) + 0x1000; a += 4) {
		uint32_t v;
		if (try_read(a, &v) == 0 && v == MAGIC) {
			printf("  MAGIC at 0x%08x  (tp%+#x, slot=%d, self%+#x)\n",
			       a, (int32_t)(a - tp), (int32_t)((a - tp) / 4),
			       (int32_t)(a - self));
			found++;
		}
	}
	if (!found)
		printf("  MAGIC NOT FOUND within ±4KB\n");

	// pthread_self ±4KB 也扫一遍
	printf("scanning around pthread_self ±4KB:\n");
	found = 0;
	for (uint32_t a = (self & ~3u) - 0x1000; a <= (self & ~3u) + 0x1000; a += 4) {
		uint32_t v;
		if (try_read(a, &v) == 0 && v == MAGIC) {
			printf("  MAGIC at 0x%08x  (self%+#x, tp%+#x, slot_from_tp=%d)\n",
			       a, (int32_t)(a - self), (int32_t)(a - tp),
			       (int32_t)((a - tp) / 4));
			found++;
		}
	}
	if (!found)
		printf("  MAGIC NOT FOUND around self\n");

	return 0;
}
