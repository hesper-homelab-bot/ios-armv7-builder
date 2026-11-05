/*
 * nocablewarn - suppress the "This accessory may not be supported"
 * (可能不支持此配件) alert on jailbroken iOS 10.
 *
 * -[SBUIController setIsConnectedToUnsupportedChargingAccessory:] is what
 * SpringBoard calls (with YES) when a non-MFi charging accessory is plugged
 * in; the flag drives the SBAlertItem with the localized
 * UNSUPPORTED_CHARGING_ACCESSORY string.  Force the setter to always write
 * NO and neither the notification nor the alert can ever trigger.
 *
 * (An earlier build scanned all classes with objc_copyClassList, which
 * aborted the ObjC runtime on this device - the class is now hard-coded.)
 */
/* libobjc.A.dylib exports; the musl-based sysroot has no objc headers */
extern void  *objc_getClass(const char *name);
extern void  *sel_registerName(const char *str);
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/time.h>

extern void MSHookMessageEx(void *cls, void *sel, void *imp, void **result);

static void (*orig_set)(void *, void *, signed char);

static void
note(const char *msg)
{
	int fd = open("/var/mobile/Library/nocablewarn.log",
	    O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd >= 0) {
		write(fd, msg, strlen(msg));
		close(fd);
	}
}

static void
my_set(void *self, void *_cmd, signed char value)
{
	char buf[128];
	struct timeval tv;

	gettimeofday(&tv, NULL);
	(void)snprintf(buf, sizeof buf,
	    "hooked: set(%s) suppressed at %ld.%06ld\n",
	    value ? "YES" : "NO", (long)tv.tv_sec, (long)tv.tv_usec);
	note(buf);
	orig_set(self, _cmd, 0);
}

__attribute__((constructor))
static void
nocablewarn_init(void)
{
	void *cls = objc_getClass("SBUIController");
	void *sel = sel_registerName("setIsConnectedToUnsupportedChargingAccessory:");

	if (cls == NULL) {
		note("constructor: SBUIController NOT found\n");
		return;
	}
	MSHookMessageEx(cls, sel, (void *)my_set, (void **)&orig_set);
	note("constructor: SBUIController hooked OK\n");
}
