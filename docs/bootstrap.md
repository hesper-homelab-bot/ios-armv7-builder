# 工具链自举(bootstrap-toolchain.sh)

一条命令搭起 `~/ios-tool`——本仓库所有交叉构建依赖的工具链(原本只能
"数小时踩坑"手工搭,2026-11-21 固化成脚本)。

```sh
tools/bootstrap-toolchain.sh                 # 全部阶段
tools/bootstrap-toolchain.sh --stage=3       # 从 stage 3 续跑
tools/bootstrap-toolchain.sh --check-only    # 校验一棵已存在的树
tools/bootstrap-toolchain.sh --prefix=/opt/ios-tool
Dockerfile                                   # docker build -t ios-armv7-toolchain .
```

## 阶段

| stage | 内容 | 产物 |
|---|---|---|
| 0 | apt 依赖(clang/llvm/lld/cmake/…) | 宿主工具 |
| 1 | conda-forge 交叉件 ×4(**sha256 已钉**) | `x-ld64/ x-cctools/ x-tapi/ x-libdispatch/` |
| 2 | ldid 构建(ProcursusTeam/ldid,sha256 已钉) | `bin/ldid` |
| 3 | iPhoneOS10.3.sdk(xybp888/iOS-SDKs 镜像,~80MB) | `iPhoneOS10.3.sdk/` |
| 4 | 本仓库自产件:`libSystem.tbd`(设备 10.3.3 对齐的裁剪桩)+ `cxx-wrapper.sh` | `$PREFIX/{libSystem.tbd,cxx-wrapper.sh}` |
| 5 | 冒烟:hello.c → armv7 Mach-O(PIE)+ ld64 依赖检查 | 通过即可用 |

## 已实证 / 待首跑

- **已实证**(2026-11-21,在现有 `~/ios-tool` 树上):`--check-only` 全绿;
  stage 5 冒烟产出 `Mach-O armv7 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>`;
  脚本的布局假设与 `docs/toolchain.md` §1 的 export 块逐字一致。
- **待首次全跑**(撰写时宿主网络限速 ~1-2KB/s,下载不现实):
  stage 1-3 的**全新下载**路径。sha256 钉的是本机实际使用过的原件
  (conda 四件 + ldid),所以下载校验语义是完整的;SDK tarball 的
  sha256 留了 TODO——原件未存档,首次下载时补钉。
- conda 包下载 URL 按 conda-forge 惯例形态
  (`conda.anaconda.org/conda-forge/linux-64/<文件名>`);若 channel 子路径
  有出入,以 anaconda.org 页面给出的 download 链接为准。

## 关键知识(踩坑沉淀)

1. **ld64 是 ELF**,但它动态依赖 `libBlocksRuntime.so / libtapi.so.17 /
   libdispatch.so`——三个都由 conda 件提供,`LD_LIBRARY_PATH` 必须指
   `x-libdispatch/lib:x-tapi/lib`(toolchain.md §1 的雷即此)。
2. **`libSystem.tbd` 用仓库里的裁剪版**(对齐设备 10.3.3 的 libSystem
   1311.60.2),**不是** SDK 自带的 1238.60.2 官方桩——链接符号集是按
   设备实际导出裁的。
3. **libcxx15-headers**(8MB,设备 libc++ 6.0.1 vintage 的 C++ 头)不可
   自动化获取,缺它时 C++ 移植跑不起来——脚本会 NOTE 提示手工复制。
4. 仓库侧正本:`tools/sysroot/libSystem.tbd`、`tools/cxx-wrapper.sh`
   (2026-11-21 从 ~/ios-tool 收编入 git;此前它们只存在于工具链树)。
