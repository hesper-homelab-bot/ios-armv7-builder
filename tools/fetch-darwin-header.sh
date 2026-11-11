#!/bin/bash
# fetch-darwin-header.sh -- get a Darwin header from an authoritative source,
# install it into the sysroot overlay, and check it before it breaks a build.
#
# This is the loop that was repeated by hand ~20 times while porting node,
# tmux, curl, lsof and friends to armv7 iOS 10.3:
#
#     find the header  ->  take the definition from upstream  ->  prove it on
#     the device with a probe
#
# The first two steps are mechanical and are done here.  The third one cannot
# be: only a probe on the actual device settles whether a constant, a struct
# layout or an ioctl number is right, so --probe writes the harness and leaves
# the assertion to you.
#
# ---------------------------------------------------------------------------
# The traps this script exists to prevent
# ---------------------------------------------------------------------------
#
# 1. DARWIN AND LINUX REUSE THE SAME NAMES FOR DIFFERENT VALUES.
#    A constant that "looks obviously right" is the single most expensive
#    mistake in this port.  Measured on the target, not remembered:
#
#        MCAST_JOIN_GROUP      Darwin 80        Linux 42
#        IP_TTL                Darwin 4         Linux 2
#        MAP_ANON              Darwin 0x1000    Linux 0x20
#        MAP_NORESERVE         Darwin 0x40      Linux 0x4000
#        MAP_STACK             Darwin 0x400     Linux 0x2000
#        MAP_MEM_NAMED_CREATE  Darwin 0x20000   (no Linux counterpart)
#        F_GETPATH             Darwin 50        (no Linux counterpart)
#        O_NONBLOCK            Darwin 0x4       Linux 0x800
#        EAGAIN                Darwin 35        Linux 11
#        SOL_SOCKET            Darwin 0xffff    Linux 1
#
#    mmap(2) is the cruel case: it *rejects* unknown flags instead of
#    ignoring them, so a wrong MAP_ANON surfaces as "Bad file descriptor"
#    from a caller three layers away.  Never type a value from memory --
#    --probe exists so the device can be asked.  For values with no local
#    source at all, scan for them: F_GETPATH was recovered by sweeping
#    fcntl numbers 45..55 on the device until F_GETPATH returned the path.
#
# 2. MUSL-STYLE HEADERS BREAK C++ WITH "different language linkage".
#    A header that declares functions without extern "C" is fine in C and a
#    hard error in C++:
#        declaration of 'htonl' has a different language linkage
#        templates must have C++ linkage
#    The working shape, used by every header in the overlay that needs it:
#
#        #ifndef _FOO_H_          <-- guard first
#        #define _FOO_H_
#        #include <sys/types.h>   <-- includes first, OUTSIDE extern "C"
#        #include <stdint.h>      <-- <stdint.h> especially: never inside
#        #ifdef __cplusplus
#        extern "C" {
#        #endif
#        ... declarations ...
#        #ifdef __cplusplus
#        }
#        #endif
#        #endif
#
#    Putting an include inside the extern "C" block pulls libc++'s own
#    headers into C linkage and produces errors that name the *included*
#    header, not this one.  Four overlay headers were fixed this way:
#    stdlib.h, netinet/in.h, unistd.h, termios.h.  The validator below
#    warns when a C++-consumed header has no extern "C" at all.
#
# 3. gyp's `defines` TAKES ONE BLOCK, NOT TWO.
#    Writing a second `defines` key in the same gyp target silently drops the
#    first one -- no warning, no error, the flags simply do not reach the
#    compiler.  Merge them into a single list.  (Not something this script
#    can check; it is here because it cost a full debug cycle.)
#
# 4. THE KERNEL KILLS BINARIES THAT LINK PLATFORM FRAMEWORKS.
#    Any executable with an LC_LOAD_DYLIB pointing at a platform framework
#    (Security, SystemConfiguration, ...) is killed at launch on this device.
#    Proven with tbd-stub probes.  Those frameworks are therefore NOT
#    linkable: the code that needs them must be compiled out, not stubbed.
#    A probe that "fails mysteriously" may be this, not a wrong constant.
#
# ---------------------------------------------------------------------------
# Where headers come from, in priority order
# ---------------------------------------------------------------------------
#
#   1. xnu sparse clone       -- kernel ABI truth (structs, MACH_* flavors)
#   2. Libc clone             -- user-space libc headers as Apple ships them
#   3. cctools foreign/       -- mach/mach-o headers cctools itself needs
#   4. libdispatch clone      -- dispatch/*, os/*
#   5. curl from GitHub       -- raw.githubusercontent.com, exact tag
#
# Kernel ABI always wins over a macOS SDK copy: this device runs
# xnu-3789.70.16 and a newer SDK would be wrong in ways that compile.
#
# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
#
#   ./fetch-darwin-header.sh sys/filio.h                  # show source + text
#   ./fetch-darwin-header.sh mach/thread_info.h --out /tmp/x.h
#   ./fetch-darwin-header.sh sys/event.h --install        # + provenance, sync
#   ./fetch-darwin-header.sh sys/event.h --probe          # probe skeleton
#   ./fetch-darwin-header.sh --explain                    # all of the above
#   ./fetch-darwin-header.sh --verify-only foo/bar.h      # validate in place
#
# Exit status is non-zero if the header could not be found, or if validation
# failed after --install.  A failed validation still leaves the file on disk
# (so you can look at it) but does NOT sync it into the build sysroot.

