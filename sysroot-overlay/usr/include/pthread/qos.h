#ifndef _PTHREAD_QOS_H_
#define _PTHREAD_QOS_H_

/*
 * Minimal <pthread/qos.h> for the iOS armv7 cross build.  QoS class values
 * are the Apple ones (osfmk/... -> pthread/qos.h); V8's platform-posix.cc
 * maps its thread priorities onto them.
 *
 * Verified on device (iPad 4, iOS 10.3.3): pthread_set_qos_class_self_np()
 * is exported by libSystem and returns 0 for QOS_CLASS_BACKGROUND.
 */

typedef unsigned int qos_class_t;

#define QOS_CLASS_USER_INTERACTIVE	((qos_class_t)0x21)
#define QOS_CLASS_USER_INITIATED	((qos_class_t)0x19)
#define QOS_CLASS_DEFAULT		((qos_class_t)0x15)
#define QOS_CLASS_UTILITY		((qos_class_t)0x11)
#define QOS_CLASS_BACKGROUND		((qos_class_t)0x09)
#define QOS_CLASS_UNSPECIFIED		((qos_class_t)0x00)

int	pthread_set_qos_class_self_np(qos_class_t, int);
int	pthread_get_qos_class_np(void *, qos_class_t *, int *);

#endif
