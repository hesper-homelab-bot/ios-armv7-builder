# Node 22.23.4（armv7 / iOS 10.3.3）移植专项

> **2026-11-11 03:30 更新：Phase 2 主体完成。** 全部 13 道墙攻克，
> 诊断已移除的 node_final 全冒烟 6/6 通过
> （--version、42×3、TypedArray、Buffer、JSON、require('fs')），
> 已安装为 /var/mobile/tools/node/bin/node.real + jitless wrapper。
> 墙 #12（blob fixup 11415 处）与墙 #13（torque host 布局字面量，
> force_32bit_output 重生成）为本阶段两大根因级发现，细节见
> BUILD-STATE (w)-(ae)。


> 工具链通用规则（env、归档、thumb、原子雷区、部署三件套、探针模板）见
> `docs/toolchain.md`，本文不重复。设备私有细节见 `DEVICE.md`（gitignored）。
> **权威流水账**：`~/scratch/node-research/BUILD-STATE.md`（仓库外，节 (a)–(v)）——
> 本文只留提炼后的状态，逐墙时间线以流水账为准。

## 当前状态（2026-11-10 16:00）

- `node --version` → `v22.23.4` **设备跑通**（jitless，三连稳定）；
  JS 执行（`-e`）未通：V8 isolate 初始化完成后的 builtin 首跳崩溃（墙 #12，调查中）。
- 运行形态：`bin/node` 是 jitless wrapper（向 `NODE_OPTIONS` 追加 `--jitless` 后
  `exec node.real`）；直接跑 `node.real` 且不带该旗标 = 自愿踩 JIT 分配。
- 注意：设备 `/var/mobile/tools/node/bin/` 目前**只有 wrapper**，`node.real`
  不在位（`--version` 的验证是在 `/var/mobile/scratch/` 的试验二进制上做的）；
  正式安装（`node/make-deb.sh` → deb）尚未执行。
- npm 未实现：`--without-npm` 构建，`lib/node_modules` 为空目录，包里只装 node。
- 已知未解：C-6 `std::filesystem`（设备 libc++ 无此库，26 个符号，
  `libcxx-shim.c` 目前是空壳 0/26）——`require()` 文件模块解析依赖它。

## 已攻克墙（#1–#11）