set -u

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="$(dirname -- "$HERE")"
OVERLAY="$BUILDER/sysroot-overlay/usr/include"
SYSROOT_INC="${IOS_SYSROOT:-$BUILDER/tmp/sysroot}/usr/include"

# Clone locations.  Every one of these can be overridden so the script works
# on a machine whose scratch layout differs.
XNU_DIR="${XNU_DIR:-$HOME/scratch/sysctl-work/xnu}"
LIBC_DIR="${LIBC_DIR:-$HOME/scratch/sysctl-work/libc}"
DISPATCH_DIR="${DISPATCH_DIR:-$HOME/ios-tool/x-libdispatch}"
CCTOOLS_FOREIGN="${CCTOOLS_FOREIGN:-$HOME/ios-tool/cctools-port/cctools/include/foreign}"

# Upstream refs used for the curl fallback.  The xnu tag matches the device
# kernel exactly (uname -v: xnu-3789.70.16~4; the ~n build suffix never
# changes headers).
XNU_TAG="${XNU_TAG:-xnu-3789.70.16}"
LIBC_TAG="${LIBC_TAG:-Libc-1244.30.3}"
DISPATCH_REF="${DISPATCH_REF:-main}"
LIBMALLOC_REF="${LIBMALLOC_REF:-libmalloc-812.100.31}"

GITHUB_RAW="${GITHUB_RAW:-https://raw.githubusercontent.com}"

# curl needs the local proxy on this host; git is configured for it already.
# Override with HDR_CURL_PROXY= if the network is direct.
PROXY="${HDR_CURL_PROXY:-}"
if [ -z "$PROXY" ] && ! curl -sS -o /dev/null --max-time 8 https://raw.githubusercontent.com/ 2>/dev/null; then
    PROXY="socks5h://127.0.0.1:40000"
fi
CURL=(curl -sS --max-time 60 --retry 2)
[ -n "$PROXY" ] && CURL+=(--proxy "$PROXY")

NAME=""; OUT=""; INSTALL=0; PROBE=0; VERIFY_ONLY=0; EXPLAIN=0; FORCE=0
QUIET=0

die()  { printf 'fetch-darwin-header: %s\n' "$*" >&2; exit 2; }
warn() { [ "$QUIET" -eq 1 ] || printf 'fetch-darwin-header: warning: %s\n' "$*" >&2; }
info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*" >&2; }

usage() { sed -n '/^# Usage$/,/^# Exit status/p' "$0" | sed 's/^# \{0,1\}//;$d'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --out)       shift; [ $# -gt 0 ] || die "--out needs a path"; OUT="$1" ;;
        --install)   INSTALL=1 ;;
        --probe)     PROBE=1 ;;
        --verify-only) VERIFY_ONLY=1; shift; [ $# -gt 0 ] || die "--verify-only needs a header name"; NAME="$1" ;;
        --explain)   EXPLAIN=1 ;;
        --force)     FORCE=1 ;;
        --quiet)     QUIET=1 ;;
        -h|--help)   usage; exit 0 ;;
        -*)          die "unknown option: $1 (try --help)" ;;
        *)           [ -z "$NAME" ] || die "only one header at a time"; NAME="$1" ;;
    esac
    shift
done

