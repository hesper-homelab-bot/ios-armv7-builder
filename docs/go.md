# Go 1.27.2 darwin/arm 移植(设备端与交叉工具链)

> 2026-11-16 起的移植工程。上游 Go 在 1.14 之后移除了 darwin/arm(32 位 iOS);
> 本工程在 **Go 1.27.2 树内复活它**:纯 Go runtime(无 cgo)、内部链接 Mach-O
> 写入器、per-thread g 槽表。宿主工具链 = `~/scratch/go-port`(tailcat 及全部
> Go 程序的构建基础);设备端工具链 = `go4` deb(`/var/mobile/tools/goroot`)。
> 构建与 patch 集合在 `../go/`(build.sh + patches/,每个 hunk 的"为什么"见
> `go/patches/README.md`);修复的提交在 go-port 仓库(4ede5256..HEAD)。
> 应用层(tailcat)的验证记录见 [tailcat-porting.md](tailcat-porting.md)。

## 一、成果一览(2026-11-19)

- **宿主交叉工具链**:官方 go1.27.2 源码 + 6 个 patch,`make.bash` 完整构建,
  可交叉编译 darwin/arm(所有 Go 程序,含 tailcat 23MB)。
- **设备端工具链**:go/compile/link/asm/vet 跑在 iPad 上;
  `go version` / `go list` / `go build` 全通;complex 多包测试(776 行、10 组)
  设备端编译并运行,**10 组全过**(默认并发、无 GODEBUG)。
- tailcat(23MB)与全部 Go 程序在 iPad4/iOS 10.3.3 上正常运行。

## 二、runtime 修复清单(每个都活着炸出来过)

| # | 症状 | 根因 | 修复 |
|---|---|---|---|
| 1 | 任何 libc 调用后 SIGSEGV pc=0xc/0x14("任何 Go 程序必崩") | syscallN_trampoline 压参区 reserve 缩放抄错:arm64 `LSL $3`(×8)抄成 `ADD R6,R6`(×2)。n=6 时 args[5] 精确覆写入口 push 的返回地址,RET 弹垃圾 | 补第二条 `ADD R6,R6`(×4);同源发现 n≤4 无边界拦截(count=n-4 为负,写循环无限跑;arm64 用 BEQ 标签链拦截),补 `CMP $0, R7; BLE callit`(commit ee291af1) |
| 2 | `runtime: stack split at bad time`(设备端 go 压力下) | `nanotime1`/vlrt 除法族是普通 Go 函数,在 exitsyscall 的 throwsplit 窗口里撞上 stackPreempt 栈检查;Linux 的 nanotime1 是 NOSPLIT VDSO 故免疫 | 两处补 `//go:nosplit`(commit 83eec5ef) |
| 3 | 每进程第一次读目录必失败 `fdopendir: not a directory` | `fcntl_trampoline` 缺结果写回(arm64 有、arm32 抄丢):runtime.fcntl 恒返回 0 → poll.OpenDir 的 F_DUPFD_CLOEXEC dup 得到 fd 0(stdin)→ fdopendir(0) ENOTDIR | 补 ret@12/errno@16 写回(commit c28c1472) |
| 4 | 所有 os.File.Seek EINVAL | zsyscall 的 Seek(arm64 抄)把 64 位 offset 当一个 uintptr 传:高 32 位截断、whence 错位到内核 offset 高半字槽 | syscall6 拆 lo/hi;mmap 的 pos 同族改 syscall9(commit c28c1472) |
| 5 | SIGURG 打进 libc 上下文线程挂死(早期"必须 GODEBUG=asyncpreemptoff=1") | 异步抢占信号落点线程的 TLS g 槽未初始化,load_g 拿不到 g | darwin/arm 默认禁用异步抢占(preemptMSupported=false,build-tag 文件对;commit 35aec282) |
| 6 | 工具链多线程崩:`math/bits.Div64` 读 g_m 时 g(R10)=0(addr=0x28) | **per-thread g 槽**:旧设计 tls_g 只指向线程 0 固定槽(tls_g0slot),注释自认"single-threaded startup path needs" | 槽表:save_g/load_g 以 TPIDRURO 为 key 查 64 项表,LDREX/STREX 抢空位;**sigtramp 无条件 load_g**(上游 iscgo≠0 判断在纯 Go 移植下失效);badsignal 对外部线程(libSystem workq)丢信号而非崩溃(commit 14d44ae0) |

## 三、链接器修复清单

