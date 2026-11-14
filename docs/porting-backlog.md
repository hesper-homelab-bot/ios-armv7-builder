# 移植候选清单（backlog）

> 2026-11-14 从 BigBoss 索引盘点产生（分析底稿：`~/scratch/bigboss/bigboss.db`，
> 索引 9973 包、Tweaks/Themes/Addons 已分区；主表 = 独立程序 2236）。
> 状态流转：候选 → 进行中 → 完成（deb 入 `out/` + `repo/pool`）。
> 方法论：BigBoss 老 deb 当"iOS 可行性证据 + ABI 说明书"（`llvm-otool -L`
> 看 `LC_LOAD_DYLIB`），移植时一律拉**上游新版**（lsof 4.78→4.99.7 同款思路）。

## 已上线

设备现有 18+ 包（kit 清单见 `repo/pool` 与 AGENTS.md 索引各专项文档）。
2026-11-14：netstat4 重建（gzip 修复）、p7zip17 上线。

## 进行中（2026-11-14 批次）

- **rsync**：部署刚需（现在全靠 scp）。上游 3.3.x，popt/zlib 源内自带，
  configure 交叉需处理探针缓存。
- **whois**：rfc1036/whois，单目录小项目，零依赖。
- **less**：curses 头已随 vim 进 sysroot；链接走 vim 先例
  （`$HOME/ios-tool/device-libs/libncursesw.5.dylib`，cc-wrapper 会吞
  `-lncursesw` 所以必须显式给 dylib）。

## 已立项待开工（用户 2026-11-14 拍板"先记录"）

- **tor**：需 libevent——cc-wrapper 已有 `-levent` 通道（`IOS_PREFIX`）。
  BigBoss 先例 `fm.was.tor 0.2.6.10` / `Mobile Tor 0.2.2.35`。拉上游新版。
- **class-dump**：设备端 dump ObjC 类，与 debugserver/lldb 工作流互补；
  ObjC runtime 设备自带。源码老（code.google 时代），需找可用镜像
  （github 有 fork 群）。
- **make**：设备端现场重编小工程；GNU make 极小，零依赖。

## 待表态（用户未点头，不动）

- **msmtp**：SMTP 客户端。deps libgsasl/libidn/openssl——openssl4 已有，
  裁掉 SASL 可省俩依赖。
- **vsftpd**：FTP 服务端，**零依赖**，最容易移植。

## 远期（难度高，最后）

- **ffmpeg**：armv7 + iOS 10 老内核 + 全编解码器，工程量最大。
  BigBoss 先例 `com.nin9tyfour.ffmpeg 2.6.1-1`（2015 上游）证明可行。

## 判死 / 排除

- **syslogcmdline**：实为 `syslogon`/`syslogoff` 两个开关包装，launchctl
  两行可替代，不值得移植（2026-11-14 验明）。
- nano / dialog、adv-cmds 家族：用户裁掉（nano/dialog 不需要；adv-cmds
  设备基础 userland 已有）。
- 全部 GUI/游戏/中文商业包（触动精灵/天下游/Filza…）、Theos 与
  on-device toolchain（与跨编译哲学相反）、mSpy（间谍件）。