# A name is a path relative to the sysroot's include dir, and it must stay
# inside it: "../../etc/passwd" would otherwise write outside the overlay.
sanitize_name() {
    local n="$1"
    n="${n#./}"
    case "$n" in
        ""|/*) die "header name must be a relative path like sys/filio.h" ;;
    esac
    case "/$n/" in
        */../*) die "header name must not contain '..': $n" ;;
    esac
    case "$n" in
        *'//'*) die "header name has an empty component: $n" ;;
    esac
    printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# Source resolution
# ---------------------------------------------------------------------------

# SRC_KIND / SRC_DESC / SRC_FILE describe the winner; SRC_CURL is set when the
# content came from the network instead of a local file.
SRC_KIND=""; SRC_DESC=""; SRC_FILE=""; SRC_CURL=""

# 1. xnu sparse clone.  The clone is a partial (--filter=blob:none) sparse
#    checkout, so the file has to be materialised before it can be read.
#    `git sparse-checkout add --skip-checks` finds the cone-mode prefix
#    itself and works for a path a human would not guess; a plain
#    `git checkout -- path` fails with "pathspec did not match" for any path
#    not already in the sparse set.  The lock files are cleaned because an
#    interrupted earlier run leaves them behind and every later git command
#    in that clone then fails with a confusing "Another git process" error.
# xnu lays the public headers out under osfmk/, bsd/ and libkern/, while the
# #include spelling drops that prefix: <mach/boolean.h> is
# osfmk/mach/boolean.h, <sys/filio.h> is bsd/sys/filio.h.  A name is therefore
# resolved by trying the prefixes, and what gets recorded as the source is the
# repo-relative path, not the include spelling.
XNU_PREFIXES=("" "osfmk/" "bsd/" "bsd/netinet6/" "libkern/" "EXTERNAL_HEADERS/" "pexpert/")
XNU_REL=""

# xnu also carries *kernel-internal* copies of headers that user space gets
# from a library instead -- libkern/os/object.h is the kernel's own os_object
# implementation, while user space sees libdispatch's include/os/object.h.
# Both exist and both "look right", so for these names libkern/ is skipped
# and the library source is preferred.
kernel_shadowed() {
    case "$1" in
        os/*) return 0 ;;   # kernel copy: libkern/os/*; user copy: libdispatch
    esac
    return 1
}

try_xnu() {
    local path="$1" repo="$XNU_DIR" cand
    [ -d "$repo/.git" ] || return 1
    XNU_REL=""

    local -a cands=()
    for cand in "${XNU_PREFIXES[@]}"; do
        if [ "$cand" = "libkern/" ] && kernel_shadowed "$path"; then
            continue
        fi
        cands+=("$cand$path")
    done

    # 1. already on disk?
    for cand in "${cands[@]}"; do
        if [ -e "$repo/$cand" ]; then
            SRC_KIND="xnu-sparse"; SRC_FILE="$repo/$cand"; XNU_REL="$cand"
            SRC_DESC="$XNU_DIR [$XNU_TAG] $cand"
            return 0
        fi
    done

    # 2. in the local object database but not checked out?  (The clone is
    #    partial -- blob:none -- so a path can be known and still unreadable.)
    for cand in "${cands[@]}"; do
        if ( cd "$repo" && git cat-file -e "HEAD:$cand" 2>/dev/null ); then
            SRC_KIND="xnu-git-object"; SRC_FILE=""; XNU_REL="$cand"
            SRC_DESC="$XNU_DIR [$XNU_TAG] $cand (via git cat-file)"
            return 0
        fi
    done

    # 3. materialise it.  `git sparse-checkout add --skip-checks` is the only
    #    form that works for a path a human would not guess: cone mode works
    #    out the parent prefix itself, whereas `git checkout -- path` fails
    #    with "pathspec did not match any file(s) known to git" for anything
    #    outside the current sparse set -- which reads as "this header is not
    #    in that tag", the most misleading possible answer.
    #    The locks are cleared first because an interrupted run leaves them
    #    behind and then *every* later git command in that clone fails with
    #    "Another git process seems to be running".
    rm -f "$repo/.git/index.lock" "$repo/.git/info/sparse-checkout.lock"
    for cand in "${cands[@]}"; do
        ( cd "$repo" && timeout 150 git sparse-checkout add --skip-checks "$cand" ) >/dev/null 2>&1
        if [ -e "$repo/$cand" ]; then
            SRC_KIND="xnu-sparse"; SRC_FILE="$repo/$cand"; XNU_REL="$cand"
            SRC_DESC="$XNU_DIR [$XNU_TAG] $cand"
            return 0
        fi
        # A wrong guess can leave a dead entry in the sparse set; drop it so
        # repeated lookups do not accumulate junk.
        if ( cd "$repo" && git sparse-checkout list 2>/dev/null | grep -qxF "$cand" ); then
            ( cd "$repo" && git sparse-checkout remove --skip-checks "$cand" ) >/dev/null 2>&1
        fi
    done
    info "  xnu: $path not in $XNU_DIR (not in $XNU_TAG, or not fetched)"
    return 1
}

# 2. Libc clone -- same shape, but Libc is a full-ish clone; try the working
#    tree, then the object database, then a shallow blob fetch.
try_libc() {
    local path="$1" repo="$LIBC_DIR"
    [ -d "$repo/.git" ] || return 1
    LIBC_REL=""
    local cand
    for cand in "$path" "include/$path"; do
        if [ -e "$repo/$cand" ]; then
            SRC_KIND="libc-clone"; SRC_FILE="$repo/$cand"; LIBC_REL="$cand"
            SRC_DESC="$LIBC_DIR [$LIBC_TAG] $cand"
            return 0
        fi
        if ( cd "$repo" && git cat-file -e "HEAD:$cand" 2>/dev/null ); then
            SRC_KIND="libc-git-object"; SRC_FILE=""; LIBC_REL="$cand"
            SRC_DESC="$LIBC_DIR [$LIBC_TAG] $cand (via git cat-file)"
            return 0
        fi
    done
    return 1
}

# 3. cctools' foreign include dir: the mach/mach-o headers cctools needs,
#    which are also a usable stand-in for a few Apple private headers.
#
#    BUT: cctools ships deliberate placeholder files whose entire content is
#    the comment "//fake headers".  Installing one of those into the overlay
#    produces a header that defines nothing, and the failure then shows up as
#    "unknown type name" hundreds of lines into some other file.  They are
#    rejected here rather than trusted.
try_cctools() {
    local path="$1" f="$CCTOOLS_FOREIGN/$1"
    [ -d "$CCTOOLS_FOREIGN" ] || return 1
    [ -f "$f" ] || return 1
    if is_stub_header "$f"; then
        info "  cctools: $f is a '$STUB_MARKER' placeholder, not a header; skipping"
        return 1
    fi
    SRC_KIND="cctools-foreign"; SRC_FILE="$f"
    SRC_DESC="$CCTOOLS_FOREIGN/$path"
    return 0
}

STUB_MARKER='//fake headers'
# A file is a cctools placeholder if, ignoring blank lines and comments, it
# has effectively no content -- or if it literally carries the marker.
is_stub_header() {
    local f="$1"
    grep -qF "$STUB_MARKER" "$f" && return 0
    local code
    code="$(grep -vE '^[[:space:]]*(/\*|\*|//|$)' "$f" | grep -cvE '^[[:space:]]*\*/?[[:space:]]*$' || true)"
    [ "$code" -eq 0 ] && return 0
    return 1
}

