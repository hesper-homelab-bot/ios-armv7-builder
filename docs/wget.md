# wget 1.25.0 移植专项（armv7 iOS 10.3.3）

> 包：`wget4_1.25.0-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`wget/build.sh`
> **本文特别重要**：wget 确立了**双签名约定**，那是全套打包脚本的模板。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 1.25.0 |
| 包名 | `wget4_1.25.0-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/wget` |
| 依赖 | **自编 OpenSSL 4.0.3 静态库**（同 curl） |
| 审计 | ✅ **261/261 全绿**（修复 4 个桩之后） |

**建模来源**：本移植**以 `curl/build.sh` 为模板**——同一个 sysroot、
同一个编译器 wrapper、同一类问题。

## 2. ★★ 双签名约定（后续所有打包脚本的模板）

wget 确立了这套约定，之后的 **curl / git / nmap / nginx / python3** 等
都照抄：

> **宿主打 payload 时签一次**，**`postinst` 在设备上用设备自己的 ldid
> 再签一次**。

**为什么**：宿主产出的签名**偶尔在设备上 exec 失败**——症状是
**SIGKILL 且无崩溃报告**。

> ⚠️ **关于"宿主 ldid 不可靠"这条传说的真相**：见 `docs/curl.md` §4
> ——**不是 ldid 不可靠，而是签名失败被 `|| true` 吞掉了**。
> 但**双签名本身仍然值得保留**（设备侧签名始终可靠，成本极低）。

**与用户级准则呼应**（`~/.dsh/AGENTS.md`）：
**无崩溃报告的 SIGKILL = 签名/内核策略问题**，优先查签名。

## 3. 构建要点

| 项 | 说明 |
|---|---|
| 建模 | `curl/build.sh`（同款 sysroot / wrapper / 问题类） |
| OpenSSL | 静态链接 `libssl.a` + `libcrypto.a`，**无运行期共享依赖**，不碰 `/usr` |
| `IOS_STUBDIR` | **`libSystem.tbd` 住在 `~/ios-tool` 而不是仓库里**——理由：**仓库是公开的，Apple 构建的桩不再分发** |
| 交叉 | `CROSS_TOP` / `CROSS_SDK` 指向我们的 sysroot |

## 4. ★ 探针修正：为什么用 `config.site` 而**不是** `--cache-file`

`configure` 的链接探测在此**必然"成功"**（`-undefined dynamic_lookup`），
而**运行期探测在交叉编译时无法执行**。`ios-config.site` **同时修正这两类谎言**。

> **必须是 `config.site`，不能用 `--cache-file`**：
> **autoconf 在每次运行结束时都会重写 cache 文件**，
> 手工编辑的 cache 值**只能存活一次运行**。

（同类思路见 `docs/rsync.md` §6 的独立 `export` 行；
`sites` 里的探针压制清单与 curl 同类。）

## 5. 修复：4 个 unlocked / locking 符号

全新构建时曾报 **4 个符号未决**：

```
fflush_unlocked
fputs_unlocked
fread_unlocked
__fsetlocking
```

这些都是 **glibc 的 `_unlocked` 变体**，设备 libSystem 没有。

**修法**（已完成）：**重建 `libios-compat.a`**（含这 4 个桩），
之后 wget **261/261 审计全绿**。

> 这类桩的统一说明见 `docs/toolchain.md`（`libios-compat.a` 优雅降级桩）。

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `wget/build.sh` | 构建（建模自 curl） |
| `wget/ios-config.site` | 探针修正（**必须是 config.site**） |
| `wget/make-deb.sh` | 打包（**双签名约定的原始出处**） |
| `docs/curl.md` §4 | 双签名传说的真相 |
| `sysroot-overlay/usr/lib/libios-compat.a` | 4 个 unlocked 桩 |
