#ifndef _NOTIFY_H_
#define _NOTIFY_H_

/*
 * <notify.h> -- Darwin's notify(3) publish/subscribe mechanism, used by
 * c-ares to watch network-configuration changes (ares_event_configchg.c)
 * and by libuv on Linux for a different reason (that file is not ours).
 *
 * Symbols verified on device (iPad 4, iOS 10.3.3, 2026-11-07):
 * notify_register_dispatch() resolved and returned NOTIFY_STATUS_FAILED
 * (1000000) for a NULL queue -- i.e. the entry point is live, the call
 * was simply malformed.
 */

#include <stdint.h>
#include <sys/cdefs.h>

__BEGIN_DECLS

typedef int notify_token;

/* status codes (the ones a caller here can actually see) */
#define NOTIFY_STATUS_OK		0
#define NOTIFY_STATUS_INVALID_NAME	1
#define NOTIFY_STATUS_INVALID_TOKEN	3
#define NOTIFY_STATUS_INVALID_PORT	6
#define NOTIFY_STATUS_FAILED		1000000

int	notify_post(const char *name);
int	notify_register_dispatch(const char *name, int *out_token,
	    void *queue, void *handler);
int	notify_register_check(const char *name, int *out_token);
/*
 * File-descriptor registration: verified working on device (rc=0, fd=3,
 * token=1 for "com.apple.system.networkd.settings"), which is what c-ares
 * uses to watch network-config changes without a dispatch queue.
 */
int	notify_register_file_descriptor(const char *name, int *out_fd,
	    int flags, int *out_token);
int	notify_register_signal(const char *name, int sig, int *out_token);
int	notify_register_mach_port(const char *name, void *port, int flags,
	    int *out_token);
int	notify_check(int token, int *check);
int	notify_cancel(int token);
int	notify_get_state(int token, uint64_t *state);
int	notify_set_state(int token, uint64_t state);

__END_DECLS

#endif
