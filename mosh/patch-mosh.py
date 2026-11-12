#!/usr/bin/env python3
"""Source patches for the mosh armv7-iOS port.  Idempotent; run with the
mosh source tree as cwd.  See ../build.sh for the full wall list."""

import sys

# ---- 1. early detach (THE most important line of this port) ----
# Termius closes the ssh channel right after reading MOSH CONNECT, and
# dropbear kills the session's process group at that moment: mosh-server
# used to die within milliseconds (ps never saw it), long before the client
# reached the UDP stage.  The upstream detach (the fork()/exit(0) pair in
# mosh-server.cc) does NOT help: its child stays in the same process group.
# OpenSSH happens not to kill the group, which is why upstream never needed
# this.
p = 'src/frontend/mosh-server.cc'
s = open(p).read()
if 'signal( SIGHUP, SIG_IGN );' not in s:
    i = s.index('int main( int argc, char *argv[] )')
    j = s.index('{', i) + 1
    s = s[:j] + '\n  setsid();\n  signal( SIGHUP, SIG_IGN );\n' + s[j:]
    open(p, 'w').write(s)
    print('early detach applied')
else:
    print('early detach: already present')

# ---- 2. locale: iOS has NO locale support at all ----
# setlocale(LC_ALL, "") returns "C" and nl_langinfo(CODESET) returns a
# garbage string ("Sun", probe-verified on an iPad 4 / iOS 10.3.3 -- the
# libSystem langinfo implementation is a stub).  mosh 1.4 refuses to run
# unless is_utf8_locale(); mosh never transcodes server-side, so on Apple
# treat the missing locale as UTF-8.
p = 'src/util/locale_utils.cc'
s = open(p).read()
if '__APPLE__' not in s:
    old = '''    return false;
  }
  return true;
}'''
    new = '''#ifdef __APPLE__
    /* no locale support on iOS; the payload is UTF-8 regardless */
    return true;
#endif
    return false;
  }
  return true;
}'''
    assert old in s, 'locale_utils.cc anchor not found'
    s = s.replace(old, new, 1)
    open(p, 'w').write(s)
    print('locale patch applied')
else:
    print('locale patch: already present')

# ---- 3. zlib headers: mosh includes <zlib.h>; the sysroot carries them
# (installed when libz was cross-built for git).  Nothing to patch here,
# noted for completeness.
print('mosh source patches done')