# 4. libdispatch checkout (dispatch/*, os/*).
try_dispatch() {
    local path="$1" repo="$DISPATCH_DIR"
    [ -d "$repo" ] || return 1
    local cand
    for cand in "$repo/include/$path" "$repo/$path"; do
        if [ -f "$cand" ]; then
            SRC_KIND="libdispatch"; SRC_FILE="$cand"
            SRC_DESC="$cand [$DISPATCH_REF]"
            return 0
        fi
    done
    return 1
}

# 5. curl fallback.  Sets SRC_CURL to the URL that answered 200.  The repo
#    list is ordered by how authoritative each is for a given subtree:
#    kernel/mach headers from xnu, dispatch/os from libdispatch, libc from
#    Libc, malloc/* from libmalloc.
try_curl() {
    local path="$1" url
    local -a urls=(
        "$GITHUB_RAW/apple-oss-distributions/xnu/$XNU_TAG/$path"
        "$GITHUB_RAW/apple-oss-distributions/Libc/$LIBC_TAG/$path"
        "$GITHUB_RAW/apple-oss-distributions/Libc/$LIBC_TAG/include/$path"
        "$GITHUB_RAW/apple/swift-corelibs-libdispatch/$DISPATCH_REF/$path"
        "$GITHUB_RAW/apple/swift-corelibs-libdispatch/$DISPATCH_REF/include/$path"
        "$GITHUB_RAW/apple-oss-distributions/libmalloc/$LIBMALLOC_REF/include/$path"
        "$GITHUB_RAW/apple-oss-distributions/libmalloc/$LIBMALLOC_REF/$path"
    )
    for url in "${urls[@]}"; do
        if "${CURL[@]}" -f -o /dev/null "$url" 2>/dev/null; then
            SRC_CURL="$url"; SRC_KIND="github-raw"; SRC_FILE=""
            SRC_DESC="$url"
            return 0
        fi
    done
    info "  github: no repo answered for '$path'"
    info "          (xnu $XNU_TAG, Libc $LIBC_TAG, libdispatch $DISPATCH_REF, libmalloc $LIBMALLOC_REF)"
    return 1
}

