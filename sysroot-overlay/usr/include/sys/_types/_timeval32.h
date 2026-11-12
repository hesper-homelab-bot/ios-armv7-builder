/* userland stub: Darwin's 32-bit timeval (two int32 fields on armv7). */
#ifndef _SYS__TYPES__TIMEVAL32_H_
#define _SYS__TYPES__TIMEVAL32_H_
struct timeval32 {
	__int32_t	tv_sec;
	__int32_t	tv_usec;
};
#endif
