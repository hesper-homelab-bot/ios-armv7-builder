# tailscale v1.104.7 移植专项（armv7 iOS 10.3.3，Go 1.27.2 darwin/arm）

> 2026-11-19 立项当日全链路跑通。上游最新 release `v1.104.7`（go.mod 要求
> go 1.27.4）。旧版（Go 1.14 时代）移植档案已删；本次以 tailcat 0.7.0 的
> 依赖适配体系（`docs/tailcat-porting.md`）+ Go 移植本体（`docs/go.md`）为
> 地基。源码：`~/scratch/tailscale/src`（goproxy.cn 的 v1.104.7 module zip
> + tag 原版 go.sum）。

## 1. 状态：✅ 全链路设备验证

| 项 | 值 |
|---|---|
| 上游 | v1.104.7（2026-11-12 release） |
| 工具链 | `~/scratch/go-port/go`（Go 1.27.2 darwin/arm 复活版，`docs/go.md`） |
| 构建 | `GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=0` + `-tags netgo -ldflags "-s -w -X tailscale.com/version.longStamp=v1.104.7 -X ...shortStamp=1.104.7"` |
| cmd/tailscale | ✅ 16.5MB Mach-O armv7，设备 `version`=`v1.104.7`（版本戳对齐官方） |
| cmd/tailscaled | ✅ 23.5MB Mach-O armv7，设备常驻（tmux `tsd` / 或 deb 的 LaunchDaemon） |
| 登录 | ✅ 用户手机点 authURL 授权；状态持久化，重启免重登（`machineAuthorized=true` 重放） |
| 控制面 | ✅ netmap 拉取、DERP、MagicDNS (100.100.100.100)、6 peer 全列出 |
| 数据面 | ✅ `tailscale ping` 直连 pong 5ms（192.168.31.6:41641，disco 协商） |
| 代理面 | ✅ SOCKS5(127.0.0.1:1055) → 隧道 → vv:22 抓回完整 SSH banner（tcpdump 佐证：三次握手 6.5ms、banner 42B 送达） |
| 打包 | ✅ `tailscale4_1.104.7-3_iphoneos-arm.deb` 已安装保留；plist **Disabled**（省电，手动 load）；wrapper 自带日志重定向（见墙 #5） |
| 工具链改动 | **无**（go-port 零改动；只补了 x/sys 树 3 个常量，见墙 #1） |

## 2. 墙

| # | 墙 | 修法 |
|---|---|---|
| 1 | `net/routetable`：`unix.RTF_GLOBAL` undefined | x/sys v0.48 darwin 树 32 位 `zerrors_darwin_arm.go` 缺 RTF_GLOBAL=0x40000000、RTF_DEAD=0x20000000、RTF_LLDATA=0x400（arm64 同值抄入）。**xsys 树已 git 化**（`~/scratch/xsys-v048-darwin-arm`，commit 7ae0e09） |
| 2 | tailscaled 编译期 `disk quota exceeded` | /tmp usrquota 二次复发——`export TMPDIR=$HOME/ios-armv7-builder/tmp`（build.sh 已内置） |
| 3 | SOCKS5/HTTP 代理不自动起 1055/1056 | 新版 tailscaled 需显式 `--socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1056`（daemon.sh 已带） |
| 4 | 旧 daemon 杀不干净：tmux kill / SIGTERM 被 SIGHUP 存活实例无视 → 多实例抢 state 锁、CPU 自旋 | 重启必须 **SIGKILL 全清**再起（设备 `/var/mobile/tools/tailscale/restart.sh`）；症状特征：`ps` 里多个 tailscaled、新实例 55% CPU 且 socket 无响应 |
| 5 | **已登录状态下，日志直写 PTY（tmux pane）时 daemon 在 logpolicy 后自旋**（~56% CPU，socket/代理永不就绪）；日志重定向到文件则完全正常（两次复验）。未登录时代 pty+tee 正常——疑似 PTY 写 × 已登录状态的组合触发，根因待查（Go runtime 写 pty？） | **手动跑一律 `>> 文件 2>&1`**（deb wrapper 已内置）；launchd 路径由 plist StandardOut/ErrPath 落盘不受影响 |

## 3. 设备端用法

```sh
# 启动（二选一）
su mobile -c "tmux new-session -d -s tsd /var/mobile/.local/bin/tailscale-daemon.sh"
launchctl load -w /Library/LaunchDaemons/com.hesper.tailscale.plist   # plist 默认 Disabled
T=/var/mobile/tools/tailscale/bin/tailscale
S=/var/mobile/tools/tailscale/tailscaled.sock
$T --socket=$S status          # 状态
$T --socket=$S ping <peer-ip>  # 数据面
# 走隧道（iOS 10 无 /dev/tun，userspace-netstack 只暴露 SOCKS5/HTTP 回环代理）：
/var/mobile/tools/python3/bin/python3 - <<'EOF'   # 设备 curl 是坏仪器，用 python3
import socket
s=socket.create_connection(('127.0.0.1',1055)); s.settimeout(8)
s.sendall(b'\x05\x01\x00'); s.recv(2)
s.sendall(b'\x05\x01\x00\x01'+bytes([100,126,97,38])+b'\x00\x16'); s.recv(32)
print(s.recv(64))
EOF
```

## 4. 验证仪器的教训（第三次现身，升级为规则）

**设备 curl 8.16 是坏仪器**：连接、发送正常，收不到响应字节/中途 reset。
本案三连：①连本机 nginx 超时（对旧二进制同样超时，曾误导排查 1.31.9）；
②连本机 SOCKS5 拿不到 reply（daemon 日志显示后端拨号已成功、SSH banner 已
推回）；③**python3 双向 loopback 实测全通**——内核栈无辜，curl 移植自身的
bug。规则：**设备上验证网络服务一律用 python3 裸 socket，禁用设备 curl**；
curl 移植另立专案（见 porting-backlog）。

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `tailscale/build.sh` | 交叉编译 CLI+daemon（GOTOOLCHAIN=local/TMPDIR/GOPROXY 内置） |
| `tailscale/make-deb.sh` | 打包（双签名、plist Disabled、无自启） |
| `~/scratch/tailscale/src` | 源码 + replace（go.mod `go 1.27.4`→`1.27.2` + GOTOOLCHAIN=local） |
| `~/scratch/xsys-v048-darwin-arm` | x/sys 本地树（已 git 化，RTF 补丁在内） |