resolve_header() {
    local path="$1"
    SRC_KIND=""; SRC_DESC=""; SRC_FILE=""; SRC_CURL=""
    info "resolving '$path':"
    try_xnu "$path"      && return 0
    try_libc "$path"     && return 0
    try_cctools "$path"  && return 0
    try_dispatch "$path" && return 0
    try_curl "$path"     && return 0
    info "  not found in any source."
    info "  If it is an Apple *private* header, the corresponding public"
    info "  definition may live in cctools' foreign tree; if it is an SDK"
    info "  header that never shipped in an open-source release, take the"
    info "  layout from a minimal hand-written overlay file and VERIFY it"
    info "  with --probe -- the kernel does not read your header, it reads"
    info "  the numbers you compiled in."
    return 1
}

# Emit the winning source to stdout (or SRC_FILE is empty for curl/objects).
emit_source() {
    if [ -n "$SRC_FILE" ]; then
        cat -- "$SRC_FILE"
        return 0
    fi
    if [ -n "$SRC_CURL" ]; then
        "${CURL[@]}" -f "$SRC_CURL"
        return $?
    fi
    # git-object kinds: recover the path and the repo from the description
    case "$SRC_KIND" in
        xnu-git-object)
            ( cd "$XNU_DIR" && git cat-file -p "HEAD:${XNU_REL:-$1}" ) ;;
        libc-git-object)
            ( cd "$LIBC_DIR" && git cat-file -p "HEAD:${LIBC_REL:-$1}" ) ;;
    esac
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

# Constants that exist on Linux and NOT on Darwin.  If one of these turns up
# in a header being installed, the header was copied from the wrong system --
# a musl header with an Apple name, or an Apple header from a different libc.
# The check is deliberately noisy about names only: a legitimate comment that
# mentions Linux is fine, a #define of SIGPWR is not.
LINUX_ONLY_NAMES=(
    SIGPWR SIGSTKFLT SIGPOLL SIGCLD
    sendmmsg recvmmsg process_vm_readv
    EPOLLIN EPOLLET EPOLL_CTL_ADD signalfd eventfd timerfd_create
    linux_banner SO_PEERCRED PR_SET_NAME
    __NR_io_uring_setup IPPROTO_MPLS
)

# Name used on BOTH systems with DIFFERENT values.  Matching on the name
# alone cannot tell right from wrong, so the Darwin value is checked where it
# can be stated unambiguously; where it cannot, the file is flagged for a
# device probe.  Values below are the measured Darwin ones.
check_known_values() {
    local file="$1" rc=0 lineno val

    # name:Darwin-value  -- grep for the name, then read the number after it.
    local -a pairs=(
        "MCAST_JOIN_GROUP:80"
        "IP_TTL:4"
        "IP_MULTICAST_TTL:10"
        "F_GETPATH:50"
        "MAP_MEM_NAMED_CREATE:0x20000"
    )
    local pair name want got
    for pair in "${pairs[@]}"; do
        name="${pair%%:*}"; want="${pair##*:}"
        # only lines that #define the name at all
        if grep -qE "^[[:space:]]*#[[:space:]]*define[[:space:]]+$name([[:space:]]|$)" "$file"; then
            got="$(grep -E "^[[:space:]]*#[[:space:]]*define[[:space:]]+$name([[:space:]]|$)" "$file" \
                   | head -1 | sed -E "s/.*$name[[:space:]]+//; s/[[:space:]]*(\/\*|\/\/).*$//; s/[[:space:]]+$//")"
            if [ "$got" != "$want" ]; then
                lineno="$(grep -nE "^[[:space:]]*#[[:space:]]*define[[:space:]]+$name([[:space:]]|$)" "$file" | head -1 | cut -d: -f1)"
                printf '  FAIL %s:%s  %s is %s, Darwin says %s\n' "$file" "$lineno" "$name" "$got" "$want" >&2
                rc=1
            fi
        fi
    done
    return $rc
}

