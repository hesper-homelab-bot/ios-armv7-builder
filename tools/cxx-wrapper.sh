#!/bin/bash
# C++ driver for the armv7 iOS cross build.
#
# Header order matters:
#   1. libc++ headers matched to the device's libc++.1.dylib vintage
#      (LLVM 6.0.1) -- they provide the std::__1 ABI and wrap some C
#      headers via #include_next;
#   2. the sysroot's C headers (explicit -isystem: with -nostdinc++ a
#      custom -isystem dir makes clang skip the implicit sysroot C group
#      for C++ compiles, so headers only present in the sysroot --
#      e.g. xlocale.h -- would not be found).
# -nostdinc++ keeps the host's libstdc++ headers (wrong ABI, std::__cxx1998)
# out; std::__1 symbols resolve from the device's libc++ at launch via
# -undefined dynamic_lookup.
#
# -D_LIBCPP_NO_EXCEPTIONS: the target is iOS 10.3 and V8 is built with
# -fno-exceptions, but the LLVM 15 libc++ headers gate std::optional's
# value() behind _LIBCPP_AVAILABILITY_THROW_BAD_OPTIONAL_ACCESS, i.e.
# "introduced in iOS 12.0" -- because that overload throws
# bad_optional_access.  With no exceptions there is nothing to throw, and
# libc++'s own __availability header handles exactly that case: defining
# _LIBCPP_NO_EXCEPTIONS makes every *_THROW_* availability macro expand to
# nothing.  So this define is not a workaround, it is the configuration the
# headers ask for.
#
# -D_LIBCPP_DISABLE_AVAILABILITY: libc++ marks a lot of otherwise ordinary
# vocabulary types with strict availability -- std::filesystem is "iOS 13.0",
# std::optional::value() is "iOS 12.0" -- because parts of them live in the
# system dylib on Apple platforms.  Our target is iOS 10.3 and we link
# against the device's own libc++ at runtime, so those exact annotations are
# simply wrong here: they reject code that compiles and runs fine.
#
# This is the switch libc++ itself provides for the purpose (see the
# "For backwards compatibility" block at the top of <__availability>); it
# turns off all vendor availability markup.  It is what makes
# node/src/util.h's `std::filesystem::path::preferred_separator` -- a
# compile-time constant -- usable again.
H="${IOS_LIBCXX_HEADERS:-$HOME/ios-tool/libcxx15-headers}"
exec "$HOME/ios-tmux-builder/tools/cc-wrapper.sh" -nostdinc++ -isystem "$H" \
    -isystem "${IOS_SYSROOT:?}/usr/include" \
    -D_LIBCPP_NO_EXCEPTIONS -D_LIBCPP_DISABLE_AVAILABILITY "$@"
