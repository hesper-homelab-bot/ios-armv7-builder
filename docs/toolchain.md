# 交叉编译工具链通用规则（iPad4 / armv7 / iOS 10.3.3）

> 适用范围：所有为这台设备交叉编译的软件（node、quickjs、dropbear、openssh、
> openssl、curl…）。软件专项细节见同目录各 md；本文只写**工具链层面可复用的规则**。
> 维护：大肥鱼。正本在本 git 仓库 `docs/`；`~/.dsh/AGENTS.md` 是它的符号链接入口。

## 1. 构建环境（每次都要 export）

```sh
export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
```

- C 驱动：`~/ios-tmux-builder/tools/cc-wrapper.sh`
- C++ 驱动：`~/ios-tool/cxx-wrapper.sh`（内部转调 cc-wrapper，附加
  `-nostdinc++ -isystem libcxx15-headers` 与 `_LIBCPP_NO_EXCEPTIONS`/
  `_LIBCPP_DISABLE_AVAILABILITY`，为匹配设备上的 libc++ 6.0.1 ABI）
- **cxx-wrapper 按自身 cwd 解析相对输入路径 → 传给它的文件路径一律绝对路径**，
  否则 `ld: file not found`。
- 常见手误：`LD64=IOS_LD64=...` 会把值设成字面量；变量名是 **`IOS_LD64`**。

## 2. 归档规则（ld64 的坑）

- **ld64 静默忽略 GNU thin archive**（不报错，符号就是缺）→ 所有 `.a`
  必须转成 darwin 扁平归档：`llvm-ar-21 --format=darwin`。
- `--format=darwin` 只存 basename → 同名成员互相覆盖（多个 heap.o/factory.o）
  → 成员名按路径哈希唯一化。
- **转换后必须验证成员数**（曾出现"成功"但 0 成员，ar 跑错了 cwd）。
- **对象 vs 归档的优先级**：普通 `.o` 对象永远压过归档成员；归档成员只在
  符号仍未定义时才被拉入。**放一个同名桩对象在链接行前面，会静默遮蔽
  归档里的真身**（node 快照桩事故的根源）。排查符号"明明在归档里却没生效"
  时先查这个。

## 3. thumb / ARM 规则（armv7）

- 汇编实现函数（`.S`）必须显式 `.thumb_func`，并尽量 `-mthumb -march=armv7` 汇编。
- 链接器警告 `ARM function not 4-byte aligned: <name>` = 该符号没有 thumb 位，
  thumb 调用方经 veneer 进入会 SIGILL——**不要忽略**。
- 汇编完必须验证：`llvm-objdump-21 -d --triple=thumbv7-apple-ios`，
  `bx lr` 应为 `4770`；`llvm-nm-21` 显示 `T`/`t`（thumb 位已置）。
- C 源码**无法**定义 `__atomic_is_lock_free` 等 clang builtin
  （`definition of builtin function`；`-fno-builtin` 也无效）→ 用 `.S`。

## 4. 原子操作雷区（设备级）

- 设备的出线原子 libcall **`___atomic_load_8` 是空函数**（64 位原子读静默
  返回垃圾；store 正常）。64 位 `std::atomic` 在 node/V8/libc++ 里都会中招。
- 修法：自备 armv7 原子 shim（LDREXD/STREXD + `dmb ish`），并让
  `__atomic_is_lock_free` 对 armv7 只认 `size <= 4`（8 字节走带锁路径）。
- 症状特征：插入成功、紧跟的查找失败；成功/失败集合随构建漂移（栈垃圾决定）。

## 5. 部署与验证

- 部署三件套（缺一 exec 即 SIGKILL）：`chmod 755 X && chown mobile:mobile X && ldid -S X`
- 排查 SIGKILL 第一步：设备上 `ldid -e X`——有输出=已签名；
  `_assert(signature != NULL)`=未签名。
- 就地覆盖已存在文件有 vnode 风险 → **部署成新文件名，再 `rm -f` 旧名 + `cp`**。
- 崩溃报告：`/var/mobile/Library/Logs/CrashReporter/*.ips`（SIGKILL 无报告；
  连续崩溃会被限流）。
- **.ips 符号化**：报告里 `0xADDR base + off` 的 base 是设备加载基址；
  主机地址 = `host_TEXT_vmaddr(0x4000) + (dev - base)`。必须用**同字节**
  的未 strip 孪生体（`llvm-nm -n` + 二分，或 llvm-symbolizer-21 --obj）；
  跨构建符号化漂移 KB 级，不可用。
- 探针模板（构建+部署+跑）：

```sh
export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
~/ios-tmux-builder/tools/cc-wrapper.sh -O1 -o /tmp/probe /tmp/probe.c [额外 .o/.a]
scp /tmp/probe root@<device>:/var/mobile/scratch/probe.new
ssh root@<device> 'cd /var/mobile/scratch && rm -f probe && cp probe.new probe && \
  chmod 755 probe && chown mobile:mobile probe && ldid -S probe && ./probe'
```

## 6. 设备连接

- 具体地址/别名只在 **DEVICE.md（gitignored，私有）** 与 `~/.ssh/config` 里，
  本仓库文档一律用 `<device>` 占位。
- **port 22 = 自编 dropbear（唯一 sshd），现代算法直连，无需兼容参数**。
- host key 变更后先 `ssh-keygen -R <device>` 再连。
- 守护：`/var/mobile/.local/bin/ssh-selfheal.sh`（每 120s；详见 docs/dropbear.md）。

## 7. 设备内存/执行模型（探针实测，写死的事实）

| 行为 | 结果 |
|---|---|
| 出生即 RWX 的 mmap | ✅ 可用 |
| mprotect 转 RWX 后执行 | ❌ SIGBUS |
| MAP_JIT | ❌ EINVAL |
| 带 platform-application entitlements 的二进制 | ❌ exec 即杀（别指望提权解锁） |
| V8 `kMmapFd = VM_MAKE_TAG(255)` | ❌ SIGSYS（已补丁为 -1，匿名映射） |

| 信号 | 含义 |
|---|---|
| SIGKILL(9)/137，无崩溃报告 | exec 层签名拒绝（先查 ldid）或 jetsam |
| SIGSYS | 内核拒绝系统调用（如 Linux cacheflush） |
| SIGSEGV @ 小地址 | 空指针/未初始化表 |
| SIGILL | thumb 位缺失或栈耗尽后的野跳 |


## sysroot 结构体的运行时 ABI（wall #14 教训，2026-11-11）

编译期能过 != 运行时 ABI 正确。sysroot 是手搓的：每个**与内核交互的
结构体**（ioctl/kevent/socket option/……）都要用**多元素探针**在设备上
验证，而不是只看编译+单元素调用。已有先例：

- `sys/event.h` struct kevent 曾带 `uint64_t ext[4]`（52B 步长），
  iOS 10.3.3 armv7 内核实际按 20B 无 ext 读——libuv/ares 的 changelist
  在第 2+ 个 change 起全错（坏 fd、EINVAL abort、SIGBUS）。
  已删 ext 并留注释（sizeof 必须 =20）。

规则：新增/修改 sysroot 头里与 syscall 相关的结构体时，
编译一个多元素探针（≥2 个元素走完整 syscall 路径）在设备上跑通
才算数。单元素探针测不出 stride 错位（第 1 个永远对齐）。