validate_header() {
    local file="$1" name="$2" rc=0
    [ -f "$file" ] || { printf '  FAIL %s does not exist\n' "$file" >&2; return 1; }

    # --- include guard pairing -------------------------------------------
    # The naive count is what catches the real failure mode: a header whose
    # #endif was lost when it was trimmed, which then swallows the rest of
    # every translation unit that includes it.
    local opens closes
    opens="$(grep -cE '^[[:space:]]*#[[:space:]]*(if|ifdef|ifndef)([[:space:]]|$)' "$file" || true)"
    closes="$(grep -cE '^[[:space:]]*#[[:space:]]*endif([[:space:]]|$)' "$file" || true)"
    if [ "$opens" != "$closes" ]; then
        printf '  FAIL %s: preprocessor blocks unbalanced: %s #if/#ifdef/#ifndef vs %s #endif\n' \
            "$file" "$opens" "$closes" >&2
        printf '       (a lost #endif makes every includer swallow the rest of the file)\n' >&2
        rc=1
    fi
    if ! grep -qE '^[[:space:]]*#[[:space:]]*ifndef[[:space:]]' "$file"; then
        printf '  FAIL %s: no include guard (#ifndef) at all\n' "$file" >&2
        rc=1
    fi

    # --- __has_include-style nesting sanity -------------------------------
    # An #endif with a trailing comment naming a different guard than the
    # #ifndef that opened it means two guards were merged carelessly.
    local head_guard tail_guard
    head_guard="$(grep -m1 -E '^[[:space:]]*#[[:space:]]*ifndef[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" \
                  | sed -E 's/.*ifndef[[:space:]]+//; s/[[:space:]].*//' || true)"
    tail_guard="$(grep -E '^[[:space:]]*#[[:space:]]*endif.*\*/' "$file" | tail -1 \
                  | sed -E 's@.*/\*[[:space:]]*(![[:space:]]*)?([A-Za-z_][A-Za-z0-9_]*).*@\2@' || true)"
    if [ -n "$head_guard" ] && [ -n "$tail_guard" ] && [ "$head_guard" != "$tail_guard" ]; then
        warn "$name: file opens guard '$head_guard' but the last #endif is commented '$tail_guard'"
    fi

    # --- extern "C" -------------------------------------------------------
    # A C++-visible header (anything under the overlay that declares
    # functions) must be C-linkage-safe.  mach/* and machine/* are pure
    # typedef/#define headers and are exempt.
    if ! grep -q 'extern "C"' "$file"; then
        case "$name" in
            mach/*|machine/*|*/machine/*|TargetConditionals.h|Availability.h|AvailabilityMacros.h)
                : ;;   # declarations-free, or macros only: nothing to wrap
            *)
                if grep -qE '^[[:space:]]*(extern[[:space:]]+)?[A-Za-z_][A-Za-z0-9_[:space:]\*]*\([^;]*\)[[:space:]]*;' "$file"; then
                    printf '  FAIL %s: declares functions but has no extern "C": a C++ consumer gets\n' "$file" >&2
                    printf '       "declaration of X has a different language linkage" against libc++ headers.\n' >&2
                    printf '       Shape: includes (incl. <stdint.h>) first OUTSIDE the block, then one\n' >&2
                    printf '       extern "C" { ... } around every declaration.\n' >&2
                    rc=1
                else
                    warn "$name: no extern \"C\" (no function declarations found, so probably fine)"
                fi
                ;;
        esac
    else
        # includes inside the extern "C" block are the subtler version of
        # the same bug: they pull libc++ into C linkage.
        local first_c first_inc
        first_c="$(grep -n 'extern "C"' "$file" | head -1 | cut -d: -f1)"
        first_inc="$(grep -nE '^[[:space:]]*#[[:space:]]*include' "$file" | head -1 | cut -d: -f1)"
        if [ -n "$first_c" ] && [ -n "$first_inc" ] && [ "$first_inc" -gt "$first_c" ]; then
            local after
            after="$(awk -v c="$first_c" 'NR>c && /^[[:space:]]*#[[:space:]]*include/ {print NR": "$0; exit}' "$file")"
            if [ -n "$after" ]; then
                warn "$name: include appears inside extern \"C\" (line ${after%%:*}): ${after#*: }"
                warn "  includes belong before the block; <stdint.h> especially"
            else
                warn "$name: extern \"C\" precedes the first include; check ordering"
            fi
        fi
    fi

    # --- Linux-only names -------------------------------------------------
    local sym
    for sym in "${LINUX_ONLY_NAMES[@]}"; do
        if grep -qE "^[[:space:]]*#[[:space:]]*define[[:space:]]+$sym([[:space:]]|$)" "$file"; then
            local ln
            ln="$(grep -nE "^[[:space:]]*#[[:space:]]*define[[:space:]]+$sym([[:space:]]|$)" "$file" | head -1 | cut -d: -f1)"
            printf '  FAIL %s:%s defines %s, which does not exist on Darwin.\n' "$file" "$ln" "$sym" >&2
            printf '       This header came from a Linux libc. Check the source before installing.\n' >&2
            rc=1
        fi
    done

    # --- same-name/different-value constants ------------------------------
    check_known_values "$file" || rc=1

    return $rc
}

# ---------------------------------------------------------------------------
# Provenance block and installation
# ---------------------------------------------------------------------------

provenance_block() {
    local name="$1" desc="$2" kind="$3"
    local ref="" repo=""
    case "$kind" in
        xnu-*)        ref="$XNU_TAG";  repo="https://github.com/apple-oss-distributions/xnu" ;;
        libc-*)       ref="$LIBC_TAG"; repo="https://github.com/apple-oss-distributions/Libc" ;;
        libdispatch)  ref="$DISPATCH_REF"; repo="https://github.com/apple/swift-corelibs-libdispatch" ;;
        github-raw)
            case "$desc" in
                *xnu*)       ref="$XNU_TAG";  repo="https://github.com/apple-oss-distributions/xnu" ;;
                *Libc*)      ref="$LIBC_TAG"; repo="https://github.com/apple-oss-distributions/Libc" ;;
                *libdispatch*) ref="$DISPATCH_REF"; repo="https://github.com/apple/swift-corelibs-libdispatch" ;;
                *libmalloc*) ref="$LIBMALLOC_REF"; repo="https://github.com/apple-oss-distributions/libmalloc" ;;
            esac ;;
        cctools-foreign)
            ref="cctools-port"; repo="https://github.com/tpoechtrager/cctools-port" ;;
    esac

    cat <<EOF
/*
 * <$name> for the iOS armv7 cross build.
 *
 * source:   $desc
EOF
    [ -n "$repo" ] && printf ' * repo:     %s\n' "$repo"
    [ -n "$ref" ]  && printf ' * tag/ref:  %s\n' "$ref"
    cat <<EOF
 * fetched:  $(date -u '+%Y-%m-%dT%H:%M:%SZ') by tools/fetch-darwin-header.sh
 *
 * why:      <why the sysroot needs this header; which program includes it>
 *
 * [verified] <how this was proven on the device, or "unverified">
 *            e.g. probe prints MCAST_JOIN_GROUP=80, matches Darwin docs
 *
 * Numbers in this file are Darwin ABI.  Do not "fix" one to match a Linux
 * value seen in musl or glibc: the same name means something else there.
 */
