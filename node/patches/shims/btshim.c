/*
 * btshim.c — backtrace()/backtrace_symbols() for the iPad4 (armv7, iOS 10.3.3).
 *
 * The device libSystem has neither symbol. Node calls backtrace() from its own
 * fatal-error printer (debug_utils.cc DumpBacktrace); with the symbol missing,
 * dyld kills the error printer itself ("Symbol not found: __Z9backtracePPvi")
 * and the real fatal message is lost — which cost us hours during the
 * snapshot-blob walls.
 *
 * Implementation: walk the AAPCS frame-pointer chain (r7 on arm32). Node and
 * V8 are built with frame pointers, so this recovers real return addresses.
 * backtrace_symbols() cannot resolve names in a stripped binary; it returns
 * raw "0x%08x" strings, which we symbolize on the host with the unstripped
 * twin (docs/toolchain.md §5).
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { void *fp; void *sp; void *lr; void *pc; } probe_frame_ctx;

int backtrace(void **buffer, int size) {
    if (buffer == NULL || size <= 0) return 0;
    int n = 0;
    /* __builtin_frame_address(0) = current r7. Each frame: {fp, sp, lr, pc}. */
    void **fp = (void **)__builtin_frame_address(0);
    /* Bound the walk: stop at NULL, at non-word-aligned fp, or after 512 hops. */
    for (int i = 0; i < 512 && n < size; i++) {
        void *next_fp = fp[0];
        void *lr = fp[2];
        /* Chain sanity: fp must be word-aligned and monotonically increasing
         * within the same stack (rough upper bound: within 64MB above us). */
        if (next_fp == NULL) break;
        if (((uintptr_t)next_fp & 0x3) != 0) break;
        if ((uintptr_t)next_fp <= (uintptr_t)fp) break;
        if ((uintptr_t)next_fp - (uintptr_t)fp > (64u << 20)) break;
        if (lr != NULL && n < size) buffer[n++] = lr;
        fp = (void **)next_fp;
    }
    return n;
}

char **backtrace_symbols(void *const *buffer, int size) {
    if (buffer == NULL || size <= 0) return NULL;
    /* One block: char*[size+1] + one "0x%08x\n"-ish string per entry. */
    char **out = (char **)malloc((size_t)(size + 1) * sizeof(char *) +
                                 (size_t)size * 32);
    if (out == NULL) return NULL;
    char *strbase = (char *)(out + size + 1);
    for (int i = 0; i < size; i++) {
        out[i] = strbase + (size_t)i * 32;
        snprintf(out[i], 32, "0x%08llx",
                 (unsigned long long)(uintptr_t)buffer[i]);
    }
    out[size] = NULL;
    return out;
}
