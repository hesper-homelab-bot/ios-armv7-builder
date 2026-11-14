# p7zip 17.05 移植专项（7za / armv7 / iOS 10.3.3）

> 2026-11-14 完成并设备验收。脚本：`p7zip/build.sh`（交叉编译）+
> `p7zip/make-deb.sh`（打包）。工具链通用规则见 `toolchain.md`。

## 动机（A/B 实证）

设备预装的 `p7zip 4.57-3p`（2007 年，越狱源）解不开现代压缩包：宿主机
7zz 23.01 建的 LZMA2 档案，4.57 直接失败。17.05 支持 LZMA2 / xz /
AES-256，且这个 fork（p7zip-project）额外内置 zstd / lz4 / lizard / lz5 /
brotli 解码器。

## 源

- **p7zip-project/p7zip tag v17.05，commit `a45b883`**（git clone）。
- Sourceforge 与 Debian pool 的经典 16.02 直链在本机全部拿到 HTML 占位页
  （51KB / 300B，`tar` 静默失败——**下载后必须 tar -t 验证，别信文件名**）；
  codeload tarball 也超时。git clone 走通了（网络慢，~10 分钟）。

## 构建配方（build.sh）

- 目标：`make 7za`（= `CPP/7zip/Bundles/Alone`）——**全部编解码器静态内置**，
  无 7z.so、无 dlopen、无归档步骤（对象直接链接，`tools/darwin-ar` 都用不上）。
- **makefile 基底：`makefile.linux_any_cpu`，不是 macosx 变体**。macosx_32bits
  带 `-m32`（穿过滤镜直达 clang，与 armv7 target 相冲）、`-DENV_MACOSX`、
  `-framework CoreFoundation`——全是反面教材；`linux_cross_arm` 变体证明
  ARM 除 any_cpu 已有 flag 外**无需任何特殊化**。
- 对 any_cpu 的三处偏差：
  1. `OPTFLAGS=-O -s` → `-O2`：`-s` 是链接期 strip 旗标，cc-wrapper 的链接行
     只透传 `-L/-l/-Wl,`，`-s` 永远到不了 ld64，纯噪音；
  2. 去掉 `-D_7ZIP_LARGE_PAGES`：iOS 无 hugetlb 大页机制，macosx 变体本就
     不定义它；
  3. `CXX/CC` 指向 `cxx-wrapper.sh` / `cc-wrapper.sh`（`-lpthread` 被包装器
     吸收进 libSystem，`LOCAL_LIBS` 留着无害）。
- `-lpthread` 吸收、`-undefined dynamic_lookup`、libios-compat.a 兜底均为
  既有机制，p7zip 全程零补丁。
- 编译实际用 `-std=gnu++11`（makefile.common 指定），LLVM15 libc++ 头 +
  设备 libc++ ABI，无异常/可用性标注问题。

## 打包（make-deb.sh）

- 包名 **`p7zip17`，版本 `17.05-1`**：预装老包字面叫 `p7zip 4.57-3p`，
  同名会撞 dpkg；分开命名可共存。
- 载荷：`/var/mobile/tools/p7zip/7za`（真身，root:wheel，host `ldid -S`
  签名 + `ldid -e` 断言）+ `/var/mobile/tools/bin/{7za,7z}` 符号链接
  （prerm 守卫式清理）。老包 dpkg 拥有的 `/usr/bin/{7z,7za}` **不动**。
- 压缩成员 **gzip**（toolchain.md §14.7 铁律，`-Zgzip --root-owner-group`）。
- deb sha256：`d410749941eb58c78c6d50bf3ffa6efdbc6f562ec9e72195beb4dacd42ced1a0`
  （1.6MB）；签名后二进制 sha256：
  `1a61289f93b622cfec9556585267c424f1a53397e97dd4891f173cde0105e7a5`（3.2MB）。

## 设备验收（全部通过，2026-11-14）

| 项 | 结果 |
|---|---|
| 横幅 | `7-Zip (a) [32] 17.05`，armv7 PIE |
| A/B 对照 | 旧 4.57 解 23.01 建的 LZMA2:x9 包 → **失败**（预期）；新版 → 内容逐字一致 |
| AES-256 | `-pSecret123 -mhe=on` 档案解密还原一致；错密码拒绝 |
| xz | 解压还原一致 |
| PATH | 登录 shell 解析到 `/var/mobile/tools/bin/7za`（新版）；非登录 shell
  （PATH=/usr/bin:/bin）仍得旧 4.57——与 DEVICE.md §3 的约定一致 |
| 仓库 | `scripts/make-repo.sh` 已收录（repo/pool/main/p/p7zip17/），共 18 包 |

## 回滚

`dpkg -r p7zip17`：prerm 摘掉 tools/bin 两个符号链接，dpkg 移除
`/var/mobile/tools/p7zip/`。老包 `p7zip 4.57-3p` 与 `/usr/bin/*` 全程未动。