EOF
}

sync_overlay() {
    if [ ! -d "$SYSROOT_INC" ]; then
        warn "build sysroot $SYSROOT_INC does not exist; skipping rsync"
        return 0
    fi
    # --include/--exclude, never `cp -r`: an unset or mistyped source
    # variable once turned this into copying / into the sysroot.
    rsync -a --include='*/' --include='*.h' --exclude='*' \
        "$OVERLAY/" "$SYSROOT_INC/" || die "rsync to $SYSROOT_INC failed"
    info "synced overlay -> $SYSROOT_INC"
}

# ---------------------------------------------------------------------------
# Probe skeleton
# ---------------------------------------------------------------------------

write_probe() {
    local name="$1" out="$2"
    local base sym
    base="$(basename "$name" .h)"
    # A plausible symbol to assert on: the guard name is a decent hint, but a
    # human has to fill this in.  Probes are intentionally minimal so the
    # device run is fast (scp + ssh, no build system).
    cat > "$out" <<EOF
/*
 * Probe for <$name> -- run on the device, not on the host.
 *
 * A header that compiles proves nothing: every number in it is just an int
 * to clang.  What has to be checked is the value the KERNEL uses, and the
 * only way to see it is to ask the device.  Fill in the asserts below, then:
 *
 *   export LD64="\$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld"
 *   export LD_LIBRARY_PATH="\$HOME/ios-tool/x-libdispatch/lib:\$HOME/ios-tool/x-tapi/lib:\$LD_LIBRARY_PATH"
 *   export IOS_SYSROOT="\$HOME/ios-tmux-builder/tmp/sysroot"
 *   export IOS_LD64="\$LD64"
 *   export IOS_STUBDIR="\$HOME/ios-tool"
 *   \$HOME/ios-tmux-builder/tools/cc-wrapper.sh $(basename "$out") -o ${base}-probe
 *   ldid -S ${base}-probe
 *   scp -q ${base}-probe ipad:/var/mobile/scratch/ && \\
 *       ssh ipad '/var/mobile/scratch/${base}-probe; echo rc=\$?'
 *
 * Rules learned the hard way:
 *   - constants must be measured, never remembered (MCAST_JOIN_GROUP is 80
 *     on Darwin and 42 on Linux; IP_TTL is 4 and 2);
 *   - a value with no local source can be found by scanning the device
 *     (F_GETPATH came out of a sweep over fcntl numbers 45..55);
 *   - if the probe dies instantly with no output, suspect an LC_LOAD_DYLIB
 *     referencing a platform framework: the kernel kills such binaries.
 *     Do not link Security/SystemConfiguration; compile that code out.
 */
#include <$name>
#include <stdio.h>
#include <string.h>
#include <errno.h>

int main(void)
{
    int failures = 0;

    /* ---- constants: assert the Darwin value ---------------------------- */
#ifdef ${base^^}_PROBE_CONSTANT
    printf("${base^^}_PROBE_CONSTANT = %d\n", (int)${base^^}_PROBE_CONSTANT);
#endif

    /* ---- struct layout: print sizes/offsets, compare with xnu ---------- */
    /* printf("sizeof(struct X) = %zu\n", sizeof(struct X)); */

    /* ---- functions: call it and print errno on failure ----------------- */
    /* errno = 0; ... if (errno) { printf("failed: %s\n", strerror(errno)); failures++; } */

    printf("%s: probe incomplete -- fill in the assertions above\n", "$name");
    (void)failures;
    return failures ? 1 : 0;
}
EOF
    info "probe skeleton written to $out"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

[ -n "$NAME" ] || { usage; exit 2; }
# An existing file path is taken as-is (verify-only); otherwise the name must
# be a sysroot-relative path that cannot escape the overlay.
if [ "$VERIFY_ONLY" -eq 1 ] && [ -f "$NAME" ]; then
    :
else
    NAME="$(sanitize_name "$NAME")"
fi

if [ "$VERIFY_ONLY" -eq 1 ]; then
    # An explicit path (or a file outside the overlay) is validated as given:
    # that is how the validator itself is tested, and how a header that is
    # still being drafted can be checked before it is installed.
    if [ -f "$NAME" ]; then
        target="$NAME"
    else
        target="$OVERLAY/$NAME"
    fi
    [ -f "$target" ] || die "no such header: $target"
    info "validating $target"
    if validate_header "$target" "$NAME"; then
        info "  ok"
        exit 0
    fi
    exit 1
fi

resolve_header "$NAME" || exit 1
info "  source: $SRC_KIND"
info "  $SRC_DESC"

# get the bytes into a temp file we control
TMP="$(mktemp "${TMPDIR:-/tmp}/fdh.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
case "$SRC_KIND" in
    xnu-git-object)  ( cd "$XNU_DIR"  && git cat-file -p "HEAD:${XNU_REL:-$NAME}" )                 > "$TMP" || die "git cat-file failed" ;;
    libc-git-object) ( cd "$LIBC_DIR" && git cat-file -p "HEAD:${LIBC_REL:-include/$NAME}" )         > "$TMP" || die "git cat-file failed" ;;
    *)               emit_source "$NAME" > "$TMP" || die "could not read source" ;;
