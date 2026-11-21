#!/bin/bash
# device-symprobe.sh -- verify symbols against the LIVE device with dlsym and
# append the survivors to the verified-export whitelist.
#
#   tools/device-symprobe.sh _localtime _setvbuf ...      # Mach-O symbol names
#   tools/device-symprobe.sh --dry _localtime             # probe only
#
# Why: check-undefined's whitelist must contain only symbols the device
# actually provides; a CI report of UNRESOLVED names feeds this probe, the
# device answers, and --dry-less runs append the OK set to
# tools/sysroot/device-exports/ios-10.3.3-armv7-verified.txt.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
DRY=0; [ "${1:-}" = "--dry" ] && { DRY=1; shift; }
[ $# -gt 0 ] || { echo "usage: device-symprobe.sh [--dry] <MachO-symbol>..." >&2; exit 2; }

WL="$root/tools/sysroot/device-exports/ios-10.3.3-armv7-verified.txt"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export LD_LIBRARY_PATH="${LD64_LIBS:-$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib}:${LD_LIBRARY_PATH:-}"

# dlsym takes the user-level name (no Mach-O leading underscore) except for
# symbols that genuinely contain leading underscores in C (e.g. __maskrune).
c_name() { case "$1" in ___*) printf '%s' "${1#_}" ;; _*) printf '%s' "${1#_}" ;; *) printf '%s' "$1" ;; esac; }

c=$(mktemp /tmp/symprobe.XXXX.c); b="${c%.c}"
trap 'rm -f "$c" "$b"' EXIT
{
    echo '#include <dlfcn.h>'
    echo '#include <stdio.h>'
    printf 'const char *names[] = {'
    sep=""
    for s in "$@"; do printf '%s"%s"' "$sep" "$(c_name "$s")"; sep=", "; done
    printf '};\n'
    echo 'int main(void){ for (unsigned i=0;i<sizeof(names)/sizeof(*names);i++)'
    echo '  printf("%s %s\n", dlsym(RTLD_DEFAULT, names[i]) ? "OK" : "MISS", names[i]); return 0; }'
} > "$c"

"$CC" "$c" -o "$b" 2>/dev/null
DEVICE="${IPAD_HOST:-ipad}"
scp -q -o BatchMode=yes "$b" "$DEVICE:/var/mobile/.symprobe"
ok=0; miss=0
result=$(ssh -o BatchMode=yes "$DEVICE" "chmod 755 /var/mobile/.symprobe && ldid -S /var/mobile/.symprobe && /var/mobile/.symprobe && rm -f /var/mobile/.symprobe")
while read -r verdict name; do
    # map the user name back to the Mach-O form for the whitelist
    macho="_$name"
    case "$verdict" in
        OK)  echo "OK   $macho"; ok=$((ok+1))
             [ "$DRY" = 0 ] && ! grep -qxF "$macho" "$WL" && echo "$macho" >> "$WL" ;;
        MISS) echo "MISS $macho"; miss=$((miss+1)) ;;
    esac
done <<< "$result"
echo "==> device: $ok OK, $miss MISS$([ "$DRY" = 1 ] && echo ' (dry, whitelist untouched)')"
[ "$miss" = 0 ]
