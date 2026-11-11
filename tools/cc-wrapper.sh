#!/bin/bash
# Cross compiler driver: compiles for armv7-apple-ios10.3 with clang and links
# with cctools ld64.  Configured entirely through environment variables:
#
#   IOS_SYSROOT   path to the hand-made sysroot      (required)
#   IOS_LD64      path to x86_64-apple-darwin*-ld    (required)
#   IOS_STUBDIR   dir holding libSystem.tbd          (required)
#   IOS_DYLIBS    extra device dylibs to link, ':'-separated (optional)
#
# Notes learned the hard way:
#   * never force -o: autoconf probes the object suffix and preprocesses to stdout
#   * GNU ar archives are unreadable by ld64; callers must use a Darwin ar
#   * symbols are left undefined on purpose and resolved from the device's
#     libSystem / libncurses at runtime
set -u

REAL_CLANG="${REAL_CLANG:-clang}"
SYSROOT="${IOS_SYSROOT:?IOS_SYSROOT not set}"
LD64="${IOS_LD64:?IOS_LD64 not set}"
STUBDIR="${IOS_STUBDIR:?IOS_STUBDIR not set}"
DYLIBS="${IOS_DYLIBS:-}"

mode_compile=0
for a in "$@"; do case "$a" in -c|-S|-E) mode_compile=1;; esac; done

FRAMEWORKS=()
OUTPUT=a.out; HAS_OUTPUT=0
SRCS=(); OBJS=(); CFLAGS=(); LDARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -c|-S|-E) CFLAGS+=("$1") ;;
    -o) shift; OUTPUT="$1"; HAS_OUTPUT=1 ;;
    *.c|*.cpp|*.cc|*.cxx|*.m|*.mm|*.s|*.S) SRCS+=("$1") ;;
    *.o) [ $mode_compile -eq 1 ] && CFLAGS+=("$1") || OBJS+=("$1") ;;
    *.a|*.dylib|*.tbd) OBJS+=("$1") ;;
    -shared|-dynamiclib) LDARGS+=("-dylib") ;;
    -static) ;;
    -pie) LDARGS+=("-pie") ;;
    -rdynamic) ;;   # GNU: export all; darwin controls exports differently
    -L*) LDARGS+=("$1") ;;
    -lSystem|-lc|-lm|-lpthread|-lutil|-lresolv|-ldl|-lrt|-lintl|\
-lpanel|-lform|-ltinfo|-lncurses|-lncursesw|-lz|-latomic|-lgcc_s|-lgcc)
        ;;                                     # all inside libSystem on Darwin
    -levent|-levent_core|-levent_extra)
        # libevent static archive lives in the build prefix
        LDARGS+=("-L${IOS_PREFIX:-/nonexistent}/lib" "$1") ;;
    -l*) LDARGS+=("$1") ;;                     # ld64 resolves via the -L paths
                                               # (e.g. -lssl -lcrypto with -L.)
    -framework) shift; FRAMEWORKS+=("-framework" "$1"); shift ;;
    -isysroot*) ;;
    -I*|-isystem*) CFLAGS+=("$1") ;;
    -target*|-arch*) ;;
    -platform_version*|-mlinker-version*) ;;
    -Wl,--start-group|-Wl,--end-group) ;;   # GNU-ld grouping: ld64 scans
                                             # archives iteratively anyway
    -Wl,*) LDARGS+=("${1#-Wl,}") ;;
    *) CFLAGS+=("$1") ;;
  esac
  shift
done

if [ -z "$OUTPUT" ] || [ "$OUTPUT" = a.out ]; then
  if [ $mode_compile -eq 1 ] && [ ${#SRCS[@]} -eq 1 ]; then OUTPUT="${SRCS[0]%.*}.o"
  elif [ ${#SRCS[@]} -eq 1 ]; then OUTPUT="${SRCS[0]%.*}"
  else OUTPUT=a.out; fi
fi

TGT=(-target armv7-apple-ios10.3 -isysroot "$SYSROOT")

# __ARM_EABI__ is the GNU/EABI spelling that says "this target follows the
# ARM EABI (AAPCS) procedure-call ABI".  clang does not define it for
# Apple triples -- Apple's toolchains predate the macro and their ABI is
# AAPCS by construction -- but V8's src/codegen/arm/constants-arm.h has a
# hard #error when a 32-bit ARM target lacks it, and Apple's armv7 *is*
# a conformant EABI target.  Defining it here is a statement of fact, not
# a workaround: the whole port rests on the armv7 ABI being EABI.
EARGS=(-D__ARM_EABI__)

if [ $mode_compile -eq 1 ]; then
  if [ $HAS_OUTPUT -eq 1 ]; then
    exec "$REAL_CLANG" "${TGT[@]}" "${EARGS[@]}" "${CFLAGS[@]}" "${SRCS[@]}" -o "$OUTPUT"
  else
    exec "$REAL_CLANG" "${TGT[@]}" "${EARGS[@]}" "${CFLAGS[@]}" "${SRCS[@]}"
  fi
fi

for src in "${SRCS[@]:-}"; do
  [ -z "$src" ] && continue
  obj="${src%.*}.o"
  "$REAL_CLANG" "${TGT[@]}" "${CFLAGS[@]}" -c "$src" -o "$obj" || exit 1
  OBJS+=("$obj")
done

EXTRA=()
IFS=':' read -r -a _libs <<< "$DYLIBS"
for l in "${_libs[@]:-}"; do [ -n "$l" ] && EXTRA+=("$l"); done
# -framework pairs captured during parsing: resolve via the local tbd stub
# dir; at runtime dyld loads the real framework from the shared cache.
if [ "${#FRAMEWORKS[@]}" -gt 0 ]; then
  EXTRA+=("-F$HOME/ios-tool/Frameworks" "${FRAMEWORKS[@]}")
fi

export LD_LIBRARY_PATH="${IOS_LD_LIBRARY_PATH:-}:${LD_LIBRARY_PATH:-}"
exec "$LD64" -arch armv7 -platform_version ios 10.3 10.3 \
  -undefined dynamic_lookup -L"$STUBDIR" -lSystem \
  -e _main -o "$OUTPUT" "${OBJS[@]}" "${EXTRA[@]}" "${LDARGS[@]}"
