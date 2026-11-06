#!/usr/bin/env python3
"""Protocol-level negative tests for db-sftp-server.

Runs the server binary with stdin/stdout on pipes (dropbear does the same
thing) and speaks the raw SFTP message layer, so error paths a real client
never exercises can be checked.
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile

SSH_FXP_INIT, SSH_FXP_VERSION = 1, 2
SSH_FXP_OPEN, SSH_FXP_CLOSE, SSH_FXP_READ, SSH_FXP_WRITE = 3, 4, 5, 6
SSH_FXP_LSTAT, SSH_FXP_FSTAT, SSH_FXP_SETSTAT, SSH_FXP_FSETSTAT = 7, 8, 9, 10
SSH_FXP_OPENDIR, SSH_FXP_READDIR, SSH_FXP_REMOVE, SSH_FXP_MKDIR = 11, 12, 13, 14
SSH_FXP_RMDIR, SSH_FXP_REALPATH, SSH_FXP_STAT, SSH_FXP_RENAME = 15, 16, 17, 18
SSH_FXP_READLINK, SSH_FXP_SYMLINK = 19, 20
SSH_FXP_STATUS, SSH_FXP_HANDLE, SSH_FXP_DATA, SSH_FXP_NAME, SSH_FXP_ATTRS = \
    101, 102, 103, 104, 105
SSH_FXP_EXTENDED, SSH_FXP_EXTENDED_REPLY = 200, 201

FX_OK, FX_EOF, FX_NO_SUCH_FILE, FX_PERMISSION_DENIED, FX_FAILURE = 0, 1, 2, 3, 4
FX_BAD_MESSAGE, FX_NO_CONNECTION, FX_CONNECTION_LOST, FX_OP_UNSUPPORTED = \
    5, 6, 7, 8
FX_INVALID_HANDLE, FX_NO_SUCH_PATH, FX_FILE_ALREADY_EXISTS = 9, 10, 11

FXF_READ, FXF_WRITE, FXF_APPEND, FXF_CREAT, FXF_TRUNC, FXF_EXCL = 1, 2, 4, 8, 16, 32
ATTR_SIZE, ATTR_UIDGID, ATTR_PERMISSIONS, ATTR_ACMODTIME = 1, 2, 4, 8

FAILURES = []


def check(cond, what):
    if cond:
        print("  ok   %s" % what)
    else:
        print("  FAIL %s" % what)
        FAILURES.append(what)


class Client:
    def __init__(self, binary, cwd):
        self.cwd = cwd
        self.p = subprocess.Popen([binary], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, cwd=cwd)
        self.id = 0
        # The server chdirs to its user's home at startup (as OpenSSH's
        # does), so a bare "name" in a request resolves against that home,
        # not against the directory this test happens to run in.
        self.root = "/home/hesper"

    def abspath(self, path):
        if path.startswith("/"):
            return path
        return self.root + "/" + path

    def send(self, payload):
        self.p.stdin.write(struct.pack(">I", len(payload)) + payload)
        self.p.stdin.flush()

    def recv(self):
        hdr = self._read(4)
        n = struct.unpack(">I", hdr)[0]
        return self._read(n)

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.p.stdout.read(n - len(buf))
            if not chunk:
                raise EOFError("server closed the stream")
            buf += chunk
        return buf

    def request(self, msg_type, fields):
        """A request is type(1), id(4), then the type's own fields."""
        self.id += 1
        self.send(bytes([msg_type]) + struct.pack(">I", self.id) + fields)
        return self.recv()

    # -- individual requests -------------------------------------------------
    def init(self, version=3):
        self.id += 1
        self.send(bytes([SSH_FXP_INIT]) + struct.pack(">I", version))
        msg = self.recv()
        typ = msg[0]
        ver = struct.unpack(">I", msg[1:5])[0]
        exts = []
        rest = msg[5:]
        while len(rest) >= 4:
            ln = struct.unpack(">I", rest[:4])[0]
            exts.append(rest[4:4 + ln].decode())
            rest = rest[4 + ln:]
        return typ, ver, exts

    def _path(self, path):
        b = path.encode()
        return struct.pack(">I", len(b)) + b

    def _string(self, b):
        return struct.pack(">I", len(b)) + b

    def _u32(self, v):
        return struct.pack(">I", v)

    def _u64(self, v):
        return struct.pack(">Q", v)

    def open(self, path, flags=FXF_READ | FXF_WRITE | FXF_CREAT, mode=0o644):
        payload = self._path(self.abspath(path)) + self._u32(flags)
        if mode is not None:
            payload += self._u32(ATTR_PERMISSIONS) + self._u32(mode)
        else:
            payload += self._u32(0)
        msg = self.request(SSH_FXP_OPEN, payload)
        return self._reply(msg)

    def opendir(self, path):
        msg = self.request(SSH_FXP_OPENDIR, self._path(self.abspath(path)))
        return self._reply(msg)

    def readdir(self, handle):
        msg = self.request(SSH_FXP_READDIR, self._string(handle))
        return self._reply(msg)

    def closedir(self, handle):
        msg = self.request(SSH_FXP_CLOSE, self._string(handle))
        return self._reply(msg)

    def read(self, handle, off, ln):
        payload = self._string(handle) + self._u64(off) + self._u32(ln)
        msg = self.request(SSH_FXP_READ, payload)
        return self._reply(msg)

    def write(self, handle, off, data):
        payload = self._string(handle) + self._u64(off) + self._string(data)
        msg = self.request(SSH_FXP_WRITE, payload)
        return self._reply(msg)

    def fstat(self, handle):
        msg = self.request(SSH_FXP_FSTAT, self._string(handle))
        return self._reply(msg)

    def realpath(self, path):
        msg = self.request(SSH_FXP_REALPATH, self._path(self.abspath(path)))
        return self._reply(msg)

    def stat(self, path):
        msg = self.request(SSH_FXP_STAT, self._path(self.abspath(path)))
        return self._reply(msg)

    def lstat(self, path):
        msg = self.request(SSH_FXP_LSTAT, self._path(self.abspath(path)))
        return self._reply(msg)

    def mkdir(self, path):
        msg = self.request(SSH_FXP_MKDIR, self._path(self.abspath(path)) +
                           self._u32(ATTR_PERMISSIONS) + self._u32(0o755))
        return self._reply(msg)

    def rmdir(self, path):
        msg = self.request(SSH_FXP_RMDIR, self._path(self.abspath(path)))
        return self._reply(msg)

    def remove(self, path):
        msg = self.request(SSH_FXP_REMOVE, self._path(self.abspath(path)))
        return self._reply(msg)

    def setstat(self, path, flags=ATTR_ACMODTIME, atime=1000000, mtime=1000000,
                perm=None):
        payload = self._path(self.abspath(path)) + self._u32(flags)
        if flags & ATTR_SIZE:
            payload += self._u64(0)
        if flags & ATTR_UIDGID:
            payload += self._u32(0) + self._u32(0)
        if flags & ATTR_PERMISSIONS:
            payload += self._u32(perm if perm is not None else 0)
        if flags & ATTR_ACMODTIME:
            payload += self._u32(atime) + self._u32(mtime)
        msg = self.request(SSH_FXP_SETSTAT, payload)
        return self._reply(msg)

    def fsetstat(self, handle, size=None, mtime=1000000):
        flags = 0
        payload = self._string(handle)
        if size is not None:
            flags |= ATTR_SIZE
        flags |= ATTR_ACMODTIME
        payload += self._u32(flags)
        if size is not None:
            payload += self._u64(size)
        payload += self._u32(1000000) + self._u32(mtime)
        msg = self.request(SSH_FXP_FSETSTAT, payload)
        return self._reply(msg)

    def symlink(self, old, new):
        msg = self.request(SSH_FXP_SYMLINK, self._path(self.abspath(old)) +
                           self._path(self.abspath(new)))
        return self._reply(msg)

    def readlink(self, path):
        msg = self.request(SSH_FXP_READLINK, self._path(self.abspath(path)))
        return self._reply(msg)

    def rename(self, old, new):
        msg = self.request(SSH_FXP_RENAME, self._path(self.abspath(old)) +
                           self._path(self.abspath(new)))
        return self._reply(msg)

    def extended(self, name, data=b""):
        """data is the raw, already-encoded field list for the request."""
        payload = self._path(name) + data
        msg = self.request(SSH_FXP_EXTENDED, payload)
        return self._reply(msg)

    def close(self, handle):
        msg = self.request(SSH_FXP_CLOSE, self._string(handle))
        return self._reply(msg)

    def _reply(self, msg):
        """Minimal reply parser: returns (type, rest)."""
        if len(msg) < 5:
            return (None, None)
        return (msg[0], msg[5:])


