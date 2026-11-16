# uuidgen 1.47.2 移植专项（armv7 iOS 10.3.3）

> 包：`uuidgen_1.47.2-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`uuid/build.sh`
> 本文记录**为什么自研替代 BigBoss 的 uuid、以及两个构建期垫片**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 1.47.2（取自 **e2fsprogs** 的 `misc/uuidgen.c`） |
| 包名 | `uuidgen_1.47.2-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/uuidgen/uuidgen`（`bin/` 下有软链） |
| 意义 | **SDK 模式拍板后的首个新移植** |

## 2. 为什么不用 BigBoss 的 `uuid`

**BigBoss `uuid` 1.6.0-2p（ossp-uuid）在 iOS 10.3.3 上是死的**：

```
CLI /usr/bin/uuid
    → dyld 无法解析 libgcc_s.1.dylib 经由 libSystem.B 的 re-export
        → Abort trap 6
```

**2026-11-15 三次复现**，确定不可修、不依赖，改由本包替代。

（死因分析见 `docs/toolchain.md` §17 的
"**SDK 头 availability ≠ 设备现实**"结论。）

## 3. 为什么我们这份能跑

**设备的 libSystem 的 `uuid_*` API 本身是好的**（同日用 `dlsym` + 探针验证）。

本 CLI 只是 `uuid_generate` / `uuid_generate_time` /
`uuid_generate_random` / `uuid_unparse` 的**薄前端**——这些符号在链接时
**留作未定义**（`-undefined dynamic_lookup`），**运行期从设备的 libSystem 解析**。

> 这与 BigBoss 那个包的失败形成对照：**问题从来不在 API，在那条
> libgcc_s re-export 链**。

## 4. 两个构建期垫片

`uuidgen.c` 需要 e2fsprogs 的构建环境，但我们**不跑它的 configure**，
只给最小垫片：

### 4.1 最小 `config.h`

```c
#define HAVE_STDLIB_H 1
```

> ⚠️ **不要定义 `HAVE_GETOPT_H`**：**iOS SDK 不带 `getopt.h`**，
> 而 `unistd.h` **已经声明了 `getopt`**。定义了反而会去找一个
> 不存在的头。

### 4.2 空操作 NLS 垫片（`support/nls-enable.h`）

```c
#define _(x)  (x)
#define N_(x) (x)
```

`ENABLE_NLS` 保持**未定义**，翻译宏直接透传。

## 5. 源码

```
e2fsprogs-1.47.2.tar.xz
  来源：https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.47.2/
  解包：tar -xf ... -C src --strip-components=1
  只取：misc/uuidgen.c
```

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `uuid/build.sh` | 构建（两个垫片 + 单文件编译） |
| `uuid/make-deb.sh` | 打包 |
| `docs/toolchain.md` §17 | 死因分析（availability ≠ 现实） |
