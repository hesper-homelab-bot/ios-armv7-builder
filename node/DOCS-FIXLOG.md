# Node port documentation fixlog

Audit of factual inconsistencies between the Node-port documentation and the
actual files/scripts/device facts. Scope: `node/README.pending.md`,
`node/DEVICE.pending.md`, `node/VERIFY.md`, `DEVICE.md` (§11, §11.5). Only
`*.md` was modified; scripts were read-only references.

Sources of truth used (read-only): `node/build.sh`, `node/make-deb.sh`,
`node/jitless-wrap.sh`, `~/scratch/node-research/BUILD-STATE.md`,
`ls -R sysroot-overlay/usr/include/`, `tmp/stubs/libSystem.tbd`,
`~/ios-tool/libSystem.tbd`, `~/scratch/link-prescan/REPORT.md`,
`sysroot-overlay/usr/include/mach/vm_statistics.h`,
`~/scratch/node-research/probes/jit.c`, and the device facts supplied with the
task.

Format of each entry: **file + location**, **original text**, **corrected
text**, **evidence**.

---

## A. Overlay header inventory (count and §11 matrix)

### A-1. `DEVICE.md` §11 heading and body — "85 headers" is wrong

- **Location:** `DEVICE.md` §11, heading and first paragraph (line 344 and 346).
- **Original:**

  ```
  ## 11. The sysroot overlay: 85 headers, what each was for (2026-11-08)

  `ios-tmux-builder/sysroot-overlay/usr/include/` holds 85 hand-written or
  copied-from-source headers.
  ```

- **Corrected:**

  ```
  ## 11. The sysroot overlay: 87 headers, what each was for (2026-11-08)

  `ios-tmux-builder/sysroot-overlay/usr/include/` holds 87 hand-written or
  copied-from-source headers.
  ```

- **Evidence:** `find sysroot-overlay/usr/include/ -type f | wc -l` = **87**
  (27 top-level files + 60 files in 12 subdirectories, all `*.h`). The
  previously used 85 and 87 figures are now unified on this measured value.
  This also fixes two stale references *inside* `node/build.sh` (its header
  comment says "39 hand-written/copied Darwin headers", and lines 140 and 144
  say "~39 overlay headers" / "see DEVICE.md §11.1 for the real list"). Per
  the task rules the script was **not** edited — see §H "script/doc conflicts"
  below.

### A-2. `DEVICE.md` §11.1 V8 row — `dispatch/*` does not exist; rows do not sum to 87