def status_of(typ, rest):
    if typ == SSH_FXP_STATUS:
        return struct.unpack(">I", rest[:4])[0], rest[8:].split(b"\0")[0]
    return (None, b"")


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else "./sftp-server"
    tmp = tempfile.mkdtemp(prefix="sftpsrv-")
    c = Client(binary, tmp)

    print("== init")
    typ, ver, exts = c.init()
    check(typ == SSH_FXP_VERSION, "INIT answered with VERSION")
    check(ver == 3, "protocol version 3 (got %d)" % ver)
    print("     extensions: %s" % exts)

    print("== realpath")
    typ, rest = c.realpath(".")
    count = struct.unpack(">I", rest[:4])[0]
    nln = struct.unpack(">I", rest[4:8])[0]
    resolved = rest[8:8 + nln].decode()
    check(typ == SSH_FXP_NAME and count == 1 and resolved.startswith("/"),
          "realpath returns one resolved absolute path")
    print("     -> %s" % resolved)

    print("== negative paths")
    typ, rest = c.lstat("/no/such/file")
    check(status_of(typ, rest)[0] == FX_NO_SUCH_FILE,
          "lstat of a missing file -> NO_SUCH_FILE")
    typ, rest = c.remove("/no/such/file")
    check(status_of(typ, rest)[0] == FX_NO_SUCH_FILE,
          "remove of a missing file -> NO_SUCH_FILE")
    typ, rest = c.opendir("/no/such/dir")
    check(status_of(typ, rest)[0] == FX_NO_SUCH_FILE,
          "opendir of a missing dir -> NO_SUCH_FILE")
    typ, rest = c.mkdir(tmp)
    check(status_of(typ, rest)[0] == FX_FILE_ALREADY_EXISTS,
          "mkdir of an existing dir -> FILE_ALREADY_EXISTS")
    typ, rest = c.open("/no/such/file", FXF_READ)
    check(status_of(typ, rest)[0] == FX_NO_SUCH_FILE,
          "open of a missing file -> NO_SUCH_FILE")
    typ, rest = c.read(b"bogus", 0, 10)
    check(status_of(typ, rest)[0] == FX_INVALID_HANDLE,
          "read with an unknown handle -> INVALID_HANDLE")
    typ, rest = c.readdir(b"bogus")
    check(status_of(typ, rest)[0] == FX_INVALID_HANDLE,
          "readdir with an unknown handle -> INVALID_HANDLE")

    print("== file round trip")
    h = None
    # READ|WRITE, exactly as an sftp client uploading and then downloading
    # would ask for it: a WRITE-only handle cannot be read (pread fails with
    # EBADF), which the protocol reports as NO_SUCH_FILE just like upstream.
    typ, rest = c.open("payload.bin", FXF_READ | FXF_WRITE | FXF_CREAT | FXF_TRUNC)
    if typ == SSH_FXP_HANDLE:
        hlen = struct.unpack(">I", rest[:4])[0]
        h = rest[4:4 + hlen]
    check(typ == SSH_FXP_HANDLE and h, "open with CREAT|TRUNC -> HANDLE")
    data = bytes(range(256)) * 40          # 10240 bytes, more than one window
    for off in range(0, len(data), 1024):
        typ, rest = c.write(h, off, data[off:off + 1024])
        check(status_of(typ, rest)[0] == FX_OK, "write at %d -> OK" % off)
    typ, rest = c.read(h, 0, 10240)
    check(typ == SSH_FXP_DATA, "read -> DATA")
    ln = struct.unpack(">I", rest[:4])[0]
    got = rest[4:4 + ln]
    check(got == data[:10240], "read back %d bytes identical" % ln)
    check(len(got) == 10240, "single read returned the full %d bytes" % len(got))
    typ, rest = c.read(h, len(data), 16)
    check(status_of(typ, rest)[0] == FX_EOF, "read at EOF -> EOF")
    typ, rest = c.fsetstat(h, size=512)
    check(status_of(typ, rest)[0] == FX_OK, "fsetstat size -> OK")
    typ, rest = c.fstat(h)
    flags = struct.unpack(">I", rest[:4])[0]
    size = struct.unpack(">Q", rest[4:12])[0] if flags & ATTR_SIZE else -1
    check(typ == SSH_FXP_ATTRS and size == 512,
          "fstat reports the truncated size (got %d)" % size)
    typ, rest = c.close(h)
    check(status_of(typ, rest)[0] == FX_OK, "close -> OK")

    print("== 300-entry directory (chunked readdir)")
    big = os.path.join(c.root, "big")
    shutil.rmtree(big, ignore_errors=True)
    os.mkdir(big)
    for i in range(300):
        open(os.path.join(big, "e%03d" % i), "w").close()
    dh = None
    typ, rest = c.opendir("big")
    if typ == SSH_FXP_HANDLE:
        hlen = struct.unpack(">I", rest[:4])[0]
        dh = rest[4:4 + hlen]
    check(typ == SSH_FXP_HANDLE and dh, "opendir -> HANDLE")
    names, rounds = [], 0
    while True:
        typ, rest = c.readdir(dh)
        rounds += 1
        if typ == SSH_FXP_STATUS:
            check(status_of(typ, rest)[0] == FX_EOF, "readdir ends with EOF")
            break
        if typ != SSH_FXP_NAME:
            check(False, "readdir -> NAME")
            break
        count = struct.unpack(">I", rest[:4])[0]
        p = rest[4:]
        for _ in range(count):
            ln = struct.unpack(">I", p[:4])[0]
            names.append(p[4:4 + ln])
            q = p[4 + ln:]
            ln2 = struct.unpack(">I", q[:4])[0]
            q = q[4 + ln2:]
            aflags = struct.unpack(">I", q[:4])[0]
            q = q[4:]
            if aflags & ATTR_SIZE:
                q = q[8:]
            if aflags & ATTR_UIDGID:
                q = q[8:]
            if aflags & ATTR_PERMISSIONS:
                q = q[4:]
            if aflags & ATTR_ACMODTIME:
                q = q[8:]
            if aflags & 0x80000000:
                ext = struct.unpack(">I", q[:4])[0]
                q = q[4:]
                for _ in range(ext):
                    ln3 = struct.unpack(">I", q[:4])[0]
                    q = q[4 + ln3:]
                    ln3 = struct.unpack(">I", q[:4])[0]
                    q = q[4 + ln3:]
            p = q
        print("     round %d: %d names, message %d bytes" % (rounds, count, len(rest) + 4))
        if rounds > 10:
            check(False, "readdir did not terminate")
            break
    print("     collected %d names in %d requests" % (len(names), rounds))
    # readdir also returns "." and ".." -- OpenSSH's sftp-server does too.
    check(len(names) == 302 and set(names) - {b".", b".."} ==
          set(("e%03d" % i).encode() for i in range(300)),
          "300 entries read across %d requests (plus . and ..)" % rounds)
    check(rounds >= 4, "readdir was chunked (%d requests)" % rounds)
    typ, rest = c.closedir(dh)
    check(status_of(typ, rest)[0] == FX_OK, "closedir -> OK")

    print("== empty directory")
    shutil.rmtree(os.path.join(c.root, "empty"), ignore_errors=True)
    os.mkdir(os.path.join(c.root, "empty"))
    typ, rest = c.opendir("empty")
    hlen = struct.unpack(">I", rest[:4])[0]
    dh = rest[4:4 + hlen]
    typ, rest = c.readdir(dh)
    count = struct.unpack(">I", rest[:4])[0] if typ == SSH_FXP_NAME else 0
    names = []
    if typ == SSH_FXP_NAME and count:
        q = rest[4:]
        for _ in range(count):
            ln = struct.unpack(">I", q[:4])[0]
            names.append(q[4:4 + ln])
            q = q[4 + ln:]
            ln2 = struct.unpack(">I", q[:4])[0]
            names_long = q[4:4 + ln2]
            q = q[4 + ln2:]
            aflags = struct.unpack(">I", q[:4])[0]
            q = q[4:]
            if aflags & ATTR_SIZE: q = q[8:]
            if aflags & ATTR_UIDGID: q = q[8:]
            if aflags & ATTR_PERMISSIONS: q = q[4:]
            if aflags & ATTR_ACMODTIME: q = q[8:]
    check(typ == SSH_FXP_NAME and set(names) == {b".", b".."},
          "an empty directory lists only . and .. (as OpenSSH does)")
    typ, rest = c.readdir(dh)
    check(typ == SSH_FXP_STATUS and status_of(typ, rest)[0] == FX_EOF,
          "readdir on empty dir ends with EOF")

    print("== symlinks and hard links")
    for stale in ("link1", "link2.bin", "renamed.bin", "payload.bin"):
        try:
            os.remove(os.path.join(c.root, stale))
        except FileNotFoundError:
            pass
    typ, rest = c.open("payload.bin", FXF_READ | FXF_WRITE | FXF_CREAT)
    typ, rest = c.symlink("payload.bin", "link1")
    check(status_of(typ, rest)[0] == FX_OK, "symlink -> OK")
    typ, rest = c.lstat("link1")
    aflags = struct.unpack(">I", rest[:4])[0]
    q = rest[4:]
    if aflags & ATTR_SIZE:
        q = q[8:]
    if aflags & ATTR_UIDGID:
        q = q[8:]
    perm = struct.unpack(">I", q[:4])[0] if aflags & ATTR_PERMISSIONS else 0
    check(typ == SSH_FXP_ATTRS and perm & 0o170000 == 0o120000,
          "lstat reports S_IFLNK for a symlink")
    typ, rest = c.readlink("link1")
    count = struct.unpack(">I", rest[:4])[0]
    tln = struct.unpack(">I", rest[4:8])[0]
    target = rest[8:8 + tln]
    check(typ == SSH_FXP_NAME and count == 1 and
          target == b"/home/hesper/payload.bin",
          "readlink returns the target")
    typ, rest = c.readlink(c.abspath("payload.bin"))
    check(typ == SSH_FXP_STATUS,
          "readlink of a non-symlink -> error status, not a bogus name")
    typ, rest = c.extended("hardlink@openssh.com",
                           c._string(c.abspath("payload.bin").encode()) +
                           c._string(c.abspath("link2.bin").encode()))
    check(status_of(typ, rest)[0] == FX_OK, "hardlink extension -> OK")
    st1 = os.stat(os.path.join(c.root, "payload.bin"))
    st2 = os.stat(os.path.join(c.root, "link2.bin"))
    check(st1.st_ino == st2.st_ino, "hard link shares the inode")
    typ, rest = c.extended("statvfs@openssh.com")
    check(status_of(typ, rest)[0] == FX_OP_UNSUPPORTED,
          "unadvertised extension -> OP_UNSUPPORTED")

    print("== timestamps and mode")
    typ, rest = c.setstat("payload.bin", ATTR_ACMODTIME, 1000000, 1234567)
    check(status_of(typ, rest)[0] == FX_OK, "setstat times -> OK")
    st = os.stat(os.path.join(c.root, "payload.bin"))
    check(int(st.st_mtime) == 1234567, "mtime is what the client asked for")
    typ, rest = c.setstat("payload.bin", ATTR_PERMISSIONS, perm=0o600)
    check(status_of(typ, rest)[0] == FX_OK, "setstat mode -> OK")
    check(os.stat(os.path.join(c.root, "payload.bin")).st_mode & 0o777 == 0o600,
          "mode is what the client asked for")

    print("== rename and removal")
    typ, rest = c.rename("payload.bin", "renamed.bin")
    check(status_of(typ, rest)[0] == FX_OK, "rename -> OK")
    check(os.path.exists(os.path.join(c.root, "renamed.bin")), "renamed file exists")
    typ, rest = c.remove("renamed.bin")
    check(status_of(typ, rest)[0] == FX_OK, "remove -> OK")

    print("== pipelined requests (out-of-order replies)")
    # Two opens back to back: the server must answer both, in order, without
    # the input queue growing a request into the previous one.
    c.id += 1
    c.send(bytes([SSH_FXP_OPEN]) + struct.pack(">I", c.id + 1) +
           c._path(c.abspath("a1")) + c._u32(FXF_WRITE | FXF_CREAT) +
           c._u32(ATTR_PERMISSIONS) + c._u32(0o600))
    c.id += 1
    c.send(bytes([SSH_FXP_OPEN]) + struct.pack(">I", c.id + 1) +
           c._path(c.abspath("a2")) + c._u32(FXF_WRITE | FXF_CREAT) +
           c._u32(ATTR_PERMISSIONS) + c._u32(0o600))
    c.id += 1
    t1, r1 = c._reply(c.recv())
    t2, r2 = c._reply(c.recv())
    check(t1 == SSH_FXP_HANDLE and t2 == SSH_FXP_HANDLE,
          "both pipelined opens answered in order")

    print("== long names and nesting")
    deep = os.path.join(c.root, "a/b/c")
    shutil.rmtree(os.path.join(c.root, "a"), ignore_errors=True)
    os.makedirs(deep)
    longname = "z" * 200 + ".txt"
    open(os.path.join(deep, longname), "w").write("deep")
    typ, rest = c.opendir("a/b/c")
    hlen = struct.unpack(">I", rest[:4])[0]
    dh = rest[4:4 + hlen]
    typ, rest = c.readdir(dh)
    nlen = struct.unpack(">I", rest[4:8])[0] if typ == SSH_FXP_NAME else -1
    got = rest[8:8 + nlen] if typ == SSH_FXP_NAME else b""
    check(typ == SSH_FXP_NAME and nlen == 204 and got.decode() == longname,
          "200+ character name survives readdir intact")

    c.p.stdin.close()
    rc = c.p.wait(timeout=10)
    check(rc == 0, "server exits 0 on stdin EOF (rc=%d)" % rc)

    print("")
    if FAILURES:
        print("%d FAILURE(S)" % len(FAILURES))
        for f in FAILURES:
            print("  - %s" % f)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
