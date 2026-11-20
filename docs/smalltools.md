# smalltools 1.0:tree / watch / realpath / hexdump(armv7 iOS 10.3.3)

> 包:`smalltools4_1.0-1_iphoneos-arm.deb` · 2026-11-20 完成并设备验证
> 一个二进制四个名字(argv[0] 分流,pgrep/pkill 先例),零依赖 C

## 1. 背景

设备实探(2026-11-20)发现四个小件全缺:`patch/xxd/hexdump/watch/realpath/tree`
里 xxd 其实随 vim 装过(tools/bin,PATH 盲区),其余真缺。打包一个 deb 一次带全。

## 2. 各件说明

| 工具 | 功能 | 关键旗标 |
|---|---|---|
| `tree` | 目录树字形(`\|--` / `` `-- ``),目录优先、隐藏跳过 | `-a`(含隐藏)`-d`(仅目录)`-L depth` |
| `watch` | 周期重跑命令并清屏 | `-n 秒`(默认 2) |
| `realpath` | 路径物理化(SDK realpath(3),已确认存在) | 多参数逐行输出 |
| `hexdump` | 16 字节/行 hex+ASCII,offset 8 位 | 文件或 stdin |

## 3. 验收(设备,2026-11-20)

- `tree -L 2 /var/mobile/tools/tailscale`:bin/certs/dns-cache 等层级字形正确
- `realpath ../scratch/../tools/../tools/less` → `/private/var/mobile/tools/less`
- `hexdump /etc/hosts`:偏移/十六进制/ASCII 三栏对齐(短行补空格修过一轮:
  初版第二组 8 字节的 `i==8` 分支抢了补位空格,输出出现假 `00`)
- `watch -n 1`:每秒清屏重跑(ANSI 清屏在 tty 下不可见,预期)
- check-undefined:33/33 符号全解析

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `smalltools/smalltools.c` | 四件合一(argv[0] 分流) |
| `smalltools/build.sh` / `make-deb.sh` | 构建 / 打包(symlink 装法 + /usr/bin 链接) |