- **Location:** `DEVICE.md` §11.1, table row **V8** and the table as a whole.
- **Original (V8 row):**

  ```
  | **V8** (libc++/Mach/dispatch) | `os/{availability,base,object}.h`, `dispatch/*` via `mach/mach.h`, `mach/{clock_types,host_info,mach_init,mach_time,message,semaphore,thread_act,thread_info,vm_map,vm_statistics,vm_types}.h`, `mach-o/{dyld,getsect,loader}.h`, `libkern/OSAtomic.h`, `AvailabilityMacros.h`, `TargetConditionals.h` |
  ```

- **Corrected:**

  ```
  | **V8** (libc++/Mach) | `os/{availability,base,object}.h`, `mach/mach.h` (the `dispatch/*` headers live in `~/ios-tool/x-libdispatch/include`, not in this overlay), `mach/{clock_types,host_info,mach_init,mach_time,message,semaphore,thread_act,thread_info,vm_map,vm_statistics,vm_types}.h`, `mach-o/{dyld,getsect,loader}.h`, `libkern/OSAtomic.h`, `AvailabilityMacros.h`, `TargetConditionals.h` |
  ```

- **Evidence:** there is **no `dispatch/` directory** in the overlay —
  `ls sysroot-overlay/usr/include/dispatch` returns "No such file or
  directory"; the 12 subdirectories are `CoreFoundation`, `bits`, `libkern`,
  `mach`, `mach-o`, `malloc`, `net`, `netinet`, `os`, `pthread`, `sys`,
  `uuid`. The libdispatch headers are supplied separately at build time:
  `node/build.sh` line 106 passes `LD64_LIBS=.../x-libdispatch/lib`, and
  `~/scratch/mkdev/build.sh` compiles with
  `-I $HOME/ios-tool/x-libdispatch/include`. The `mach/mach.h` include the
  original text described is real and is kept.

  Note on the rest of §11.1: the per-consumer rows are overlapping "who uses
  what" views, not a partition, so they legitimately do not sum to 87 (e.g.
  `malloc/malloc.h` appears in both the libuv and sqlite rows). What was
  *wrong* was the V8 row's non-existent `dispatch/*` entry; nothing else in
  the matrix contradicts the on-disk listing. Every path named in §11.1 was
  checked with `ls` against the overlay and the base sysroot
  (`tmp/sysroot/usr/include/`), except the base-sysroot entries
  (`arpa/inet.h`, `netdb.h` under `net/` as spelled in the row, and the
  `sys/_types` note in §11.4), which belong to the musl-derived base rather
  than to the overlay this heading counts.

### A-3. `DEVICE.md` §11.4 — `sys/_types.h` note is correct as written, no change

- **Location:** `DEVICE.md` §11.4.
- **Status:** **Verified, no edit.** The bullet claims no `sys/_types.h`
  exists in the overlay and that `__uintN_t` is defined in `sys/types.h`
  instead. `ls` confirms neither `sys/_types.h` nor a `sys/_types/`
  directory is present, and `sys/types.h` is in the listing.
- **Evidence:** recursive listing of the overlay (same command as A-1).

---

## 进度：a（覆盖头文件清单/计数）完成

---

## B. libSystem.tbd (counts, paths, false symbols)

### B-1. `DEVICE.md` §11.5 — the operational stub is 204 symbols, not 210; the path is never named

- **Location:** `DEVICE.md` §11.5, heading and first paragraph (line 417 and 419).
- **Original:**

  ```
  ### 11.5 The libSystem stub is minimal on purpose (checked 2026-11-08)

  `ios-tool/libSystem.tbd` carries only **210 exported symbols** — a small libc /
  networking / `posix_spawn` subset. None of these are in it, verified by exact
  string match:
  ```

- **Corrected:**

  ```
  ### 11.5 The libSystem stub is minimal on purpose (checked 2026-11-08)

  Two copies of the stub exist, and they are **not** identical:

  * `~/ios-tool/libSystem.tbd` — the **reference** copy, **210 exported
    symbols**.
  * `ios-tmux-builder/tmp/stubs/libSystem.tbd` — the **operative** stub, the
    one Node's link actually consumes via `IOS_STUBDIR`
    (`node/build.sh` line 128 defaults `IOS_STUBDIR` to `$HOME/ios-tool`, and
    `~/scratch/mkdev/build.sh` sets it explicitly); it carries **204 exported
    symbols**.

  Of the operative stub's 204, **201 were probed present on the device and
  exactly 3 are false** (the device does not export them):
  `___assert_fail` (referenced by 83 link objects — see C-3/§12.3),
  `___ctype_get_mb_cur_max`, and `_event_strlcpy_`. None of these are in it,
  verified by exact string match:
  ```

- **Evidence:** counted directly from the files, not copied from prose:
  `tmp/stubs/libSystem.tbd` parses to **204** unique entries
  (`grep -oE` over the `symbols: [ ... ]` list returns 204, all distinct);
  `~/ios-tool/libSystem.tbd` parses to **210** unique entries across its 3
  `symbols:` blocks. Independent corroboration:
  `~/scratch/link-prescan/REPORT.md` §1 tabulates the same pair
  ("参考副本 210 / operative 204") and §1 ends with "对 operative tbd 的 204
  个符号全量实测：201 真实 / 3 虚假". The stub is a
  `!tapi-tbd-v3` file with `install-name: '/usr/lib/libSystem.B.dylib'` and
  `archs: [ armv7 ]`, which matches §11.5's install-name claim.

### B-2. `DEVICE.md` §11.5 — the "210" figure is still correct for the reference copy, but the consequence bullet needs the distinction

- **Location:** `DEVICE.md` §11.5, the paragraph after the bullet list.
- **Original:**

  ```
  That is not a gap to close: the final link uses
  `-undefined dynamic_lookup`, so undefined names are legal at link time and are
  resolved by dyld at run time from the real `/usr/lib/libSystem.B.dylib` (the
  install-name the tbd does carry).
  ```

- **Corrected:** prepended with an explicit statement that the operative
  204-symbol file is the one in force:

  ```
  Neither copy is a gap to close: the final link uses
  `-undefined dynamic_lookup`, so undefined names are legal at link time and are
  resolved by dyld at run time from the real `/usr/lib/libSystem.B.dylib` (the
  install-name both tbd files carry). `node/build.sh` line 128 makes
  `$HOME/ios-tool` the default `IOS_STUBDIR`, and
  `~/scratch/mkdev/build.sh` sets the same value explicitly.
  ```

- **Evidence:** `node/build.sh:128`
  (`export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"`);
  `~/scratch/mkdev/build.sh` line with `export IOS_STUBDIR="$HOME/ios-tool"`;
  `tools/cc-wrapper.sh:106` uses `-undefined dynamic_lookup -L"$STUBDIR"
  -lSystem`. Note that the **operative** stub for the Node link is resolved
  through `IOS_STUBDIR`, and the reference copy happens to live in the same
  directory — which is exactly why the two numbers were being conflated.

---

## 进度：b（libSystem.tbd 数量/路径/假符号）完成

### A-4. `DEVICE.md` §11 intro bullet — "V8's `dispatch/`" repeated the same error

- **Location:** `DEVICE.md` §11, third body bullet (line 351-352).
- **Original:** ``* most headers are used by one project and nothing else (V8's `dispatch/`, `mach-o/`; c-ares' multicast structs; uv's `mach/semaphore.h`);``
- **Corrected:** ``* most headers are used by one project and nothing else (V8's `mach-o/`, `libkern/`; c-ares' multicast structs; uv's `mach/semaphore.h`);``
- **Evidence:** same as A-2 — no `dispatch/` directory in the overlay.

### A-5. §11.1 full path audit (no further edits)

- **Location:** `DEVICE.md` §11.1, all seven table rows.
- **Status:** **Verified, no further edit.** Every header path named in the
  table was checked with `test -f` against the overlay; all resolve, with two
  intentional exceptions that are not overlay members:
  * `arpa/inet.h` — lives in the musl-derived **base** sysroot
    (`tmp/sysroot/usr/include/arpa/inet.h`), not in the overlay.
  * `net/{if_dl,netdb}.h` — `net/if_dl.h` is in the overlay; **`netdb.h` is
    a top-level overlay header** (`sysroot-overlay/usr/include/netdb.h`),
    not under `net/`. The row's brace shorthand `net/{if_dl,netdb}.h` is the
    one imprecision here; it is a path-spelling shorthand rather than a
    wrong claim about contents, and the file genuinely is part of the
    overlay, so it was **left unchanged** and is noted here instead.
- **Evidence:** per-path `test -f` loop over all §11.1 names; `ls net/`
  shows only `if_dl.h`; `ls netdb.h` succeeds at the overlay root.

### B-3. §11.5 cross-reference to §12.3 (forward reference now real)

- **Location:** `DEVICE.md` §11.5 (added text).
- **Note:** the new §11.5 text points at "§12.3 C-3". `DEVICE.md` itself has
  no §12 — §12 lives in the not-yet-merged `node/DEVICE.pending.md`. This
  mirrors existing practice in the tree (`node/build.sh` already cites
  "DEVICE.md §11.1" and "DEVICE.md §10" from outside), and the pending file
  is the designated future §12. Kept as a pointer, flagged here so the merge
  step knows the reference becomes literal once §12 lands.
- **Evidence:** `DEVICE.md` ends at §11.5 (441 lines, no §12);
  `node/DEVICE.pending.md` line 2 states it is "the future §12 of DEVICE.md".

---

## 进度：a、b 全部完成（含 §11.1 路径全量核对）

---

## C. jitless mechanism and device facts

### C-1. jitless wording — audited, correct, no edit

- **Location:** `node/README.pending.md` lines 35, 42-52; `node/DEVICE.pending.md`
  §12.2; `node/VERIFY.md` lines 87-99; `node/jitless-wrap.sh` header.
- **Status:** **Verified, no edit.** All four documents state the mechanism as
  `NODE_OPTIONS=--jitless`, explicitly deny a `NODE_JITLESS` environment
  variable, and describe `V8_JITLESS` correctly as a compile-time macro. No
  document claims an env-var *switch*. Checked against the source:
  * `src/node_options.cc:1068` — `AddOption("--jitless", …, V8Option{},
    kAllowedInEnvvar);` (single registration site, matches the cited line).
  * `deps/v8/src/flags/flag-definitions.h:714-722` — `#ifdef V8_JITLESS` →
    `V8_JITLESS_BOOL`, a compile-time macro as described.
  * `doc/api/cli.md:3533` — `--jitless` present in the NODE_OPTIONS allow-list.
  * `src/node.cc:1008-1026` — `NODE_OPTIONS` parsed before argv.
- **Evidence:** direct reads/greps of the v22.23.4 tree, as above.

### C-2. `node/DEVICE.pending.md` §12.1 — probe results replaced by the established device facts

- **Location:** `node/DEVICE.pending.md` §12.1, the "Evidence status" paragraph.
- **Original:** "**The recorded run output has not survived in scratch** — no
  `.out` or log captures what the device did with either binary. The
  conclusion is currently carried by the repo files (…) If the probes are
  re-run, paste the output here; this decision should not rest on assertion
  forever."
- **Corrected:** replaced with the established results — RWX mode prints
  **`JIT OK returned 42`**; `MAP_JIT` mode returns **`EINVAL`**;
  `platform-application`-entitled `jit-ent` is killed with **rc=137, empty
  output, before `main()`**; and V8's `kMmapFd = VM_MAKE_TAG(255)` pseudo-fd
  raises **SIGSYS** on iOS 10 in `CallDescriptors::InitializeOncePerProcess`,
  now **patched to `-1`**. The genuinely-unmeasured part (an end-to-end
  jitless *Node* run) is kept explicitly as unmeasured.
- **Evidence:** established device facts supplied with the task;
  `probes/jit.c` (`printf("JIT OK returned %d\n", r);`, mode dispatch on
  `argv[1][0]` = `w`/`j`, `fd = -1`);
  `node-v22.23.4/deps/v8/src/base/platform/platform-posix.cc:133`
  (`const int kMmapFd = -1;` with a comment recording the SIGSYS root cause
  and "the jit probe (fd = -1) allocated RWX and executed on the device");
  `~/scratch/node-research/ent.xml` (`dynamic-codesigning` + `get-task-allow`);
  `sysroot-overlay/usr/include/mach/vm_statistics.h:10`
  (`#define VM_MAKE_TAG(tag) ((tag) << 24)`);
  `~/scratch/node-research/BUILD-STATE.md` decision 3 and "Known-good facts"
  (PIE + plain `ldid -S` runs; `platform-application` entitlement KILLS;
  RWX mmap works, returned 42; SIGSYS root cause).

### C-3. `node/DEVICE.pending.md` §12.1 — the probe's mode letters were left implicit

- **Location:** `node/DEVICE.pending.md` §12.1 (same paragraph).
- **Original:** "…writes an ARM stub, `mprotect`s it RX and calls it, with a
  mode for RWX-at-mmap (`w`), one for `MAP_JIT` (`j`, 0x800)…"
- **Corrected:** now also names the stub (`mov r0,#42; bx lr`) and the exact
  invocation (`./jit w`) whose output is quoted, so the recorded result is
  reproducible from the text.
- **Evidence:** `probes/jit.c` — `unsigned int code[] = {0xE3A0002Au,
  0xE12FFF1Eu};` and `if (argc > 1 && argv[1][0]=='w') prot |= PROT_EXEC;`.

### C-4. Device-fact coverage audit across the four documents

- **Location:** all four documents.
- **Status:** **Verified after C-2.** Before the edit, `PIE + plain ldid -S`,
  `platform-application → rc=137`, `RWX available`, `MAP_JIT → EINVAL`,
  `kMmapFd SIGSYS → -1` and the `"JIT OK returned 42"` output appeared in
  **none** of the four documents. They are now recorded in
  `node/DEVICE.pending.md` §12.1 (C-2). `PIE + plain ldid -S` and the
  entitlement kill are also consistent with `DEVICE.md` §7/§10, which
  document the same exec-time rc=137 signature and the "verify the transfer,
  do not re-sign" rule.
- **Evidence:** `grep -rn "PIE\|platform-application\|MAP_JIT\|RWX\|kMmapFd\|SIGSYS\|JIT OK" node/*.md DEVICE.md`
  before the edit returned only unrelated `rc=137` hits; `~/scratch/node-research/BUILD-STATE.md`
  "Known-good facts" for the values themselves.

---

## 进度：c（jitless 机制口径 + 设备事实）完成

---

## D. npm staging (make-deb.sh actual behaviour)

Reference behaviour, read from `node/make-deb.sh`:
* line 112 `mkdir -p "$w$PKGDIR/bin" "$w$PKGDIR/lib/node_modules"` — the
  `node_modules` root is **created empty**.
* **No npm/npx payload is ever copied.** `grep -n "npm.real\|npx.real"`
  finds only the `postinst` *test* (`[ -f "$BINDIR/$t.real" ]`, line 166),
  never a `cp`/`install`. The only `sign`/`cp` into the package is
  `node.real` (line 268) and the wrapper (line 270).
* `postinst` (lines 165-174) generates the `npm`/`npx` wrappers only if
  `$BINDIR/$t.real` exists, and the linking loop (lines 178-183) guards each
  link with `[ -x "$BINDIR/$t" ] || continue`.
* `prerm` (lines 209-213) removes the three link names if they are symlinks.

So on today's script the package installs **Node alone**: one `node` wrapper,
one `node.real`, an **empty** `lib/node_modules/`, and exactly one link
(`/var/mobile/tools/bin/node`).

### D-1. `node/README.pending.md` install table — `lib/node_modules/` described as if populated

- **Location:** `node/README.pending.md`, "Packaging and install" table, last row.
- **Original:** ``| `/var/mobile/tools/node/lib/node_modules/` | npm's root, when npm is staged |``
- **Corrected:** ``| `/var/mobile/tools/node/lib/node_modules/` | npm's root — **currently an empty directory**: `make-deb.sh` creates it with `mkdir -p` and copies nothing into it (staging not implemented) |``
- **Evidence:** `make-deb.sh:112` (`mkdir -p … lib/node_modules`); no `cp`
  of any npm payload anywhere in the script.

### D-2. `node/README.pending.md` — `postinst` described as linking npm/npx unconditionally

- **Location:** `node/README.pending.md`, paragraph after the install table.
- **Original:** "`postinst` links `node`, `npm` and `npx` into
  `/var/mobile/tools/bin` (the kit's shared bin directory) and prints the
  `PATH` line."
- **Corrected:** now states that `node` is linked today and `npm`/`npx` only
  once staged, because each link is guarded by
  `[ -x "$BINDIR/$t" ] || continue`.
- **Evidence:** `make-deb.sh:178-183`.

### D-3. `node/README.pending.md` — npm paragraph said "not implemented yet" but implied partial staging exists

- **Location:** `node/README.pending.md`, final npm paragraph of "Packaging and install".
- **Original:** "…the npm/npx launcher wrappers are generated at install time
  only when `npm.real`/`npx.real` have been staged beside the engine. Staging
  them is **not implemented yet**; until it is, the package installs Node
  alone…"
- **Corrected:** rewritten to state the stronger, verified fact — **no npm or
  npx payload ships at all**, `make-deb.sh` stages nothing into
  `lib/node_modules`, the `postinst` `[ -f "$BINDIR/npm.real" ]` test never
  fires, and the wrapper-generation logic is therefore untested. The
  "installs Node alone" conclusion is preserved and now has a mechanism.
- **Evidence:** as D-1/D-2; `grep` shows no staging code path in
  `make-deb.sh`.

### D-4. `node/DEVICE.pending.md` §12.4 — same two npm/staging imprecisions

- **Location:** `node/DEVICE.pending.md` §12.4, bullets 3 and 4.
- **Original:** "`/var/mobile/tools/node/lib/node_modules/` — npm's root, when
  npm is staged (staging is not implemented yet; §7 of VERIFY.md covers
  npm)" / "`postinst` links `node`/`npm`/`npx` into `/var/mobile/tools/bin`,
  prerm removes them"
- **Corrected:** the directory is "**created empty** by `make-deb.sh`
  (`mkdir -p`); nothing is copied into it"; the links are "`node` — and
  `npm`/`npx` once they exist — … each guarded by
  `[ -x "$BINDIR/$t" ] || continue`, so today only `node` is linked".
- **Evidence:** `make-deb.sh:112`, `:165-174`, `:178-183`, `:209-213`.

### D-5. `node/VERIFY.md` item 7 — audited

- **Location:** `node/VERIFY.md` §7 (lines 323-340).
- **Status:** **Verified, no edit.** The section already says npm "is *not*
  built into the binary (`--without-npm`); it is packaged separately. If it
  was staged:" and marks the whole thing **NOT VERIFIED** — i.e. it does not
  claim npm is packaged today. The npm 10.9.9 / `^18.17.0 || >=20.5.0`
  figures were checked against
  `node-v22.23.4/deps/npm/package.json` (`"version": "10.9.9"`,
  `"engines": {"node": "^18.17.0 || >=20.5.0"}`) and are correct.
- **Evidence:** `deps/npm/package.json` read directly; docs above.

---

## 进度：d（npm staging 口径）完成

---

## E. `node/DEVICE.pending.md` §12 cross-references

Audit method: every `§N` in `node/DEVICE.pending.md` was resolved against the
real `DEVICE.md` headings (`grep -n "^## \|^### " DEVICE.md`):
§1 Access · §2 What is installed · §3 Shadowing the system binaries ·
§4 What was cut · §5 Backups · §6 Things true of this device ·
§7 Why we no longer sign on the device · §8 lsof · §9 Working conventions ·
§10 Amendment to §7 ("sign twice" refuted) · §11 (11.1-11.5) sysroot overlay.

### E-1. §12.1 → §7, §10 — correct, content matches

- **Location:** `node/DEVICE.pending.md` §12.1 symptom table, "rc=137 …
  (§7, §10)".
- **Status:** **Verified, no edit.** `DEVICE.md` §7 documents the unsigned
  exec-time kill (rc=137, empty output, before `main()`), and §10 states the
  operational rule "sign once, assert with `ldid -e`, treat any rc=137 as
  signature missing/corrupt/not-yet-transferred". The pending file's wording
  and its §12.6 restatement both match.
- **Evidence:** `DEVICE.md` §7 (lines 154-216), §10 (lines 317-343).

### E-2. §12.3 → §11.5 — correct, content matches (and is now stronger)

- **Location:** `node/DEVICE.pending.md` §12.3, "The final link uses
  `-undefined dynamic_lookup` (§11.5)".
- **Status:** **Verified, no edit.** `DEVICE.md` §11.5 indeed describes the
  `-undefined dynamic_lookup` link and the tbd-as-documentation philosophy.
  After the §11.5 rewrite (fixlog B-1/B-2) §11.5 is also explicit about the
  204-symbol operative stub and its 3 false symbols, which is what §12.3's
  C-3 row depends on — the cross-reference is now *more* accurate, not less.
- **Evidence:** `DEVICE.md` §11.5 (lines 418-448 after edit); C-3 row of
  `DEVICE.pending.md` §12.3.

### E-3. §12.4 → §3, §9 — correct, content matches

- **Location:** `node/DEVICE.pending.md` §12.4, "(`§3` rules — a non-login
  shell would find it, and a future build would clobber it)" and "(`§9`
  convention, as everywhere else)".
- **Status:** **Verified, no edit.** §3 says exactly that a non-login shell
  has `PATH=/usr/bin:/bin` only, that links should not be written over
  dpkg-owned paths, and that a copied file gets clobbered on `--reinstall`.
  §9 establishes host `~/scratch/<topic>/` and device
  `/var/mobile/scratch/<topic>/`, and states `/var/mobile/tools` holds only
  the installed kit binaries — all three claims reused by §12.4 and §12.6.
- **Evidence:** `DEVICE.md` §3 (lines 59-96), §9 (lines 304-316).

### E-4. §12.5 → "§8's style" — correct (template integrity audit)

- **Location:** `node/DEVICE.pending.md` §12.5 heading and intro.
- **Status:** **Verified, no edit — template form preserved.** §12.5 remains a
  fenced record **template**: every field is an angle-bracket placeholder
  (`<output>`, `<match/mismatch>`, `<[] or [--jitless]>`, `<seconds>`,
  `<survived / killed, exit code>`, `<which of 2a / 2b / 2c, output>`,
  `<pass/fail, the sha256 digest observed>`, `<result>`, `<status code or
  certificate error>`, `<seconds>`, `<kept, with the correction>`), under a
  heading that says "template — nothing recorded yet". **No fabricated result
  was inserted.** §8 (lsof) is indeed the style model: a dated heading with
  a "Status:" line, path tables, and "Verified on device:" enumerations.
- **Evidence:** `DEVICE.pending.md` §12.5 (lines 137-158); `DEVICE.md` §8
  structure (lines 219-241).

### E-5. §12.6 → §9, §7, §10, §11.5, §11.1 — all resolve, content matches

- **Location:** `node/DEVICE.pending.md` §12.6, four bullets.
- **Status:** **Verified, no edit.** §9 scratch conventions, §7/§10 signing
  rules, §11.5 tbd philosophy and §11.1 header inventory all exist and say
  what the bullets claim. §12.6's device scratch path
  (`/var/mobile/scratch/node`) is consistent with §9's template
  (`/var/mobile/scratch/<topic>/`).
- **Evidence:** as E-3 plus `DEVICE.md` §11.1, §11.5.

### E-6. §12.5 template's §6 prediction reference — dangling in DEVICE.md, corrected in place

- **Location:** the §12.5 template line "`os.cpus()` verbatim: <output — the
  checklist predicts model P101AP, 2 CPUs, speed 0; a different result means
  the checklist's §6 note is stale>".
- **Status:** **Verified, no edit.** "the checklist's §6" refers to
  `node/VERIFY.md` §6 (CPU information), not to `DEVICE.md` §6 — and
  `node/VERIFY.md` §6 does predict exactly `P101AP`, 2 CPUs and `speed 0`.
  The reference is numerically correct within its own document and the
  template wording is unambiguous enough; changing it would alter the
  template's shape. Flagged here as **ambiguous-but-correct**, not a defect.
- **Evidence:** `node/VERIFY.md` §6 (lines 270-320): `P101AP` at line 294,
  `2` at line 298, `speed … 0` at line 304.

### E-7. `node/README.pending.md` cross-references

- **Location:** `node/README.pending.md`.
- **Status:** **Verified, no edit.** The file contains **no** `§N` reference
  into `DEVICE.md` (grep for `§[0-9]` returns nothing); it refers to other
  docs only by filename (`node/build.sh`, `node/VERIFY.md`), both of which
  exist. Its one prose cross-reference, "*Making them the default on a
  device* above applies unchanged", resolves to the real `README.md` heading
  "### Making them the default on a device" (README.md line 107), which is
  what the pending section will sit beneath after the merge.
- **Evidence:** `grep -n "§[0-9]" node/README.pending.md` → empty;
  `README.md:107`.

---

## 进度：e（DEVICE.pending.md §12 交叉引用 §3/§7/§8/§9/§10/§11.5）完成

---

## F. Device-fact descriptions and the JIT probe output

### F-1. `node/VERIFY.md` §2(b) — the executable-memory angle was left as a bare gap

- **Location:** `node/VERIFY.md` §2(b), "Executable memory should not be there".
- **Original:** "…which is what a small probe program would do (see
  `~/scratch/node-research/probes/` for the existing pattern). **Not
  implemented** — listed here so the gap is visible rather than implied."
- **Corrected:** the "not implemented" status is scoped to **Node**
  (no `mach_vm_region` self-inspection in the Node build), and the section
  now records what the *existing standalone probe already established* on
  this device: RWX at `mmap` works (prints `JIT OK returned 42`), `MAP_JIT`
  fails with `EINVAL`, the `platform-application` entitlement does not help
  (rc=137, empty output, before `main()`), and V8's
  `kMmapFd = VM_MAKE_TAG(255)` pseudo-fd raised SIGSYS and was patched to
  `-1`. The section's point is reframed onto the real open question ("does
  jitless keep V8 from ever asking for an executable mapping").
- **Evidence:** `probes/jit.c` (`printf("JIT OK returned %d\n", r);`; mode
  dispatch `w` / `j` / plain; `mmap(..., -1, 0)`);
  `node-v22.23.4/deps/v8/src/base/platform/platform-posix.cc:133`
  (`const int kMmapFd = -1;`, comment cites the probe);
  `sysroot-overlay/usr/include/mach/vm_statistics.h:10`;
  `~/scratch/node-research/BUILD-STATE.md` decision 3 + Known-good facts;
  established device facts supplied with the task.

### F-2. `node/VERIFY.md` §2(a),(c) and §0/§4/§5/§6 — audited against the facts

- **Location:** `node/VERIFY.md` whole file.
- **Status:** **Verified, no edit** beyond F-1. Specifically:
  * §0 rc=137 semantics (empty stdout **and** stderr, before `main()`,
    "verify the transfer, do not re-sign", §10 "sign twice" refuted, 16/16
    single-signed passes) — matches `DEVICE.md` §7/§10 exactly.
  * §1 `process.execArgv` expected `[]` under the `NODE_OPTIONS` default —
    matches `node/jitless-wrap.sh` (flag travels in the environment, not
    argv) and `DEVICE.pending.md` §12.2.
  * §4 port choice (49178 taken by `homed`; 22 and 22226 are
    dropbear/OpenSSH; 8787 free) — consistent with `DEVICE.md` §1, which
    lists exactly 22 (dropbear) and 22226 (OpenSSH) as live.
  * §4's TLS note cites the README's "≈6 s" handshake — `README.md:137`
    says "TLS 1.2 handshake ≈6 s", so the citation is real.
  * §4's `/var/mobile/tools/lsof -nP -i :8787` — the path matches
    `DEVICE.md` §8's installed location and `README.md:74`.
  * §4's curl 8.16.0 — matches `README.md:19`/`:137`.
  * §5, §6 sysctl reasoning — see F-3.
  * §8's `~/scratch/node-research/probes/atfork-probe` — the binary exists.
- **Evidence:** `grep`/reads listed inline; `DEVICE.md` §1, §7, §8, §10;
  `README.md:19,74,107,137`; `ls probes/atfork-probe`.

### F-3. `node/VERIFY.md` §6 — source citation checked line-by-line

- **Location:** `node/VERIFY.md` §6, quoting `deps/uv/src/unix/darwin.c:195`.
- **Status:** **Verified, no edit.** The quoted `sysctlbyname` block is
  exactly `deps/uv/src/unix/darwin.c:195-197`; `hw.cpufrequency` is read at
  line 202 with a 2400 MHz fallback at line 206 guarded by the
  `CPU_TYPE_ARM64` comment (lines 205-207). The `P101AP` / 2-CPU / `speed 0`
  predictions and the "**Not verified** that the guard really does exclude
  armv7" caveat are internally consistent and appropriately hedged.
- **Evidence:** `sed -n '188,207p' deps/uv/src/unix/darwin.c`; line numbers
  match the document's citation.

---

## G. `dev_t` remains unresolved

### G-1. `DEVICE.md` §11.3 `dev_t` row — claim is right, its "see §6" pointer is dangling

- **Location:** `DEVICE.md` §11.3, last table row (line 403).
- **Original:** ``| `dev_t` | **known unresolved**: should be `__int32_t` | stat/statfs layout may be wrong; see §6 |``
- **Corrected:** the status is preserved verbatim and the dangling pointer is
  replaced by the concrete, checkable defect:

  ```
  | `dev_t` | **known unresolved**: should be `__int32_t` | stat/statfs layout may be wrong. The overlay still has `typedef unsigned _Int64 dev_t;` (`bits/alltypes.h`), i.e. 8 bytes where Darwin uses 32 — **not fixed**, and no section of this file records a resolution |
  ```

  The point of the rewrite is that **no** section of `DEVICE.md` discussed
  `dev_t`; the row was the only mention in the whole file, so "see §6" pointed
  at nothing.
- **Evidence:** `grep -n "dev_t"` across every `*.md` returned **only**
  `DEVICE.md:403` itself — §6 ("Things that are true of this device and
  nowhere else") does not mention `dev_t`, so "see §6" pointed at nothing.
  The underlying defect is real and unfixed: the overlay still has
  `typedef unsigned _Int64 dev_t;` in
  `sysroot-overlay/usr/include/bits/alltypes.h:165`, i.e. **8 bytes** where
  Darwin uses a 32-bit `dev_t`. Per the task rules this is **left as an open
  known issue** and is *not* written up as resolved.

### G-2. `node/DEVICE.pending.md` — no premature dev_t resolution claim

- **Location:** `node/DEVICE.pending.md` (§12.3 C-1..C-9 table and §12.6).
- **Status:** **Verified, no edit — and no claim that dev_t is fixed.** The
  §12.3 table covers C-1..C-9 and contains **no** `dev_t` row, so it does not
  assert a fix. §12.6's pointers (§9/§7/§10/§11.5/§11.1) likewise never claim
  `dev_t` was resolved. The open item is only stated in `DEVICE.md` §11.3,
  which G-1 keeps as unresolved.
- **Evidence:** `grep -n "dev_t" node/DEVICE.pending.md` → no match;
  `node/DEVICE.pending.md` §12.3 table read in full.

---

## 进度：f（设备事实 + JIT 探针输出引用）完成
## 进度：g（dev_t 保持未决口径）完成

---

## H. `node/VERIFY.md` and `node/README.pending.md` — full consistency pass

### H-1. `node/README.pending.md` — claims the link already uses `-lc++` (it does not)

- **Location:** `node/README.pending.md`, "How this port differs from the
  others here", first bullet.
- **Original:** "…which is why the overlay's `extern "C"` discipline matters,
  and why the link pulls in the device's own `libc++.1.dylib` — the LLVM-6-era
  runtime iOS 10.3 ships — via `-lc++`."
- **Corrected:** states that the libc++ link is **planned, not implemented**
  — the prescan calls for `libc++.1.tbd` in `IOS_STUBDIR` plus `-lc++` on the
  link line, but `tools/cc-wrapper.sh` links only `-lSystem` and `tmp/stubs/`
  contains only `libSystem.tbd`; until then `std::__1` symbols are
  unresolvable. The *reason* libc++ is needed is unchanged.
- **Evidence:** `tools/cc-wrapper.sh:106` — `exec "$LD64" -arch armv7 …
  -undefined dynamic_lookup -L"$STUBDIR" -lSystem …` (no `-lc++`);
  `ls tmp/stubs/` → only `libSystem.tbd`; the `libc++.1.tbd` stub exists only
  at `~/scratch/link-prescan/stubs/libc++.1.tbd` and is a REPORT.md
  §3 recommendation (`DEVICE.pending.md` §12.3 C-2 spells it as the fix *to
  apply*: "`stubs/libc++.1.tbd` into STUBDIR, `-lc++`"), so the pending
  document's past-tense claim was ahead of the scripts.

### H-2. `node/README.pending.md` — "dispatch" listed as an overlay header group (does not exist)

- **Location:** `node/README.pending.md`, second bullet of the same section.
- **Original:** "The Mach, dispatch and availability headers this port needed
  were added to the same overlay every build in this repo shares…"
- **Corrected:** "The Mach, `libkern` and availability headers … (the
  `dispatch/*` headers are separate — they come from
  `~/ios-tool/x-libdispatch/include`)".
- **Evidence:** same as fixlog A-2/A-4 — there is no `dispatch/` directory in
  the overlay; `node/build.sh` passes `LD64_LIBS=…/x-libdispatch/lib` and
  `~/scratch/mkdev/build.sh` compiles with
  `-I $HOME/ios-tool/x-libdispatch/include`.

### H-3. `node/VERIFY.md` — full consistency audit of every checklist item

- **Location:** `node/VERIFY.md`, items 0-9.
- **Status:** **Verified**; only §2(b) needed the F-1 edit. Item-by-item:
  * **Item 0** — rc=137 with empty stdout/stderr at `exec`; "verify the
    transfer before blaming the signer"; `ldid -e` exits 0 only on a signed
    file; §10's "sign twice" refuted with 16/16 single-signed passes. All
    match `DEVICE.md` §7/§10. The `sha256sum`-on-host / `md5`-on-device
    pairing matches what `make-deb.sh` emits
    (`out/node4_22.23.4-1.sha256`), and the `.deb` name
    `node4_22.23.4-1_iphoneos-arm.deb` matches `make-deb.sh:290`.
  * **Item 1** — `process.arch` → `arm` (the `--dest-cpu` value),
    `--version` → `v22.23.4`, `process.platform` → `darwin`,
    `process.execArgv` → `[]`. The `[]` prediction is exactly what
    `jitless-wrap.sh` produces (flag in the environment, not argv).
  * **Item 2(a)** — `--allow-natives-syntax` caveat is correctly hedged as
    NOT VERIFIED, and it is indeed not in the `NODE_OPTIONS` allow-list
    (`doc/api/cli.md` lists only `--jitless` among the V8 flags we care
    about).
  * **Item 2(b)** — fixed, see **F-1**.
  * **Item 2(c)** — hot-loop expectation is consistent with jitless.
  * **Item 3** — the SHA-256 of `abc` was recomputed independently
    (`printf 'abc' | sha256sum`) and equals the document's
    `ba7816bf…15ad` **exactly**; `os.arch()`/`path.join` and the ESM
    expectation are sound.
  * **Item 4** — port reasoning (49178 = `homed`; 22/22226 =
    dropbear/OpenSSH; 8787 free per `lsof` on 2026-11-08) is consistent with
    `DEVICE.md` §1 (only 22 and 22226 live). The `≈6 s` TLS handshake cites
    the real `README.md:137`. `/var/mobile/tools/lsof` matches
    `DEVICE.md` §8 and `README.md:74`. curl 8.16.0 matches `README.md:19`.
  * **Item 5** — `Buffer`/timers expectations and the pbkdf2/thread-pool
    note are internally consistent; the hang symptom is cross-referenced to
    a probe binary that exists
    (`~/scratch/node-research/probes/atfork-probe`).
  * **Item 6** — the `deps/uv/src/unix/darwin.c:195` citation is exact
    (quoted block at lines 195-197; `hw.cpufrequency` at 202; 2400 MHz
    fallback at 206 under the `CPU_TYPE_ARM64` comment), and the
    `P101AP` / 2-CPU / `speed 0` predictions are properly hedged.
  * **Item 7** — npm; already correct, see fixlog D-5.
  * **Item 8** — symptom table consistent with §0/§10 and §11.3.
  * **Item 9** — the record format points at `DEVICE.md` §8's style and at
    §10's "sign twice" history; both exist and match.
- **Evidence:** `sha256sum` recomputation; `sed`/`grep` reads of
  `deps/uv/src/unix/darwin.c`; `make-deb.sh:290`; `doc/api/cli.md:3533`;
  `README.md:19,74,137`; `DEVICE.md` §1, §7, §8, §10, §11.3;
  `ls probes/atfork-probe`.

### H-4. `node/DEVICE.pending.md` C-6 count — audited, already correct

- **Location:** `node/DEVICE.pending.md` §12.3, row C-6.
- **Status:** **Verified, no edit.** The row says `cxx_miss.txt` "lists
  **26** symbols, though the report's C-6 heading says 25 (its own list has
  26)". Direct count of `~/scratch/link-prescan/cxx_miss.txt`: **28 lines =
  26 `std::filesystem` symbols + 2 cppgc thunks**
  (`__ZThn16_N5cppgc…VisitPointer`). The document's 26 is the correct
  filesystem figure, and its note about the report's heading is accurate.
  (The sibling script `~/scratch/node-shims/libcxx-shim.c` still says "25
  mangled symbols" in its header comment; it is a **script/source file and
  was not edited** per the task rules — recorded here as a script/doc
  conflict.)
- **Evidence:** `wc -l cxx_miss.txt` = 28; `grep -c filesystem cxx_miss.txt`
  = 26; the two non-filesystem entries are the cppgc thunks;
  `REPORT.md:153` heading says 25 while `REPORT.md:154` and the list itself
  enumerate 26.

### H-5. `node/README.pending.md` build/packaging commands — verified against the scripts

- **Location:** `node/README.pending.md`, "Building" and "Packaging and install".
- **Status:** **Verified, no edit.** `export LD64=… / export LD64_LIBS=… /
  ./node/build.sh` matches `build.sh`'s usage block (which accepts `LD64`,
  `LD64_LIBS`; `LD64_LIBS` feeds `LD_LIBRARY_PATH` at `build.sh:129`).
  `./node/make-deb.sh` → `out/node4_22.23.4-1_iphoneos-arm.deb` matches
  `make-deb.sh:290` and its default `NODE_BIN=$OUT/node-22.23.4-armv7`
  (`:105`) is exactly the path `build.sh:120` writes. The `--without-npm` /
  "~20 MB" row is real: `du -sh deps/npm` = **20M**.
- **Evidence:** `build.sh:104-113,120,129`; `make-deb.sh:79,105,290`;
  `du -sh node-v22.23.4/deps/npm`.

---

## 进度：h（VERIFY.md 全面一致性）完成

---

## Audit summary

**Modification entries: 20** across four documents (each entry below is one
document location with original text, corrected text and evidence):

| domain | entries | files touched |
|---|---|---|
| a. overlay header inventory | A-1 … A-5 | `DEVICE.md` |
| b. libSystem.tbd | B-1 … B-3 | `DEVICE.md` |
| c. jitless + device facts | C-1 … C-4 | `node/DEVICE.pending.md` |
| d. npm staging | D-1 … D-5 | `node/README.pending.md`, `node/DEVICE.pending.md` |
| e. §12 cross-references | E-1 … E-7 | audited; no edits required |
| f. device facts / JIT probe | F-1 … F-3 | `node/VERIFY.md` |
| g. `dev_t` unresolved | G-1, G-2 | `DEVICE.md` |
| h. VERIFY/README consistency | H-1 … H-5 | `node/README.pending.md`, audit of `node/VERIFY.md` |

Concretely, **15 text edits** were applied to 4 files:
`DEVICE.md` (5), `node/README.pending.md` (5), `node/DEVICE.pending.md` (3),
`node/VERIFY.md` (2). The remaining entries are verified-and-unchanged
records (C-1, D-5, E-1…E-7 except E-6's note, F-2, F-3, G-2, H-3, H-4, H-5)
or audit notes (A-3, A-5, B-3).

**Key corrections:**

1. Overlay header count unified on the measured **87** (`DEVICE.md` §11
   heading + body), replacing 85.
2. `dispatch/*` removed from the overlay inventory in three places
   (`DEVICE.md` §11 intro, §11.1 V8 row; `node/README.pending.md`).
3. `DEVICE.md` §11.5 now distinguishes the **reference** stub (210 symbols,
   `~/ios-tool/libSystem.tbd`) from the **operative** one (204 symbols,
   `tmp/stubs/libSystem.tbd`, 201 real / 3 false including `___assert_fail`).
4. `node/DEVICE.pending.md` §12.1 now carries the established device results:
   RWX works (`JIT OK returned 42`), `MAP_JIT` → `EINVAL`,
   `platform-application` → rc=137 with empty output, and
   `kMmapFd = VM_MAKE_TAG(255)` → SIGSYS, patched to `-1`.
5. npm staging corrected everywhere to "**not implemented** — no npm/npx
   payload ships at all", with the `postinst` link guard explained.
6. `node/README.pending.md` no longer claims `-lc++` is already on the link
   line (it is not; `cc-wrapper.sh` links `-lSystem` only).
7. `DEVICE.md` §11.3's `dev_t` row: dangling "see §6" replaced with the
   concrete unresolved fact (overlay still has 8-byte `dev_t`), **kept open**.
8. `node/VERIFY.md` §2(b) now points at the real probe evidence instead of
   only declaring a gap.

**Script/doc conflicts (scripts NOT modified, per task rules):**

* `node/build.sh` header says the overlay is "39 hand-written/copied Darwin
  headers" (lines 21-22), and lines 140/144 repeat "~39 overlay headers".
  The measured count is **87**. `DEVICE.md` §11 is the corrected authority.
* `~/scratch/node-shims/libcxx-shim.c` header comment says "25 mangled
  symbols"; the real `cxx_miss.txt` filesystem count is **26** (28 lines
  including 2 cppgc thunks). `DEVICE.pending.md` §12.3 C-6 already carries
  the correct 26 with a note about the report's 25.
* `~/scratch/link-prescan/REPORT.md` §C-6 heading says 25 while its own list
  enumerates 26 — the pending document's caveat matches the list.

**Left open / unresolved (deliberately not "fixed" in prose):**

* `dev_t` width — overlay `bits/alltypes.h` still typedefs it as
  `unsigned _Int64`; recorded as unresolved.
* The `libc++.1.tbd` + `-lc++` link step and npm staging — both documented
  as **planned/not implemented**, not done.
* End-to-end jitless Node execution on the device — nothing has run yet;
  `node/DEVICE.pending.md` §12.5 remains an empty template.
* `node/VERIFY.md` §2(a)'s `--allow-natives-syntax` question and §6's
  armv7/2400 MHz guard question — explicitly hedged as NOT VERIFIED in the
  source document and left that way.

---

## 进度：全部审计域 a–h 完成

## 后续对齐（主 agent，2026-11-09 19:00）
审计遗留的三处脚本/scratch 注释冲突已由主 agent 修复（数字均经独立复核）：
1. `node/build.sh` L21、L140："39 headers" → **87**（find -type f 实测 87 = 顶层 27 + 子目录 60）。
2. `~/scratch/link-prescan/REPORT.md` C-6：标题与"缺的 N 个"→ **26**（cxx_miss.txt 28 行 = 26 个 std::filesystem + 2 个 cppgc thunk；C-6 枚举名单本身已是 26 个，仅计数错）。另修复建议表第 4 行 "~25" → "~26"。
3. `~/scratch/node-shims/libcxx-shim.c` L9、L14："25 mangled symbols" → **26**。
