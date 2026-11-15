# 移植候选清单（backlog）

> 2026-11-14 从 BigBoss 索引盘点产生（分析底稿：`~/scratch/bigboss/bigboss.db`，
> 索引 9973 包、Tweaks/Themes/Addons 已分区；主表 = 独立程序 2236）。
> 状态流转：候选 → 进行中 → 完成（deb 入 `out/` + `repo/pool`）。
> 方法论：BigBoss 老 deb 当"iOS 可行性证据 + ABI 说明书"（`llvm-otool -L`
> 看 `LC_LOAD_DYLIB`），移植时一律拉**上游新版**（lsof 4.78→4.99.7 同款思路）。

## 已上线

设备 kit 现有 **26 包**（清单见 `repo/pool` 与 AGENTS.md 索引各专项文档）。
2026-11-14：netstat4 重建（gzip 修复）、p7zip17、rsync4、whois4、less4、
make4、tor4、class-dump4 依次上线（当日 T1/T2 批次全清）。
2026-11-15：**uuidgen 1.47.2-1** 上线（e2fsprogs misc/uuidgen.c，SDK 模式
拍板后首个新移植；BigBoss `uuid` CLI 在 iOS 10.3.3 上 dyld 必死，本包
替代之——死因与 "SDK 头 availability ≠ 设备现实" 结论见
`toolchain.md` §17）。
2026-11-15：**ffmpeg 9.0.2-1** 上线（**远期最大工程清仓**，全内置编解码器
静态 ffmpeg+ffprobe，deb 19MB；构建雷区与验收全录 `toolchain.md` §18）。

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
  验收；用法与坑见 `toolchain.md` §16。**阶段 2 已拍板（2026-11-15）**：
  新移植默认走 SDK 模式（规则见仓库 AGENTS.md 工作规则 5）；存量 24 包
  不重编。
- **python3（CPython 3.14.x）**：用户 2026-11-15 立项。SDK 模式。预研点：
  ① configure 交叉四板斧 + ac_cv 压制（dynamic_lookup 恒真）；
  ② CPython 交叉编译经典坑——host python3 编译 parse/pgen 生成器
  （`--build/--host` 分离 + 宿主 python3 提供 BUILDPYTHON）；
  ③ 依赖取舍：openssl（接已有静态 4.0.3）、zlib（已有）、readline/ncurses
  （设备 libncursesw.5.dylib）、expat（自编或 --without-system-expat 内置）、
  libffi/ctypes（可 `--disable-ctypes` 类开关砍掉，需要时再补）；
  ④ stdlib 纯 Python 部分无移植问题，C 扩展逐个过审计门禁。
  产出：`python3` + `pip`（ensurepip 可选）。

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

（暂无——ffmpeg 已于 2026-11-15 完工上线，见"已上线"。）

## 判死 / 排除

- **syslogcmdline**：实为 `syslogon`/`syslogoff` 两个开关包装，launchctl
  两行可替代，不值得移植（2026-11-14 验明）。
- **BigBoss `uuid` 1.6.0-2p（ossp-uuid）**：设备存量包，CLI `/usr/bin/uuid`
  在 iOS 10.3.3 上 dyld 解析 libgcc_s re-export 失败，Abort trap 6
  （2026-11-15 三次复现）。不修不依赖，由自研 `uuidgen` 包替代。
- **msmtp / vsftpd**：用户 2026-11-15 裁掉（不做）。
- nano / dialog、adv-cmds 家族：用户裁掉（nano/dialog 不需要；adv-cmds
  设备基础 userland 已有）。
- 全部 GUI/游戏/中文商业包（触动精灵/天下游/Filza…）、Theos 与
  on-device toolchain（与跨编译哲学相反）、mSpy（间谍件）。
