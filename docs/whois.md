# whois 5.6.6 移植专项（armv7 iOS 10.3.3）

> 包：`whois4_5.6.6-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`whois/build.sh`
> 本文记录**"最干净的移植"是怎么做到的**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 5.6.6（rfc1036/whois） |
| 包名 | `whois4_5.6.6-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/bin/whois` |
| 特点 | **零探针覆盖、零补丁** —— 迄今**最干净的移植** |
| 验收 | ✅ 设备实弹查询验证 |

另：whois 是 **SDK sysroot 模式阶段 1 的两只金丝雀之一**
（Makefile 型构建系统的代表），见 `docs/toolchain.md` §16。

## 2. 为什么这么干净

### 2.1 自带正确的平台检测

`config.h` 通过**预定义宏**做平台检测，并且**有一个正经的
`__APPLE__ && __MACH__` 分支**。

**NLS 自动保持关闭**：`ENABLE_NLS` 被 `__GLIBC__` / `__FreeBSD__` 门控，
而 armv7-apple-ios 上两个都**没有定义**。

### 2.2 数据列表在编译期进头文件

`tld_serv`、`ip_del` 等数据列表通过**自带的 perl 脚本**在构建期生成成
头文件 —— **没有需要随包发布的运行期数据文件**。

### 2.3 可选依赖天然关闭

`iconv` / `libidn` / `crypt` 都是 **opt-in**（默认不开），我们保持 opt-out：

- **`PKG_CONFIG` 指向 `/bin/false`** —— 阻断宿主的 pkg-config 自动探测
  **把宿主的 `-I`/`-L` 泄漏进交叉构建**
- `HAVE_ICONV` 不设置

> `PKG_CONFIG=/bin/false` 是个**值得复用的技巧**：交叉构建时防宿主
> pkg-config 污染。

## 3. 源码

```sh
git clone --depth 1 https://github.com/rfc1036/whois
# commit 54d60d8
```

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `whois/build.sh` | 构建（干净路径的完整说明） |
| `whois/make-deb.sh` | 打包 |
| `docs/toolchain.md` §16 | SDK sysroot 模式（whois 是金丝雀之一） |
