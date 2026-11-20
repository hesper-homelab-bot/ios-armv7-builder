# GNU make 4.4.1 移植专项（armv7 iOS 10.3.3）

> 包：`make4_4.4.1-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`make/build.sh`
> 本文记录**用途、探针压制、以及归档格式那个"自相矛盾的警告"**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 4.4.1 |
| 包名 | `make4_4.4.1-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/make/make`（`bin/` 下有软链） |
| 依赖 | **零外部依赖**（NLS 关：设备无 gettext；guile 关） |
| 审计 | ✅ `check-undefined.sh` 通过 |

**用途**：**设备端就地重建小项目**，免去往返宿主机的麻烦。

> 这也是很多**设备侧操作**的前提——需要注意的是，root 非登录 shell 的
> `PATH` 只有 `/usr/bin:/bin`，用 `make` 这类 tools/bin 下的工具时
> **要给绝对路径**（或显式 `PATH=`）。

## 2. 探针压制

| 符号 | 为什么 |
|---|---|
| `eaccess` | **glibc 的同义词**（= `faccessat`/`access`），**设备 libSystem 没有**。恒真探针会把它放进 gnulib 的 `findprog-in` → **压掉，走 `access` 回退** |
| `memrchr` | 设备没有 |

（`dynamic_lookup` 恒真探针陷阱见 `docs/toolchain.md` §8。）

## 3. ⚠️ 归档格式：那个自相矛盾的警告

**必须** `AR`/`RANLIB` 用 darwin 变体：

```sh
make -j"$(nproc)" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib"
```

**如果不这样**，GNU ar 归档会被 ld64 **整体无视**，并打出这条
**自相矛盾**的警告：

```
ignoring file ... building for iOS-armv7 but attempting to link with
file built for iOS-armv7
```

（"为 iOS-armv7 构建，却试图链接为 iOS-armv7 构建的文件"——听起来像废话，
**实为归档格式问题**。）

> 同族坑见 `docs/toolchain.md` §2。

## 4. configure 参数

```sh
ac_cv_func_eaccess=no \
ac_cv_func_memrchr=no \
CC="$root/tools/cc-wrapper.sh" \
CFLAGS="-O2 -D_POSIX_VERSION=200809L -D_CS_PATH=1" \
./configure --host=armv7-apple-darwin \
            --prefix=/var/mobile/tools/make \
            --disable-nls
```

## 5. 源码

```
https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz
```

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `make/build.sh` | 构建（压制 + 归档警告） |
| `make/make-deb.sh` | 打包 |
| `docs/toolchain.md` §2 | 归档格式（跨包通用） |
