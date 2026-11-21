# QuickJS（Phase 1）专项

> 工具链通用规则见 `docs/toolchain.md`；libc++/C++ 头文件纪律见 `DEVICE.md` §11.2。

## Phase 1 状态（完成）

- **C++(libc++) 冒烟 + QuickJS 落地**：C++ 冒烟探针（`~/scratch/node-research/cxx-smoke`）
  验证 cxx-wrapper + 设备 libc++ 路线可用；随后 QuickJS 移植跑通——设备实测
  `qjs -e 'print(40+2)'` → `42`。
- 源码：`~/scratch/node-research/quickjs-2026-06-04/`（VERSION 2026-06-04）；
  打包快照 `~/scratch/node-research/qjs.tar.xz`（621 KB）。
- 设备侧：`/var/mobile/scratch/qjs`——scratch 验证件；**未**装进
  `/var/mobile/tools`，未做成 deb，未入本仓库（无 build.sh/make-deb.sh）。
- 链接方式：`-undefined dynamic_lookup`——qjs 调用的 `mach_vm_map` 等符号
  不在任何 tbd 桩里，链接期不解析、exec 时由真 libSystem 解析
  （`DEVICE.md` §11.5 的活例）。
- 签名：host `ldid -S` 单次签名即可。2026-11-07 曾有"qjs 816 KB rc=137、
  双签才活"的误判，已由 16/16 单签复验推翻（`DEVICE.md` §10）；
  规则仍是签一次 + `ldid -e` 断言（`docs/toolchain.md` §5）。

## 待办 / 待补

- （待补：Phase 2 的定义与范围——拆解前的 PRINCIPLES.md 未留存相关原文）
- （待补：qjs 构建配置的固化——源树为手工编译，仅存 err-*.log 报错痕迹）
- （待补：test262 结果与已知失败集——源树有 test262_errors.txt，无结论文档）

## Phase 2:产品化(2026-11-21,第二位审稿人建议;✅ 完成)

quickjs4_2026-06-04-1 已入 APT 仓库(`quickjs/` 目录:build.sh + make-deb.sh):

- **钉版源**:bellard.org 上游 tarball 进 sources.lock(sha256 钉死);
  与 phase-1 手工树 diff 确认字节一致后才开始。
- **干净树重建**:每次构建先 rm 产物,从 pristine tarball 重编;
  phase-1 的 .o 残留不参与。
- **两条构建墙**(复现时的坑):
  1. `<crt_externs.h>`:SDK 公开裁剪版没有,overlay 有——但不能整体
     `-I overlay`(shadow SDK 头,toolchain.md §23 教训);单独复制该头
     到专用 include 目录,经 Makefile 的 `DEFINES=` 注入(不能覆盖
     CFLAGS,会丢架构 flag)。
  2. **qjsc 自举**:repl.c 由 qjsc 生成,交叉构建时 qjsc 必须是 host
     可执行——Makefile 的非空 `CROSS_PREFIX` 分支正是为此存在
     (`make qjs CROSS_PREFIX=armv7-ios10.3- HOST_CC=gcc CC=<wrapper>…`:
     host-qjsc 用系统 gcc,target qjs 用 wrapper)。不设它,qjsc 被编成
     armv7,host 执行报 "Syntax error: word unexpected"。
- **门禁**:check-undefined 164/164(dynamic_lookup 路线,与 phase-1 一致)。
- **test262 基线**:58 已知失败(phase-1 宿主跑得,全量清单见
  [quickjs-test262-baseline.txt](quickjs-test262-baseline.txt);
  分类:35 Test262Error / 11 strict / 11 SyntaxError / 1 TypeError)。
  上游同版本基线,升级 quickjs 版本时对照此文件看回归。
- **设备验收**(tests/quickjs.sh,5 cases):eval 冒烟 42、JSON、regexp
  分组、float 精度、ES2023 optional chaining + nullish 全绿。
- 发布身份(大哥拍板背景):node 移植的**对照基准**兼独立轻量 JS 引擎;
  Node 在设备上不可用时,这是唯一的 JS 运行时。
