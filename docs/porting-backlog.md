# 移植候选清单（backlog）

> 2026-11-14 从 BigBoss 索引盘点产生（分析底稿：`~/scratch/bigboss/bigboss.db`，
> 索引 9973 包、Tweaks/Themes/Addons 已分区；主表 = 独立程序 2236）。
> 状态流转：候选 → 进行中 → 完成（deb 入 `out/` + `repo/pool`）。
> 方法论：BigBoss 老 deb 当"iOS 可行性证据 + ABI 说明书"（`llvm-otool -L`
> 看 `LC_LOAD_DYLIB`），移植时一律拉**上游新版**（lsof 4.78→4.99.7 同款思路）。

## 已上线

设备现有 18+ 包（kit 清单见 `repo/pool` 与 AGENTS.md 索引各专项文档）。
2026-11-14：netstat4 重建（gzip 修复）、p7zip17 上线。

## 已上线（2026-11-14 批次，T1 完成）

- **rsync4 3.3.0-1**：增量同步设备验收 291B/2817×（改 1 加 1 只传增量）。
  过 ssh 用 `--rsync-path=/var/mobile/tools/bin/rsync`（非登录 shell PATH
  不含 tools/bin）。构建踩坑全记录见 `rsync/build.sh` 注释 +
  `toolchain.md` §15（dynamic_lookup 恒真探针、ac_cv 压制清单、
  configure 后断言）。
- **whois4 5.6.6-1**：零 override 零补丁（config.h 自带 __APPLE__ 分支，
  数据列表编译期进头文件）；设备实弹查询验证。
- **less4 668-1**：ncurses 走 vim 先例（设备 libncursesw.5.dylib 显式
  上链接行）；release tarball 补齐 git 树缺的生成物；设备翻页冒烟过。
- **tor4 0.4.8.14-1**（2026-11-14 深夜）：全静态栈（libevent 2.1.12 +
  OpenSSL 4.0.3 + zlib 1.3.1），**249 个未定义符号全部设备实测绑定**；
  设备 `--version` / `--verify-config` 验收过。踩坑全记录见
  `tor/build.sh` 注释（ac_cv 压制 20+ 项、configure 探针跑宿主 gcc 的
  断链事故、iOS 10 的 zlib 不在 libSystem 等四板斧实例）。源：Debian
  pool 的 tor_0.4.8.14.orig.tar.gz（dist.torproject.org 与 GitHub 镜像
  均不可用/只有 alpha tag）。

## 挡板（有明确破局点，待下批次）

- **class-dump**：76 个 ObjC 源全部依赖 pch 里的 `<Foundation/Foundation.h>`，
  而本工具链从未有过 iOS SDK 头（设备不带头文件，sysroot 也没有）——
  编译期就挡住，与 Mach-O 解析能力无关。
  **破局点（用户 2026-11-14 指出）**：github.com/xybp888/iOS-SDKs 收录
  **iPhoneOS10.3.sdk**（与设备精确同版本！），Foundation 头 + 官方全量
  tbd 符号表可一并解决 class-dump 编译与审计白名单精度；长期看还是
  手写 sysroot 头（NULL 缺口/getopt 签名/net 头拼装）的官方替代参考。
  待做：sparse clone 只拉 iPhoneOS10.3.sdk 子目录（文件量大，后台进行）。

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
