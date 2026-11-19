# tailcat 移植(Go 1.27.2 darwin/arm)——状态与坑

> 2026-11-17。大肥鱼。接 `porting-backlog.md` 的"设备端 Go"遗留。
> 目标:用移植好的 Go 1.27.2(`~/scratch/go-port/`)编译 tailcat 跑上 iPad4。
>
> **2026-11-19:Go 移植本体(runtime/链接器/工具链/调试史)已整体迁至
> [docs/go.md](go.md);本文聚焦 tailcat 应用层——依赖适配、dyld 三个障碍、
> 与最终验证。状态:✅ tailcat 全链路跑通(见文末)。**

## 一、已打通的部分(全部有实证)

1. **x/sys v0.48.0 补齐 darwin/arm**(本地副本 `~/scratch/xsys-v048-darwin-arm/`,
   replace 生效):
   - `ztypes_darwin_arm_extra.go`:KinfoProc/ExternProc/Eproc/TCPConnectionInfo/
     SaEndpoints/RawSockaddrVM/IPMreqn/Attrlist/SysvShmDesc 等,**布局用 C 探针
     在设备上实测**(probe-layout.c,kinfo_proc=492、tcp_connection_info=112
     align=8、tcpi_txpackets@56 需显式 `[4]byte` pad——AAPCS 的 long long
     8 字节对齐,Go arm 内部只有 4)。
   - `zsyscall_darwin_arm.go` 补 19 个新函数封装(从 arm64 版移植,funcPC 形式,
     preadv/pwritev 的 int64 拆高低字)。
   - `syscall_darwin_arm_compat.go`:补回 `funcPC()`(新版生成器已改用
     trampoline_addr 变量,老 zsyscall 需要)。
   - 删除与新版 syscall_unix.go 冲突的 Pread/Pwrite(改小写)/Setrlimit。
2. **x/net v0.60 本地副本**(`~/scratch/x-net-darwin-arm/`):补
   `zsys_darwin_arm.go`(iovec/msghdr/cmsghdr 32 位)。**坑:module cache 里
   新增文件不被识别(cache 按 zip 清单工作),必须本地副本 + replace。**
3. **u-root v0.16 termios**:32 位 Termios(Ispeed/Ospeed uint32)适配,
   本地副本 `~/scratch/u-root-v016/` + replace(sgtty_darwin.go/var_darwin.go
   的 speed()/toTermiosCflag() 改 uint32)。
4. **Go 1.27.2 GOROOT 内改动**(本阶段新增):
   - `runtime/pprof/defs_darwin_arm.go`(vm_region 常量,arm 缺失)。
   - `internal/golang.org/x/sys/cpu`(vendor)与 ts-ios 第三方 xsys 的
     `IsBigEndian`(wireguard-go checksum 用)。
   - `syscall/asm_darwin_arm.s`:**从 Go 1.14 抄回**的 Syscall/Syscall6/
     Syscall9/RawSyscall*(SVC $0x80,R12=trap 号)。1.27 上游删了 arm 版,
     netmon/pty/go-ps 等用 linkname 引 syscall.Syscall,缺了就链接失败。
   - `crypto/x509`:root_darwin.go 打 `darwin && !arm` tag,新增
     root_darwin_arm.go(PEM 路线:/etc/ssl/cert.pem);root.go 的 darwin
     分支排除 arm(无 env 时不再返回 systemPool,改读盘)。**不这样 CF/
     Security 的 macOS 风格路径(Versions/A)会让 dyld 直接拒载。**
   - `internal/syscall/unix/net_darwin.go`:打 `darwin && !netgo` tag
     (其 libresolv cgo_import_dynamic 会让链接器对 iOS 没有的
     libresolv.9.dylib 发 LC_LOAD_DYLD,dyld 直接拒载);拆出
     `syscall_hooks_darwin.go`(syscall_syscall* linkname + GoString + AI_*
     常量,无条件编译)。
   - **runtime `sys_darwin_arm.s` 的 syscallN_trampoline st_6 bug(今天修复,
     见下)**。
5. **tailcat 全链路跑通(✅ 终态)**:`-tags netgo -ldflags='-s -w'`,20MB
   Mach-O armv7;`--help`/`genkey`(真实生成密钥)/`serve`(常驻,DERP+地址)在
   设备上正常——**无 GODEBUG**(见二的环境点更新)。complex 776 行测试
   (宿主与设备端 go 两个工具链分别编译)10 组全过,见文末终验。

