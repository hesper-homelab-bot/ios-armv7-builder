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