| 症状 | 根因 | 修复 |
|---|---|---|
| dyld: `__TEXT segment not writable`(bind) | zsyscall trampoline 里 `MOVW $libc_xxx(SB)` 取地址 → R_ADDR → 原地 bind __TEXT | 改 `BL libc_xxx(SB)` 走 PLT/GOT(自包含桩) |
| "所有崩溃报告符号名不可信"(0x8e96a0 报 rate.Every 实为 fiat.p224Sub) | __plt 故意不带 S_SYMBOL_STUBS(iOS 10 dyld 对 stub-stride/indirect 语义敏感),桩地址无任何 symtab 符号;lldb 对坏元数据的解析整体错位 | doMachoLink 为每个桩合成 `libc_<name>.pltstub` 符号(N_SECT|N_EXT,value=__plt+SymPlt);symkind 归 extdef 防 dyld 当 undef 解析(commit e1f54449) |
| 桩数据蒸发(rib_fresh 无 __plt section) | `allocateSingleSymSections(SMACHOPLT)` 被注释 | 还原(同 commit) |
| dyld: `malformed mach-o image: __DWARF filesize > vmsize` | 上游 macOS 形态(vsize=0/filelen=N)被 iOS 10 老 dyld 拒载;设备端 go build 默认产物全部中招 | __DWARF 给真实 vsize + 独立 vmaddr(+0x40000000),protections 保持 0(commit 77f89cbb) |

runtime/链接器的 **SVC 直陷遗留**:zsyscall 的 SVC 路径(SYS_LSEEK 等)在 iOS 10
返回 ENOTTY;libc trampoline 路径正常。arm 版 zsyscall 应全面改用 libc 原语(待办)。

## 四、调试方法论(血泪换来的,直接复用)

1. **汇编金丝雀**:入口把预期返回地址存进空闲寄存器(勿用 R9,libc 当临时用),
   各阶段读 [R5] 比对,坏则 spin 死循环等 attach。校验点选"sp 不动、无栈复用"
   的窗口。sys_darwin_arm.s 的 syscallN 金丝雀一次定位 ×2 压参 bug。
2. **lldb 断桩读参数**:pltstub 符号断点 + `register read r0`(系统调用参数)
   + `finish` 读返回。fdopendir 断桩抓到 fd=0,一步实锤 fcntl 链。
3. **lldb 在 armv7 的坑**:条件断点(EXC_ARM_DA_DEBUG)评估时机≠停住时机;
   watchpoint set expression 对寄存器/内存语义含混;栈 ASLR+复用使固定地址
   watchpoint 被噪声淹没——能不用则不用。
4. **工具先验再下结论**:nlist_32 是 12 字节/条(不是 16);pclntab functab
   entry 是 entryOff(相对 textStart=0x2000);LC_DYSYMTAB 字段偏移——三次解析
   错误制造了三个假象。
5. **改链接器必须 `cd src/cmd/link && go install .` 重建 tool**——go build
   不会自动重建 GOROOT tool,三次踩坑。
6. **对照上游原文**:syscallN 的 ×2 vs arm64 `LSL $3`、fcntl 的写回缺失、
   Seek 的拆槽——全部在 arm64 原文对照下现形。移植汇编必须逐行对照缩放系数。

## 五、设备端工具链

- 部署形态:`/var/mobile/tools/goroot/{bin/go,pkg/tool/darwin_arm/{compile,link,asm,vet},src,pkg/include}`
- `go4` deb 自动 postinst 设备重签(宿主 ldid 签名在本设备内核策略下
  Killed: 9);GOCACHE 别混 root/mobile 属主;设备 hfs 的 tar 解压会随机丢
  小文件,部署后必须 `find -size 0` 校验(testdata 空文件除外)。
- /tmp 是 1.7G 上限的 tmpfs(带 usrquota):go build/make.bash 的 $WORK 必须
  `TMPDIR` 指到根分区,否则 "disk quota exceeded"(构建脚本已内置)。
- 性能:A6X 上 complex 多包编译约 10 分钟;工具链自举或编译大程序按耐心计。

## 六、遗留待办

- **用设备端 go 编译 tailcat**(终极自举验证;源码+依赖需上设备,
  goproxy.cn 拉取或宿主推 modcache;预计 30-60 分钟)。
- zsyscall SVC 路径全面改 libc 原语(见三末)。
- Ftruncate/Truncate/pread/pwrite 的 64 位参数"<4GB 碰巧对"形态规范化。
- trampoline 调 libc 时 sp 的 8 字节对齐(quirk 路径)未系统验证。
- g 槽表满(64 线程)行为:当前跳过写,可加诊断。
