#ifndef _COREFOUNDATION_CFTIMEZONE_H_MINIMAL_
#define _COREFOUNDATION_CFTIMEZONE_H_MINIMAL_

/*
 * Minimal CoreFoundation/CFTimeZone.h for the iOS armv7 cross build --
 * just what cctz (abseil time) uses to discover the system time zone:
 * CFTimeZoneCopyDefault / CFTimeZoneGetName / CFStringGetCString.
 *
 * All types are opaque; the functions are resolved at runtime from the
 * CoreFoundation framework in the dyld shared cache (the tbd stub at
 * ~/ios-tool/Frameworks/CoreFoundation.framework/CoreFoundation lists
 * exactly these symbols; verified on device 2026-11-07).
 */

#include <stdint.h>
#include <sys/cdefs.h>

typedef long		CFIndex;
typedef unsigned long	CFStringEncoding;
typedef const void *	CFTypeRef;
typedef const void *	CFStringRef;
typedef const void *	CFTimeZoneRef;

#define kCFStringEncodingUTF8	0x08000100

__BEGIN_DECLS

CFTimeZoneRef	CFTimeZoneCopyDefault(void);
CFStringRef	CFTimeZoneGetName(CFTimeZoneRef tz);
CFIndex		CFStringGetLength(CFStringRef s);
CFIndex		CFStringGetMaximumSizeForEncoding(CFIndex len,
		    CFStringEncoding encoding);
int		CFStringGetCString(CFStringRef s, char *buffer, CFIndex size,
		    CFStringEncoding encoding);
void		CFRelease(CFTypeRef cf);

__END_DECLS

#endif
