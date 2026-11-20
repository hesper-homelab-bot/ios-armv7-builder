# traceroute 1.0 移植专项（armv7 iOS 10.3.3）

> 包：`traceroute4_1.0-1_iphoneos-arm.deb` · **设备验收通过**（2026-11-20 真机实测）
> 构建脚本注释即详细文档：`traceroute/build.sh`（含每步动机）
> 本文记录**状态、用法、坑与结论**；细节指向 build.sh，不重复。

## 1. 状态

| 项 | 值 |
|---|---|
| 上游 | Apple `network_cmds-457`（Darwin 16 / xnu-3789 同代），`traceroute.tproj` |
| 源码 | `traceroute/traceroute.tproj/`（5 个 .c：traceroute/as/findsaddr-socket/ifaddrlist/version） |
| 构建 | `traceroute/build.sh` → `out/traceroute-armv7`，check-undefined **71/71 全绿** |
| 安装 | `/usr/bin/traceroute`，**setuid 4755 root:wheel**（Apple 上游同款形状：pbxproj `ALTERNATE_MODE = 04555`，只是 Apple 装 /usr/sbin；设备无存量 traceroute，装 /usr/bin 与 ping4 一致） |
| 补丁 | **上游仅 1 处功能性单行**：`SO_RECV_ANYIF` 的 `#ifndef` 守卫（见坑 1）；其余全是头文件供给 |
| 验收 | `-n` 到网关 1 跳命中；`-m 3` 外网目标第 1 跳=网关、3 跳内见到运营商节点；无参输出 usage；hostname/反查 DNS 正常 |

## 2. 依赖链

无外部库：纯 libSystem（raw socket + sysctl）。头文件供给：

- `traceroute/include/`（本包自带，带 `<PROVENANCE-STAMP>`）：
  `netinet/ip_var.h`、`netinet/udp_var.h`、`netinet/tcpip.h`
  ——三个 iOS 10.3 SDK 都不发的内核私有头（Mac 上在
  System.framework/PrivateHeaders）。从 `~/scratch/sysctl-work/xnu`
  tag `xnu-3789.70.16` 取，用户态段原样（不定义
  `KERNEL_PRIVATE`/`BSD_KERNEL_PRIVATE`，与 Apple 用户态构建一致）。
- `ifconfig/include/` 直接 `-I` 复用（同族 457、同一 xnu-3789 头集合），
  未重复拉取。

## 3. 坑列表

| # | 坑 | 要点 / 修法 |
|---|---|---|
| 1 | SDK 公开版 `<sys/socket.h>` 没 `SO_RECV_ANYIF` | 0x1104 在 xnu-3789 `bsd/sys/socket.h:318` 的 `#ifdef PRIVATE` 尾段里，SDK 公切删掉了。修法：traceroute.c 顶部一行 `#ifndef SO_RECV_ANYIF/#define`。setsockopt 失败本就不致命（上游不查返回值） |
| 2 | SDK 完全没有 `netinet/ip_var.h`、`udp_var.h`、`tcpip.h` | 见 §2；tcpip.h 对 traceroute.c 纯属历史遗留 include（无任何引用），但仍给真头不给 stub，与 Apple 构建所见一致 |
| 3 | iOS 10 上 raw socket 必须 root | deb 装 setuid 4755（同 ping4 结论：非特权 SOCK_DGRAM ICMP 只发不收）。postinst `ldid -S` 重签 + `chown root:wheel` + `chmod 4755` |
| 4 | `-D` 集合不能照抄 ifconfig | Apple pbxproj target "traceroute" 只定义 `HAVE_SOCKADDR_SA_LEN`；补 Darwin 上为真的 autoconf 项：`HAVE_SYS_SYSCTL_H`、`HAVE_USLEEP`、`HAVE_SETLINEBUF`；**不**定义 `HAVE_SYS_SELECT_H`/`HAVE_MALLOC_H`/`HAVE_OS_PROTO_H` |
| 5 | `-I` 顺序 | 本包 `include/` 必须在 `ifconfig/include/` 之前（tcpip.h include ip_var.h，同名优先取自本包，避免两条取用路径不一致） |

## 4. 设备侧用法 / 注意事项

```sh
traceroute -n 192.168.31.1          # 数字输出，1 跳命中网关
traceroute -n -m 3 223.5.5.5        # 限 3 跳看外网前段
traceroute -P icmp|tcp|udp|gre host # Apple 版特有：可选探测协议
traceroute -a host                  # AS 号反查（as.c，whois）
```

- 预期内"异常"：中间跳 `* * *` 是 ICMP time-exceeded 被运营商过滤，属正常。
- setuid root 的木马面同 ping4：二进制不可由用户替换；升级走 deb。
- 上游 Apple 版装 `/usr/sbin`，本包装 `/usr/bin`（与 ping4 同布局，便于 mobile 直接调用）。

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `traceroute/traceroute.tproj/` | 上游源码（含 APPLE_LICENSE 同级目录 `traceroute/APPLE_LICENSE`） |
| `traceroute/build.sh` | 交叉编译 + check-undefined |
| `traceroute/make-deb.sh` | setuid 4755 deb 打包（`dpkg-deb --root-owner-group -Zgzip`） |
| `traceroute/include/` | 3 个 xnu-3789 内核私有头（带 PROVENANCE 戳） |
| `docs/traceroute.md` | 本文 |