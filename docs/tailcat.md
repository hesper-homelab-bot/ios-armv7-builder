# tailcat(armv7 iOS 10)

Go 语言 WireGuard 数据面工具(tailscale/tailcat),**第一个在本目标上完整运行的
Go 程序**。用移植的 Go 1.27.2 darwin/arm 工具链(`~/scratch/go-port`,见
`docs/go.md` 与 `docs/tailcat-porting.md`)交叉编译。

## 构建(宿主)

```sh
./tailcat/build.sh              # -> out/tailcat-<ver>-armv7
./tailcat/make-deb.sh           # -> out/tailcat4_<ver>-<rev>_iphoneos-arm.deb
```

- 工具链:`GOPORT` 指向 go-port(默认 `~/scratch/go-port/go/bin/go`)。
- 代理:默认 `GOPROXY=https://goproxy.cn,direct`(proxy.golang.org 在本网络挂起,
  曾导致 20 分钟"卡死"假象)。
- `-s -w` 必带:链接器 `__DWARF` 段布局有已知 bug,不带时 dyld 拒载。
- 版本取自 tailcat 源码仓库的 `git describe`;deb 版本规范为
  `0.0.0+g<hash>-<rev>`(dpkg 要求数字开头)。

## 部署与使用(设备)

deb 安装(dpkg -i)后二进制在 `/var/mobile/tools/tailcat`,无需配置、无守护进程:

```sh
tailcat genkey --key=foo --client --force   # 生成密钥
tailcat serve                               # 服务端,打印 tailcat 地址
tailcat <address>                           # 客户端,管道到 stdout
```

签名:`make-deb.sh` 已在宿主侧 `ldid -S`(失败会大声报错);手动部署散装二进制时
仍走三件套 `chmod 755 + chown mobile:mobile + ldid -S`。

**不需要 `GODEBUG=asyncpreemptoff=1`**——runtime 已在 darwin/arm 上默认禁用异步
抢占(SIGURG 在 libc 上下文会挂线程:g 槽 TLS 在 iOS 10 未初始化;见
tailcat-porting.md 八-9 与 go-port 的 preempt_msupported_off.go)。早期版本的
"必须加 GODEBUG"是两个 runtime bug 的遮罩,均已修复并实测无 GODEBUG 稳定。

## 移植史与坑

完整的移植、调试(金丝雀定位 syscallN_trampoline 双 bug)与链接器修复记录见
[docs/tailcat-porting.md](tailcat-porting.md);runtime 与链接器修复提交在
`~/scratch/go-port/go`(ee291af1、e1f54449)。