## 二、今天修掉的三个运行时障碍

| 症状 | 根因 | 修法 |
|---|---|---|
| dyld: `__TEXT segment not writable`(bind) | zsyscall 的 libc trampoline 里 `MOVW $libc_mach_task_self_(SB)` 取地址→R_ADDR→原地 bind 到 __TEXT | 改 `BL libc_mach_task_self_(SB)`,走 PLT/GOT |
| dyld: Symbol not found `_utimensat` | iOS 10 内核/共享缓存无 utimensat(iOS 11+) | x/sys 与 syscall 两处 utimensat 都改为基于 utimes 的兼容实现(AT_FDCWD 场景;注意标准库常量是 `_AT_FDCWD`) |
| dyld: CoreFoundation/Security 找不到 | crypto/x509 root_darwin 的 macOS 框架路径 | 见上,PEM 路线 |

另外两个必须记住的环境点:
- ~~必须 `GODEBUG=asyncpreemptoff=1`~~——**已不需要**(2026-11-18 晚):主线 bug
  (八-9)修复后又暴露异步抢占 SIGURG 打进 libc 上下文时线程挂死(根因:TLS g 槽
  在 iOS 10 未初始化,load_g 拿不到 g)。已在 go-port 禁用 darwin/arm 的异步抢占
  (preemptMSupported=false,build-tag 文件对),协作式抢占保留。实测 `tailcat serve`
  无 GODEBUG 正常常驻;若未来修好 g 槽 TLS 可再开。
- **签名要用设备上的 `/var/root/ts/ents.plist`**(platform-application +
  no-sandbox + skip-library-validation):no-sandbox 缺失时 netmon 的
  route 相关调用会 EPERM。

## 三、Go 移植调试史(2026-11-18~19,已全部解决 → 迁移至 docs/go.md)

tailcat 编译期与运行期暴露的全部 Go 移植层问题——syscallN_trampoline 压参
覆写返回地址(pc=0xc,"任何 Go 程序必崩")、nanotime1/vlrt 的 throwsplit 崩、
fcntl_trampoline 写回缺失(fdopendir ENOTDIR)、Seek/mmap 64 位参数槽(EINVAL)、
per-thread g 槽表(工具链多线程)、链接器的 pltstub 符号/__DWARF 段布局/
SMACHOPLT——**根因、修复、金丝雀与 lldb 方法论、全部提交号,现集中在
[docs/go.md](go.md) 二~四节**。此处不再保留逐日调试记录。

## 四、设备现场清理提醒

- 宿主侧:tailcat server(9999, host-auto key)、python3 http.server 8000
  (derpmap)、nc 监听——都是测试残留,可杀。
- 设备侧:tailcat2/tailcat-dbg/complex_retest/rib/ribdbg/rib_canary/rib_sym/
  rib_fresh/rib_fix/rib_ign/probe-* 等在 /var/root/ts/,调试期进程记得 killall;
  rib/ribdbg 带旧 bug 不可再用于验证(已修,以 rib_fix 为准)。
- 调试金丝雀版 rib_canary 的 spin 特性:触发即挂死(等 attach),看到进程
  卡死烧 CPU 先想到它。
- **build cache 回放坑**(今天吃了三次):改 linker 或 replace 目录源码后,
  `go build` 可能回放旧产物(stderr/二进制都不变)。对策:ldflags 里塞变化
  参数强制重链(与 hello/main.go 的 forcelink 注释同款)。

## 五、终验(2026-11-19)

- **宿主工具链编的 tailcat**:`--help`/`genkey`(真实生成密钥)/`serve`(常驻,
  DERP+tailcat 地址,主动 kill 正常退出)——无 GODEBUG。
- **设备端 go 编译的 complex 测试**(776 行、10 组:goroutines/atomics/mutex/
  文件/JSON/TCP+Unix socket/DNS/timer/信号/syscall):**10 组全过**——工具链与
  runtime 的完整闭环。
- 包:`tailcat4_0.7.0-1_iphoneos-arm.deb`(已装设备保留)、`go4_1.27.2-1_iphoneos-arm.deb`。
- Go 移植本体(runtime/链接器/工具链/patches)详见 [docs/go.md](go.md);
  "设备端 go 编译 tailcat"已列入 porting-backlog.md 待办。