esac
[ -s "$TMP" ] || die "source is empty"

if [ "$INSTALL" -eq 0 ]; then
    if [ -n "$OUT" ]; then
        cat "$TMP" > "$OUT" || die "cannot write $OUT"
        info "  written to $OUT"
    else
        cat "$TMP"
    fi
    if [ "$PROBE" -eq 1 ]; then
        write_probe "$NAME" "${OUT:-$(basename "$NAME")}.probe.c" >&2
        info "  (probe written next to the header text)"
    fi
    exit 0
fi

# --install: provenance header, then the verbatim body.
DEST="$OVERLAY/$NAME"
mkdir -p "$(dirname "$DEST")"
if [ -e "$DEST" ] && [ "$FORCE" -eq 0 ]; then
    # Never clobber a header by accident: these are hand-checked files and
    # several carry notes that upstream does not have.
    if cmp -s "$TMP" "$DEST"; then
        info "  $DEST already matches this source; nothing to do"
        exit 0
    fi
    die "$DEST exists and differs from the fetched source; re-run with --force to overwrite"
fi

{
    provenance_block "$NAME" "$SRC_DESC" "$SRC_KIND"
    cat "$TMP"
} > "$DEST.tmp.$$" || die "cannot write $DEST"
mv -f "$DEST.tmp.$$" "$DEST"

info "installed $DEST"

if validate_header "$DEST" "$NAME"; then
    info "validation: ok"
    sync_overlay
    if [ "$PROBE" -eq 1 ]; then
        write_probe "$NAME" "$BUILDER/../scratch/hdr-workflow-test/$(basename "$NAME").probe.c" 2>/dev/null \
          || write_probe "$NAME" "${TMPDIR:-/tmp}/$(basename "$NAME").probe.c"
    fi
    info "next: fill in the provenance '[verified]' field after probing."
    exit 0
else
    printf 'fetch-darwin-header: validation FAILED for %s\n' "$DEST" >&2
    printf '  The file was written (so you can inspect it) but NOT synced into %s.\n' "$SYSROOT_INC" >&2
    printf '  Fix the header, then re-run: %s --verify-only %s\n' "$0" "$NAME" >&2
    exit 1
fi