| # | 墙 | 根因（一句） | 修法（一句） |
|---|---|---|---|
| 1 | kMmapFd SIGSYS | V8 `kMmapFd = VM_MAKE_TAG(255)` 的 Mach tag 伪 fd 在 iOS 10 内核触发 SIGSYS | 补丁为 `-1`（普通匿名映射；jit 探针实测 fd=-1 RWX 可用） |
| 2 | ArmUsingHardFloat | 源码守卫只含 LINUX/FREEBSD，不含 DARWIN，armv7 无定义（C-9） | shim 进链接（`shims_arm.o`；armv7-apple 为软浮点，答案=false） |
| 3 | 栈耗尽 SIGILL | BigInt 字面量转换递归链吃穿 1MB 主线程栈，污染返回地址落入 ARM 态解码 thumb（UDF） | `ulimit` 被内核锁死（root 亦然）；实际落地 = thumb 位 blx 跳板；**1MB 栈限制本身未消除，属已知限制** |
| 4 | FlushICache SIGSYS | `cpu-arm.cc` 的 `#else` 分支是 Linux ARM cacheflush 内联 `svc`（iOS 系统调用门是 svc 0x80，必杀；musl 派生 sys/syscall.h 让它编译通过） | `V8_OS_DARWIN` 下改 no-op（mksnapshot 不执行生成代码；jitless 不执行新代码） |
| 5 | RO 转换 SIGSEGV | 序列化期代码 chunk 的 RO（mprotect PROT_READ）转换触发崩溃，teardown 形态 | 对 `V8_TARGET_OS_IOS` 短路该转换（保持 RW），最小 diff 入补丁 |
| 6 | setup-isolate-deserialize | 快照墙使大 make 提前失败，该文件 0 编译 → dyld 缺 `SetupIsolateDelegate` vtable | 按 target 旗标单独编译并入链接；链接前 prescan 全输入列全缺失，防打地鼠 |
| 7 | `__atomic_is_lock_free` | clang builtin，C 源码无法定义（`-fno-builtin` 也无效） | thumb `.S` 实现（`.thumb_func` + `-mthumb -march=armv7` 汇编） |
| 8 | thin 归档 | ld64 静默忽略 GNU thin archive；`--format=darwin` 只存 basename，同名孪生成员（heap.o/factory.o）被拉错 | llvm-ar 扁平归档 + 成员名按路径哈希唯一化（`rebuild-flat2.sh`，armap 验证） |
| 9 | PushAll thumb | `push_registers_asm.cc` Apple 变体符号没加下划线/缺 thumb 位，`stack.cc` 引用 `_PushAll…` → lazy 查找，jitless 下 Abort 134 "Symbol not found" | `shims.cc` 跳板 shim（thumb 位正确），undefined 归零 |
| 10 | exec 随机 SIGKILL | 部署漏了 `ldid -S`（未签名 Mach-O exec 即被杀，与体积/内容/vnode/重启均无关） | 部署三件套 `chmod 755 + chown mobile:mobile + ldid -S` 缺一不可；排查第一步 = 设备上 `ldid -e` |
| 11 | CSPRNG | 设备 `___atomic_load_8` 是 no-op（64 位原子读静默返回垃圾）+ clang `__atomic_is_lock_free(8)` 撒谎（返回 1 但 libcall 没写）→ OpenSSL namemap 条目 hash 全 0 → `EVP_CIPHER_fetch("AES-256-ECB")` 失败 → `RAND_status()==0` → node CHECK 崩 | `c8fixed.o`（thumb .S，is_lock_free 只认 size≤4，逼 OpenSSL 走带锁路径）；`RAND_set_DRBG_type("AES-192-CTR")` 绕行已从 node.cc 撤回 |

## 进行中：墙 #12 — isolate 启动后 builtin 首跳崩溃

- 现象：`-e` 在 `Warning: disabling flag --expose_wasm` 之后、任何 JS 输出之前
  SIGSEGV；`blx ip` 时 `ip=0x22` → PC=0x20（跳空页），lr = embedded blob+0xeb68
  （即调用点位于 blob 内某 builtin，按偏移记为 builtin#111），r3=0x55c80000（cage base）。
- 已排除：快照/embedded.o 比特正确（embedded.o `__text` 1,920,160B 与设备
  embedded_code.bin 逐字节一致；`_v8_Default_embedded_blob_data_` 指向真 blob 起点）；
  旗标问题（`--version` 各变体 3/3 稳定）；反序列化（`--profile-deserialization`
  证明 RO space 228,879B / isolate 18,416B / context #0 40,400B 三段全部成功）。
- 配置矩阵（blob / snapshot / delegate → 结果）：
  `node_v4` 真/真/full → SIGSEGV PC=0x20, r0=5；
  `node_v5` 空/真/full → SIGSEGV @ RO PostProcessCode（wrapper 空）；
  `node_v6` 真/真/deserialize → SIGSEGV PC=0x20, ip=0x22（主签名）；
  旧 `nrb` 空/真/full+旧 c8 → SIGILL。
- 主嫌疑：`Builtins::InitializeIsolateDataTables`（isolate.cc:4903，反序列化完成后
  调用）用 `EmbeddedData::FromBlob(isolate).InstructionStartOf(i)` 填
  `builtin_entry_table`；若表内容错，首次间接 builtin 跳转即 blx 垃圾。
  具体是哪个 builtin、经何机制调用——子 agent 调查中。
- 符号化注意：`.ips` 里 base 是设备加载基址，主机地址 =
  host_TEXT_vmaddr(0x4000) + (dev − base)，且必须用同字节未 strip 孪生体
  （见 `docs/toolchain.md` §5）。
- 附带发现（未完）：设备 `___atomic_load_8` no-op 波及所有 64 位 `std::atomic`
  （node/V8/libc++），待 LDREXD/STREXD 真实现（首版手写汇编寄存器误用已弃稿）。

