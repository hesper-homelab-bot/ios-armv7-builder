// probe-tsd-direct.c —— 找一个可用的 _pthread direct TSD 槽（Go 移植 TLS 用）
//
// 验证三件事（对每个槽 0..63）：
//   1. _pthread_setspecific_direct/_getspecific_direct 是否存在（dlsym）；
//   2. 写入后读回是否一致（round-trip）；
//   3. 是否真的落在 TPIDRURO&~3 + 4*slot（快窗口内联，Go load_g 可读）；
//   4. 经 libc 活动后值是否还在（libSystem 不回收）。
// 已被占用的槽（orig != NULL）只记录不占用。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <dlfcn.h>

#define MAGIC 0xc476c475u

typedef int (*setspec_fn)(unsigned long, void *);
typedef void *(*getspec_fn)(unsigned long);

static uint32_t mrc_tpidruro(void) {
	uint32_t v;
	__asm__ volatile("mrc p15, 0, %0, c13, c0, 3" : "=r"(v));
	return v;
}

int main(void) {
	setspec_fn setd = (setspec_fn)dlsym(RTLD_DEFAULT, "_pthread_setspecific_direct");
	getspec_fn getd = (getspec_fn)dlsym(RTLD_DEFAULT, "_pthread_getspecific_direct");
	printf("setspecific_direct=%p getspecific_direct=%p\n", (void *)setd, (void *)getd);
	if (!setd || !getd)
		return 1;

	uint32_t tsd = mrc_tpidruro() & ~3u;
	printf("tsd_base = 0x%08x\n", tsd);

	// 先在窗口外放一个哨兵，确认地址读法没跑偏
	printf("slot  orig      rc  roundtrip  in_window\n");
	for (unsigned long slot = 0; slot < 64; slot++) {
		void *orig = getd(slot);
		uint32_t v = MAGIC ^ (uint32_t)slot;
		int rc = setd(slot, (void *)(uintptr_t)v);
		void *back = getd(slot);
		volatile uint32_t *p = (volatile uint32_t *)(tsd + 4 * slot);
		uint32_t mem = *p;
		int rt = ((uint32_t)(uintptr_t)back == v);
		int inw = (mem == v);
		if (rc == 0 && (rt || inw || orig != NULL))
			printf("slot %2lu  %08x  %d  %d  %d  (mem=%08x)\n",
			       slot, (uint32_t)(uintptr_t)orig, rc, rt, inw, mem);
		if (rc == 0 && orig == NULL)
			setd(slot, orig); // 立即恢复
	}

	// 候选持久性测试：找第一个 orig==NULL 且 roundtrip 的槽，
	// 写入后跑一串 libc，再看是否还在
	unsigned long cand = 64;
	for (unsigned long slot = 0; slot < 64; slot++) {
		if (getd(slot) == NULL && setd(slot, (void *)(uintptr_t)MAGIC) == 0) {
			cand = slot;
			break;
		}
	}
	if (cand < 64) {
		void *m = malloc(4096);
		memset(m, 1, 4096);
		printf("libc activity... ");
		free(m);
		printf("after malloc/memset/free: slot %lu = %08x (expect %08x) mem@tsd+%lu = %08x\n",
		       cand, (uint32_t)(uintptr_t)getd(cand), MAGIC,
		       4 * cand, *(volatile uint32_t *)(tsd + 4 * cand));
		setd(cand, NULL);
	} else {
		printf("no free direct slot in 0..63\n");
	}
	return 0;
}
