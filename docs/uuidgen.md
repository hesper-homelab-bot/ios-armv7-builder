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

（死因分析见本文 §7，原载 `docs/toolchain.md` §17，
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
| 本文 §7 | 死因分析（availability ≠ 现实；2026-11-20 自 toolchain §17 迁入） |

## 7. 死因分析全录（2026-11-20 自 toolchain §17 原文迁入）

## 17. 设备 UUID 复测：SDK 头 availability ≠ 设备现实（2026-11-15）

三路实测（探针源码 `~/scratch/uuid-probe/`，二进制部署三件套签名）：

- **libSystem `uuid_*` API 全正常**：uuid_generate（连续 3 次互异 v4）、
  generate_random、parse/unparse 往返 rc=0，root/mobile 双身份各过。
- **内核 `gethostuuid()` 头标 `__IPHONE_NA`，设备符号却存在且可用**：
  dlsym(RTLD_DEFAULT) 拿到、调用成功，返回稳定主机 UUID（两次一致）。
  **结论：SDK 头的 availability 标注不是设备事实。** 以后遇到"头说
  iOS 没有"的函数（`__IPHONE_NA` / `__OSX_AVAILABLE` 系），先 dlsym
  复核符号在不在，再决定 shim/放弃，不要按头文件宣判。
- **BigBoss `uuid` 1.6.0-2p 的 `/usr/bin/uuid` CLI 是死的**：dyld 解析
  `libgcc_s.1.dylib` 经 libSystem.B 的 re-export 失败，Abort trap 6
  （三次复现）。2008 年老包兼容性烂，与设备 UUID 体系无关。
- **填补**：仓库第 25 包 `uuidgen`（e2fsprogs 1.47.2 misc/uuidgen.c，
  SDK 模式首移植，`uuid/build.sh`）。默认/-r v4、-t v1 实弹验证通过；
  `uuid_unparse` 大写输出是 e2fsprogs 上游行为。安装后注意：设备
  登录 shell PATH 只有 `/usr/bin:/bin`，`/var/mobile/tools/bin` 下的
  工具（含 uuidgen/node）日常要走绝对路径或自行 alias——既有环境
  现状，非本包问题。
