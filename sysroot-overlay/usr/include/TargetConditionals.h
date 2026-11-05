/*
 * Minimal TargetConditionals.h for the cross sysroot.
 * The target is an armv7 iOS device (not simulator, not macOS).
 */
#ifndef _TARGETCONDITIONALS_H
#define _TARGETCONDITIONALS_H

#define TARGET_OS_MAC          1
#define TARGET_OS_IPHONE       1
#define TARGET_OS_IOS          1
#define TARGET_OS_WATCH        0
#define TARGET_OS_TV           0
#define TARGET_OS_OSX          0
#define TARGET_OS_VISION       0
#define TARGET_OS_BRIDGE       0
#define TARGET_OS_SIMULATOR    0
#define TARGET_OS_EMBEDDED     1

#define TARGET_CPU_ARM         1
#define TARGET_CPU_ARM64       0
#define TARGET_CPU_X86         0
#define TARGET_CPU_X86_64      0

#define TARGET_RT_LITTLE_ENDIAN 1
#define TARGET_RT_BIG_ENDIAN    0
#define TARGET_RT_64_BIT        0

#endif