## 链接配方（`/tmp/link-node.sh`）

链接驱动 `~/ios-tool/cxx-wrapper.sh -O2 -pie`；env 四件套见
`docs/toolchain.md` §1。输入分三层（顺序即优先级）：

1. **对象**（普通 .o，永远压过归档成员）：
   `node_main.o`（定义 `_main`，cc-wrapper 硬编码 `-e _main`）、
   `node_snapshot_stub.o`（`GetEmbeddedSnapshotData → nullptr`）、
   `v8_base_without_compiler/.../setup-isolate-deserialize.o`（DESERIALIZING
   delegate，标准配置）、`/tmp/c8fixed.o`（墙#7/11 修法）、
   `mksnapshot_dev/shims_arm.o`（C-4 futimens/utimensat + 墙#2 ArmUsingHardFloat）。
   **教训**：embedded-empty/snapshot-empty 桩对象曾静默遮蔽
   `libv8_snapshot.flat.a` 里的真身 geni/{snapshot,embedded}.o——真快照由该归档
   成员提供，桩必须移除。
2. **非 V8 扁平归档**（`obj.target/flatdeps/*.flat.a`，18 个）：libnode、
   libopenssl、libuv、libcares、libllhttp、libuvwasi、libnghttp2、libada、
   libsimdjson、libsimdutf、libbrotli、libsqlite、libzstd、libzlib、libnbytes、
   libcrdtp、libncrypto、libhistogram。
3. **V8 扁平归档**（`obj.target/tools/v8_gypfiles/*.flat.a`，10 个进链接）：
   v8_base_without_compiler、v8_compiler、v8_turboshaft、v8_initializers、
   v8_initializers_slow、v8_libbase、v8_libplatform、v8_zlib、v8_snapshot、abseil。
   （`libv8_init.flat.a` 在盘上但属 mksnapshot 侧 full 变体，node 链接不用。）

真快照链：设备跑 arm32 `mksnapshot.arm`（`~/scratch/mkdev/build.sh` 从 target
对象构建）→ 产物 `~/scratch/snapshot_gen/{snapshot.cc,embedded.S}` 回填源树
`out/Release/obj.target/v8_snapshot/geni/` 编译成 geni/{snapshot.o,embedded.o}。

## 关键文件路径表

| 用途 | 路径 |
|---|---|
| 权威流水账（节 (a)–(v)） | `~/scratch/node-research/BUILD-STATE.md` |
| node 源树（已按补丁改造，非 pristine） | `~/scratch/node-research/node-v22.23.4/` |
| 补丁（对 node 源树，33 个） | `~/scratch/node-patches/*.patch`（README.md 有增量说明） |
| 链接 shim 源 | `~/scratch/node-shims/shims.cc`、`libcxx-shim.c`；is_lock_free 真话版 `/tmp/c8fixed.S` → `/tmp/c8fixed.o` |
| 设备端 mksnapshot 构建 | `~/scratch/mkdev/build.sh`（→ 源树 `out/Release/mksnapshot.arm`）；扁平归档重建 `~/scratch/mkdev/rebuild-flat2.sh` |
| 快照产物（设备回填） | `~/scratch/snapshot_gen/{snapshot.cc,embedded.S,embedded_code.bin,embedded_data.bin}` |
| 链接脚本 | `/tmp/link-node.sh`（/tmp 易失；固化配方以本文为准） |
| 仓库侧脚本 | `node/build.sh`、`node/jitless-wrap.sh`、`node/make-deb.sh`、`node/VERIFY.md`（设备验证清单） |
| 待并入文档草稿 | `node/README.pending.md`（主 README 的 Node 节）、`node/DEVICE.pending.md`（DEVICE.md §12 草稿） |

## 工作日志

逐墙时间线、调查协议与中间结论：`~/scratch/node-research/BUILD-STATE.md`
（节 (a)–(v)；墙 #12 进行中，结论落 (u) 节及其后续）。
