# 移植候选清单（backlog）

> 2026-11-14 从 BigBoss 索引盘点产生（分析底稿：`~/scratch/bigboss/bigboss.db`，
> 索引 9973 包、Tweaks/Themes/Addons 已分区；主表 = 独立程序 2236）。
> 状态流转：候选 → 进行中 → 完成（deb 入 `out/` + `repo/pool`）。
> 方法论：BigBoss 老 deb 当"iOS 可行性证据 + ABI 说明书"（`llvm-otool -L`
> 看 `LC_LOAD_DYLIB`），移植时一律拉**上游新版**（lsof 4.78→4.99.7 同款思路）。

## 已上线

设备 kit 现有 **24 包**（清单见 `repo/pool` 与 AGENTS.md 索引各专项文档）。
2026-11-14：netstat4 重建（gzip 修复）、p7zip17、rsync4、whois4、less4、
make4、tor4、class-dump4 依次上线（当日 T1/T2 批次全清）。

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

## 已上线（2026-11-14 深夜批次补完）

- **class-dump4 3.5.2-1**（nygard fork 2c82b4f）：**用户指出的
  xybp888/iOS-SDKs 破局兑现**——真实 iPhoneOS10.3.sdk（与设备精确同版本）
  的 Foundation/CoreFoundation/ObjC 头 + 官方全量 tbd（178 个 usr/lib
  + system 子库）入审计白名单。设备验收：宿主编一个 ObjC 测试程序
  （CDPTestWidget）部署后 class-dump 现场解剖出类/ivar/属性/方法全表。
  构建要点（`class-dump/build.sh` 注释全记录）：SDK 头世界一致性
  （-isystem SDK/usr/include 优先 + -F 双投递——cc-wrapper 补了 -F 通道）、
  MRC 的 __weak/weak 属性被 clang 词法层直认（宏无效，必须字面量 sed，
  且**弱引用大多住在 .h 里**——只扫 .m 会漏）、mach-o 平台常量 shim
  （10.3 SDK 早于 LC_BUILD_VERSION）、NeXT 时代 libc.h 摘除。

## 挡板（无）

（原"已立项待开工"的 tor / class-dump / make 已于 2026-11-14 深夜全部
完工上线，条目并入上方已上线节；可行性笔记在各 build.sh 注释。）

## 进行中（2026-11-15 立项）

- **iPhoneOS10.3.sdk 头整合**（结构性基建）：**阶段 1（共存验证）已完成**
  ——SDK 落位 `~/ios-tool/iPhoneOS10.3.sdk`，金丝雀 whois（Makefile 型）
  与 rsync（configure+gnulib 型）均以 SDK sysroot 重建并通过设备实弹
  验收；用法与坑见 `toolchain.md` §16。**阶段 2（默认切换）待拍板**：
  已上线 24 包为 musl sysroot 产物，切默认需分批重验。

## 待表态（用户未点头，不动）

（暂无）

## 远期（难度高，最后）

- **ffmpeg**：armv7 + iOS 10 老内核 + 全编解码器，工程量最大。
  BigBoss 先例 `com.nin9tyfour.ffmpeg 2.6.1-1`（2015 上游）证明可行。

## 判死 / 排除

- **syslogcmdline**：实为 `syslogon`/`syslogoff` 两个开关包装，launchctl
  两行可替代，不值得移植（2026-11-14 验明）。
- **msmtp / vsftpd**：用户 2026-11-15 裁掉（不做）。
- nano / dialog、adv-cmds 家族：用户裁掉（nano/dialog 不需要；adv-cmds
  设备基础 userland 已有）。
- 全部 GUI/游戏/中文商业包（触动精灵/天下游/Filza…）、Theos 与
  on-device toolchain（与跨编译哲学相反）、mSpy（间谍件）。
