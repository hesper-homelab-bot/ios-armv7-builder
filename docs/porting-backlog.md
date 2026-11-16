# 移植候选清单（backlog）

> **本文件只放"还没做的"和"判死的"。**
> 已上线的包，详情在各自的 `docs/<pkg>.md` 专项文档里（索引见下）。
>
> 2026-11-14 从 BigBoss 索引盘点产生（分析底稿：`~/scratch/bigboss/bigboss.db`，
> 索引 9973 包、Tweaks/Themes/Addons 已分区；主表 = 独立程序 2236）。
> 状态流转：候选 → 进行中 → 完成（deb 入 `out/` + `repo/pool`）。
> 方法论：BigBoss 老 deb 当"iOS 可行性证据 + ABI 说明书"（`llvm-otool -L`
> 看 `LC_LOAD_DYLIB`），移植时一律拉**上游新版**（lsof 4.78→4.99.7 同款思路）。

## 已上线（全部有专项文档）

设备 kit 现有 **27 个包**（29 个 deb 文件，python3 有两个版本号，
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
| nginx | 1.26.3 | [nginx.md](nginx.md) | 设备侧已停用 |
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

**未能凑齐专项文档的**：wget（信息散落在 `docs/curl.md` §4 的签名教训里）。

## 进行中

**（暂无）**

## 待表态（用户未点头，不动）

- **node JIT（内核 patch 级）**：**用户 2026-11-15 判死**（"有那精力不如
  研究 Go 移植"）。用户态路线全灭实验证据链 `docs/node.md`（entitlement×2
  / RWX 直建 / vm_remap 四路全 SIGBUS）。
- **Go 最新版移植（1.27.x，darwin/arm32 复活）**：2026-11-15 立项侦察。
  基建级：编译器后端（gc arm）健在（linux/arm 是 tier-1），缺的只是
  darwin 薄层 6-8 文件（os/rt0/signal/sys_darwin_arm）零残留——从
  darwin/arm64 的 libc 调用桩 × linux/arm 的 32 位 asm 拼装（Go 1.17+
  darwin runtime 全走 libc 调用，转写工整）+ cmd/link 的 macho32 +
  buildcfg 合法组合表。源码在 `~/go-sdk/go1.27.2/src`（tarball 自带）。
  预估 3-7 天级，风险点 = libc 调用约定细节（armv7 Darwin 的 struct
  return/vfp）与 ucontext 字段。
- **tailcat（Rust 复刻）**：用户 2026-11-15 裁掉（放弃 Rust，磁盘约束 +
  DERP/STUN/netstack 生态全空白需自写数周）。宿主侧 tailcat server +
  跨机 ping 已验证（`~/scratch/tailcat/`，server 已按用户指示关停，
  宿主可直接装官方包）。

## 远期（难度高，最后）

**（暂无——ffmpeg 已于 2026-11-15 完工上线。）**

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
