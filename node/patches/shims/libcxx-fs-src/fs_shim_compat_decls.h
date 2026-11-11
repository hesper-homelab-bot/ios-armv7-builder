// fs-shim: declarations missing from the hand-made iOS 10.3 sysroot headers.
// Included via -include on the compiler command line; each entry must also be
// verified as exported by the device's libSystem before it is trusted.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int unlinkat(int, const char *, int);
#ifdef __cplusplus
}
#endif
