# ncdu 1.20 移植专项(armv7 iOS 10.3.3)

> 包:`ncdu4_1.20-1_iphoneos-arm.deb` · 2026-11-20 完成并设备验证
> 上游:dev.yorhel.nl ncdu 1.20(MIT);链接设备自带 libncursesw.5.dylib

## 1. 验收

- `ncdu --version` → 1.20 ✓
- 非交互导出:`ncdu -o /tmp/ncdu-export.json -q /var/mobile/tools/less` →
  合法 JSON(184B,含目录/尺寸)✓(TUI 程序的标准无头验收法)
- check-undefined:98/98 全解析 ✓

## 2. 墙实录(ncurses 三连环)

1. **设备 ncurses 是 wrapped-var 构建**:头里 `acs_map` 是宏(→访问函数),
   dylib 导出 `D _acs_map` 数据符号——但**头要与 dylib 配套**:普通
   ncurses.h 编出的代码引用裸 `_acs_map`,运行期 dyld 找不到(明明 dylib
   导出了同名符号——实际是**头不配套**,编译期走的是非 wide 头)。
   修法:shim include(`#include <ncursesw/ncurses.h>`)+ 宽头优先。
2. **`-lncursesw` 静默放行**:`-L` 搜索只认 `lib<name>.dylib`(无版本)与
   `.a`;目录里只有 `libncursesw.5.dylib` 版本名,ld64 一个都没吃到,
   dynamic_lookup 全兜底 → 运行期 flat namespace 崩。修法:**设备 dylib
   以直接路径作为链接输入传入**(自动记录 LC_LOAD_DYLIB,install name
   /usr/lib/libncursesw.5.dylib 设备原生存在)。
3. **IOS_DYLIBS 通道小坑**:cc-wrapper 的 IOS_DYLIBS 支持存在,但绝对路径
   在某层丢了前缀(ld64 收到 /libncursesw.5.dylib)——绕开,直接传文件。
4. 头与 dylib 都从设备拉(tmux 先例:/usr/include 的 ncurses 头 + 
   /usr/lib/libncursesw.5.dylib),devhdr/ 里带 shim。

## 3. 用法

```sh
ncdu /var/mobile/tools          # TUI 浏览(ssh/tmux 下)
ncdu -o export.json /path       # 无头导出 JSON
```

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `ncdu/src/` | 源树 |
| `ncdu/devhdr/` | 设备拉取的 ncurses 头 + dylib + shim |
| `ncdu/build.sh` / `make-deb.sh` | 构建(dylib 直链固化)/ 打包 |
