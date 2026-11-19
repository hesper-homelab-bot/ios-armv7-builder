# Go 1.27.2 darwin/arm revived port

armv7 iOS 10 上可用的 Go 1.27.2 工具链(上游在 1.14 后移除了 darwin/arm,
本目录在 1.27.2 树内复活它)。

## 结构

- `build.sh` — 从官方 go1.27.2 源码 + `patches/` 构建两个产物:
  - `out/go-host-<ver>-linux-amd64.tgz` 宿主交叉工具链(编 darwin/arm 程序)
  - `out/goroot-arm-<ver>.tgz` 设备端工具链(在 iPad 上跑 `go build`)
- `make-deb.sh` — 把设备端工具链打成 `out/go4_<ver>-<rev>_iphoneos-arm.deb`
  (安装到 `/var/mobile/tools/goroot`,postinst 自动设备重签)。
- `patches/` — 相对官方 go1.27.2 的全部改动,按主题编号
  (runtime trampolines/TLS 槽表/syscall 64 位参数槽/链接器 Mach-O/
  vendor x/sys/x509 PEM/internal platform),每个的"为什么"见
  `patches/README.md`,完整证据链见 `../docs/tailcat-porting.md`。

## 快速用法

```sh
./go/build.sh && ./go/make-deb.sh          # 全流程
# 设备上:
export GOROOT=/var/mobile/tools/goroot
cd /var/mobile/gohello && go build -o hello .
```

## 已验证(2026-11-19,iPad4/iOS 10.3.3)

`go version` / `go list` / `go build` 设备上全通;complex 多包测试
(776 行、10 组:goroutines/atomics/mutex/文件/JSON/TCP+Unix socket/DNS/
timer/信号/syscall)设备端编译并运行,**10 组全过**。
宿主工具链 = tailcat 及全部 Go 程序的构建基础(`~/scratch/go-port` 同源)。
