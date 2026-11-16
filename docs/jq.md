# jq 1.7.1 移植专项（armv7 iOS 10.3.3）

> 包：`jq_1.7.1-2_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`jq/build.sh`
> 本文记录**三层依赖、libtool 的两个陷阱、以及 `__exp10` 的实测修正**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | jq 1.7.1（+ **oniguruma 6.9.10**） |
| 包名 | `jq_1.7.1-2_iphoneos-arm.deb`（`-2` 为 `_pow10` 修复后重建） |
| 安装路径 | `/var/mobile/tools/bin/jq` |
| 审计 | ✅ **143/143 全绿**（`tools/audit-all.sh`） |

## 2. 依赖链

```
oniguruma 6.9.10  →  libonig.a（正则引擎）
        ↓
jq 1.7.1          →  静态链接 libonig
```

**jq 1.7 丢掉了自带的 oniguruma**，所以 `libonig` 要**先交叉构建**。
两者都是纯 C；这里的墙**全是工具链形态的**。

## 3. 坑

### 3.1 libtool 的 `.la` 记录了安装目录 → relink 逻辑嗌死

oniguruma 由 libtool 生成的 `libonig.la` 会**记录自己的安装目录**。
用 `DESTDIR` 安装来收取 `.a` 时，`.la` 里仍写着 `/var/mobile/tools`，
于是 libtool 的 **"moved library" relink 逻辑**被触发并噎住
（`eval` 语法错误）。

**修法**：把裸的 `libonig.a` + 头文件**拷进一个干净目录**，
`--with-oniguruma` 指向它——**视野内没有 `.la`**。

### 3.2 libtool 想建共享库

`--mode=link` 想构建共享的 `libjq.dylib`（`-Wl,-soname …`）。
那条路在这个设备上毫无用处，工具链也用不上。

**修法**：`--disable-shared --enable-static` 让 libtool 老实待在 `.a` 世界，
jq 静态链接 libonig。

### 3.3 ★ `exp10` → `__exp10`：**实测修正**

jq 的 `builtin.c` **无条件**把 `exp10` 重定向到 Apple 的 `__exp10`：

```c
#define exp10 __exp10
```

这在真 Darwin 上没问题，**但 musl 的 `math.h` 没有它的声明**。

**处理**：在设备上**实测验证** `__exp10` 确实存在
（`__exp10(2.0) == 100.0`），**然后**把声明加进
`sysroot-overlay/usr/include/math.h`。

> **方法论**：**先探针确认符号真在设备上，再补声明**——
> 而不是反过来假设"Darwin 有的 iOS 也有"（那正是 `docs/toolchain.md` §17
> "availability ≠ 现实"的教训）。

### 3.4 `_pow10` 仿真（审计发现）

全量符号审计发现 jq 引用 `_pow10`，在 `libios-compat.a` 里加了**忠实仿真**
（`pow(10, x)`），jq 已重建，**143/143 审计全绿**。

## 4. 源码获取

```
oniguruma: github.com/kkos/oniguruma releases（v6.9.10）
jq:        github.com/jqlang/jq releases（jq-1.7.1）
```

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `jq/build.sh` | 构建（三层依赖 + libtool 陷阱） |
| `jq/make-deb.sh` | 打包 |
| `sysroot-overlay/usr/include/math.h` | `__exp10` 声明（实测后补） |
| `tools/audit-all.sh` | 全量符号审计 |
