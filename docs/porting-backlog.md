# 移植候选清单（backlog）

> **本文件只放"还没做的"和"判死的"。**
>
> **✅ 已完成(2026-11-19):设备端 Go 工具链编译 tailcat**(终极自举验证)。
> A6X 上 40 分钟编出 20.3MB 完整 tailcat(全依赖图),`--help` 正常。
> 方法与墙见 [go.md](go.md) §六;顺带清完 Go 移植全部遗留(trampoline
> 审计/64 位参数规范化/g 槽诊断/墙 #8 libc 声明)。
> 已上线的包，详情在各自的 `docs/<pkg>.md` 专项文档里（索引见下）。
>
> 2026-11-14 从 BigBoss 索引盘点产生（分析底稿：`~/scratch/bigboss/bigboss.db`，
> 索引 9973 包、Tweaks/Themes/Addons 已分区；主表 = 独立程序 2236）。
> 状态流转：候选 → 进行中 → 完成（deb 入 `out/` + `repo/pool`）。
> 方法论：BigBoss 老 deb 当"iOS 可行性证据 + ABI 说明书"（`llvm-otool -L`
> 看 `LC_LOAD_DYLIB`），移植时一律拉**上游新版**（lsof 4.78→4.99.7 同款思路）。

## 已上线（全部有专项文档）

设备 kit 现有 **28 个包**（30 个 deb 文件，python3 有两个版本号，
含一个被取代的旧版）。

| 包 | 版本 | 专项文档 | 备注 |
|---|---|---|---|
| tmux | 3.8 | [tmux.md](tmux.md) | **第一个移植**，基建源头 |
| vim | 9.1.0000 | [vim.md](vim.md) | 终端类模板（六道 WALL） |
| git | 2.51.2 | [git.md](git.md) | 手写 config.mak |
| curl | 8.16.0 | [curl.md](curl.md) | 静态 OpenSSL |
| wget | 1.25.0 | — | 双签名约定的出处 |
| openssh | 10.6p2 | [openssh.md](openssh.md) | 22226 验证口 |
| dropbear | 2026.94 | [dropbear.md](dropbear.md) | 唯一 sshd（22 口） |
| nginx | 1.31.9 | [nginx.md](nginx.md) | 设备侧已停用 |
| mosh | 1.4.0 | [mosh.md](mosh.md) | Termius 验证通过 |
| netstat | 1.0 | [netstat.md](netstat.md) | **自研**，ABI 全实测 |
| nmap | 7.95 | [nmap.md](nmap.md) | **侵入性最强**（八道墙） |
| tcpdump | 4.99.5 | [tcpdump.md](tcpdump.md) | 含 libpcap |
| lsof | 4.99.7 | [lsof.md](lsof.md) | libproc 路线 |
| tor | 0.4.8.14 | [tor.md](tor.md) | 全静态栈 |
| rsync | 3.3.0 | [rsync.md](rsync.md) | 增量同步验证 |
| sqlite | 3.54.1 | [sqlite.md](sqlite.md) | 不用 configure |
| ffmpeg | 9.0.2 | [ffmpeg.md](ffmpeg.md) | 远期最大工程 |
| openssl | 4.0.3 | [openssl.md](openssl.md) | 带汇编 |
| p7zip | 17.05 | [p7zip.md](p7zip.md) | — |
| jq | 1.7.1 | [jq.md](jq.md) | 含 oniguruma |
| whois | 5.6.6 | [whois.md](whois.md) | 最干净（零补丁） |
| less | 668 | [less.md](less.md) | ncurses 走 vim 先例 |
| make | 4.4.1 | [make.md](make.md) | 设备端重建 |
| class-dump | 3.5.2 | [class-dump.md](class-dump.md) | 真实 SDK 破局 |
| uuidgen | 1.47.2 | [uuidgen.md](uuidgen.md) | 替代 BigBoss uuid |
| node | 22.23.4 | [node.md](node.md) | jitless |
| python3 | 3.13.18 | [python.md](python.md) · [python3.md](python3.md) | 含 ssl/sqlite3 |
| python314 | 3.14.10 | 同上 | 与 3.13 并存 |
| tailcat | 0.7.0 | [tailcat-porting.md](tailcat-porting.md) · [tailcat.md](tailcat.md) | 首个完整 Go 程序;设备端自举编译 ✓ |
| go | 1.27.2 | [go.md](go.md) | **TESTING ONLY**;设备端工具链 |
| tailscale | 1.104.7 | [tailscale.md](tailscale.md) | 全链路验证,userspace-netstack |
| pgrep/pkill | 1.0 | [pgrep.md](pgrep.md) | OpenBSD 血统,sysctl 路线(-f 需 root) |
| ping | 1.0 | [ping.md](ping.md) | 自写;setuid root(ICMP 投递策略实测) |
| ifconfig + route | network_cmds-457 | [ifconfig.md](ifconfig.md) | Apple 正版;-DPRIVATE + xnu-3789 内核头(§23 模式);iproute2 无 Darwin 版 |
| arp/ndp | network_cmds-457 | [ifconfig.md](ifconfig.md) | 并入 ifconfig4 457-2;三次单行改动(§2.1) |
| traceroute | 1.0 (network_cmds-457) | [traceroute.md](traceroute.md) | Apple 正版;-DPRIVATE + xnu-3789 内核头;setuid 4755(SOCK_RAW);上游仅 1 单行改动 |
| dig/nslookup/host | 1.0 | [dns.md](dns.md) | 自研 stub 解析器;设备 DNS 客户端 0→3 |
| tree/watch/realpath/hexdump | 1.0 | [smalltools.md](smalltools.md) | 小件四连,一包带走 |
| pgrep -f | 1.1 | [pgrep.md](pgrep.md) | 4 元 mib bug 翻案;PROCARGS2 权限模型落文档 |

**未能凑齐专项文档的**：wget（信息散落在 `docs/curl.md` §4 的签名教训里）。

## 进行中

（暂无）

## 已完成

- **Go 1.27.2 darwin/arm32 移植**：**✅ 2026-11-17 真机验证通过**。
  用户 2026-11-16 拍板开工（"Go 移植开干"），2026-11-15 立项侦察；
  实际耗时约 22 小时（其中大半花在设备活体调试上）。
  - 成果：宿主 go1.27.2 交叉产出可运行的 `Mach-O armv7`，
    hello world + goroutine + time + sort 在 iPad4 实测通过（exit 0）。
  - 规模：改 7 个文件 + 新增 12 个（runtime 6 / syscall 6），
    补丁 618 行。
  - **专项文档**：`docs/go.md`（14 个坑 → 根因 → 复现方法）。
  - **进展流水账**：`~/ios-armv7-builder/tmp/GO-STATE.md`（历史全过程）。
  - 移植代码**不入库**（宿主侧工具链，非设备包），保存在
    `~/scratch/go-port/`。
  - 遗留（独立工作，未做）：设备端 `go build` 需要先补
    vendored `golang.org/x/sys/unix` 的 darwin/arm 类型定义。
- ffmpeg 已于 2026-11-15 完工上线。
- tailcat 已于 2026-11-19 完工上线。
- tailscale 已于 2026-11-19 完工上线。

## 判死 / 排除

- **syslogcmdline**：实为 `syslogon`/`syslogoff` 两个开关包装，launchctl
  两行可替代，不值得移植（2026-11-14 验明）。
- **BigBoss `uuid` 1.6.0-2p（ossp-uuid）**：设备存量包，CLI `/usr/bin/uuid`
  在 iOS 10.3.3 上 dyld 解析 libgcc_s re-export 失败，Abort trap 6
  （2026-11-15 三次复现）。不修不依赖，由自研 `uuidgen` 包替代
  （见 `docs/uuidgen.md`）。
- **msmtp / vsftpd**：用户 2026-11-15 裁掉（不做）。
- **nano / dialog、adv-cmds 家族**：用户裁掉（nano/dialog 不需要；adv-cmds
  设备基础 userland 已有）。
- 全部 GUI/游戏/中文商业包（触动精灵/天下游/Filza…）、Theos 与
  on-device toolchain（与跨编译哲学相反）、mSpy（间谍件）。

## 已完成的结构性基建

- **iPhoneOS10.3.sdk 头整合**：阶段 1（共存验证）用 whois（Makefile 型）
  与 rsync（configure+gnulib 型）两只金丝雀完成；**阶段 2 已拍板
  （2026-11-15）**：新移植默认走 SDK 模式（仓库 AGENTS.md 工作规则 5），
  存量包不重编。用法与坑见 `docs/toolchain.md` §16。
