# ifconfig + route(network_cmds-457)移植专项(armv7 iOS 10.3.3)

> 包:`ifconfig4_457-1_iphoneos-arm.deb`(root:wheel 0755,**不 setuid**)· 2026-11-20 完成并设备验证
> 上游:Apple `network_cmds-457`(Darwin 16 / xnu-3789 时代,与 iOS 10.3.3 精确同代)
> 二进制:`ifconfig/ifconfig.tproj/`(9 个 .c)+ `ifconfig/route.tproj/route.c`;**.c 零补丁**

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | network_cmds-**457**(iOS 10.3.3 = Darwin 16 = xnu-3789,同代对齐;更新的 tag 漂向新内核成语) |
| 构建 | SDK sysroot 模式(§16)+ `-DPRIVATE` + 端口自带 `include/`(xnu-3789.70.16 头) |
| 安装 | `/var/mobile/tools/ifconfig/{ifconfig,route}` + `/usr/bin` 符号链接(postinst 建、prerm 清,rsync 3.3.0-2 先例) |
| 权限 | root:wheel 0755,**不 setuid**——setuid ifconfig = 把整个接口控制权(含 en0 down)交给 mobile,绝不 |
| 验收 | 见 §4 |

iproute2 没有 Darwin 版:它整个建立在 Linux netlink(rtnetlink)上,Darwin 无此
socket 族,无从移植。Homebrew 的 `iproute2mac` 只是拿 ifconfig/route/netstat 拼
的 CLI 壳,恰好证明 BSD 侧正解就是 ifconfig + route + netstat(自研 netstat 已有)。

## 2. 墙实录(按撞上顺序)

1. **iOS SDK 头是"公开裁剪版",不是完整内核头**。SDK 的 `net/if.h`、
   `sys/sockio.h`、`net/if_var.h` 全部删掉了 PRIVATE 段:`if_descreq`/
   `if_linkparamsreq`/`if_throttlereq`、`ifr_log`/`ifru_2kcl`、
   `SIOCSIFDESC/SIOCSIFLINKPARAMS/SIOCSIFTHROTTLE/SIOCSIFLOG/SIOCSIF2KCL`、
   `if_bandwidths`/`if_latencies`/`if_interface_state`、
   `if_traffic_class`/`if_data_extended`/`if_packet_stats`/`if_rxpoll_stats`
   一个都不在。解法 = **xnu-3789.70.16 完整头 + `-DPRIVATE`**(Apple 内部
   构建 network_cmds 的同款姿势),见 §3。
2. **shadow 陷阱**:`-I sysroot-overlay/usr/include` 会把 xnu 的
   `sys/param.h` 等同名头遮住 SDK 头,xnu 世界头文件互相引用 SDK 没有
   的 `endian.h` → 雪崩。解法 = 端口自带 `include/` **只放 SDK 真缺的
   头**(18 个)+ 3 个必须整头换用的 shadow(net/if.h、net/if_var.h、
   sys/sockio.h),SDK 其余头原样生效。
3. **`tmp/sysroot` 是 musl 时代的旧 sysroot**(epoll.h/inotify.h 等
   Linux 头都在),§16 拍板后只服务存量 24 包,新移植禁止再用;其中
   连 SDK 自带的 `sys/queue.h` 都没有。第一次误当 SDK 用,撞墙即回。
4. **kldload/modstat(sys/module.h、sys/linker.h)是 FreeBSD 遗留**,
   上游已包在 `#ifndef __APPLE__` 里,Darwin 构建天然跳过,零补丁。
5. **fetch-darwin-header.sh 的 extern "C" 门禁是文本检查**,看不见
   `#ifdef KERNEL_PRIVATE` 护栏:这些内核头的"函数声明"全在私有护栏
   内(用户态不可见),但正则会命中 `return (...)`/`__attribute__` 成员
   等假阳性。解法 = 按工具自己的处方,在护栏**内侧**补
   `#if defined(__cplusplus) extern "C" { #endif` 包裹(语义诚实),
   原文补丁保留 provenance。
6. **uuid_t 的出处**:xnu `net/if.h` 的 `struct if_agentidreq`(PRIVATE
   段)用 uuid_t;内核构建从 KERNEL 侧 uuid 头拿,用户态 SDK 从
   `sys/_types/_uuid_t.h` 拿。stamped if.h 里补一行该 include(已注明)。
7. **ld64 起不来**(`libBlocksRuntime.so not found`)= 环境变量不全。
   §1 的标准 export 必须整块带上(尤其 `LD_LIBRARY_PATH=x-libdispatch/
   lib:x-tapi/lib`);build.sh 已固化全默认值,裸跑即可。

## 3. 头清单(端口 `ifconfig/include/`,21 个)

- **SDK 真缺(18)**:`net/route.h`、`net/if_media.h`、`net/if_types.h`、
  `net/if_mib.h`、`net/if_vlan_var.h`、`net/if_bond_var.h`、
  `net/if_bridgevar.h`、`net/lacp.h`、`net/if_bond_internal.h`、
  `net/pktsched/pktsched.h`、`net/net_kev.h`、`netinet/in_var.h`、
  `netinet6/nd6.h`、`netinet6/in6_var.h`、`netinet6/scope6_var.h`、
  `sys/kern_event.h`、`sys/sys_domain.h`(级联拉取,×2 未走外层工具门禁
  的三个由端口内直落)
- **整头 shadow(3)**:`net/if.h`、`net/if_var.h`、`sys/sockio.h`
  (xnu-3789.70.16 原文 + provenance 戳;if.h 加一行 `_uuid_t.h` include)
- 其余(ether.h、if_dl.h、queue.h、in.h、ifaddrs.h……)全用 SDK 自带。

私有护栏内的 extern "C" 包裹记录:if_vlan_var(KERNEL_PRIVATE)、
if_bridgevar/if_bond_internal(XNU_KERNEL_PRIVATE/KERNEL_PRIVATE)、
nd6.h(两段 BSD_KERNEL_PRIVATE)、in6_var(557-582 与 1092-1166 两段)、
scope6_var、kern_event(`#ifdef KERNEL` 区)、lacp(无真声明,整段包裹)。

## 4. 验收(2026-11-20 设备实测)

| 探针 | 结果 |
|---|---|
| mobile `ifconfig -a` | lo0/en1/en2/en0/awdl0/utun0 全列,en0 带 192.168.31.70 |
| mobile `ifconfig en0` | ether MAC、inet6 secured、`media: autoselect`、`status: active`、`type: Wi-Fi`(ifmedia 全通) |
| mobile `route -n get default` | gateway 192.168.31.1、interface en0、STATIC flags |
| mobile `lo0 <ip> alias` | **SIOCAIFADDR: permission denied**(接口 ioctl 需 root,符合预期) |
| root `lo0 10.173.0.1 alias` → `ping 10.173.0.1` | **2/2 received, 0.33ms**;`-alias` 删除后恢复 |
| root `route add -host 10.173.0.2 127.0.0.1` → `route -n get` | gateway 127.0.0.1 / lo0 / HOST,STATIC;`delete` 后回落 default 网关 |
| check-undefined.sh | ifconfig 72/72、route 62/62 全解析 |

## 5. 用法

```sh
ifconfig -a                  # 全接口(mobile 可用)
ifconfig en0                 # 单接口状态(media/status/type)
ifconfig lo0 10.173.0.1 alias    # root:加地址别名
ifconfig lo0 10.173.0.1 -alias   # root:删
route -n get default         # 默认路由(mobile 可用)
route add -host 10.173.0.2 127.0.0.1   # root
route delete 10.173.0.2      # root
route -n monitor             # 路由表变化监听
```

## 6. 已知限制

- 写操作(up/down、alias、route add/del/flush)必须 root——刻意不 setuid。
- `arp`/`ndp`(network_cmds 邻居系)未移植;需要时按同款
  -DPRIVATE + 端口 include 模式走,arp 另需 libutil(free)。
- ifbond/ifbridge/ifvlan 子命令依赖内核 clone 类型;设备内核是否编译
  bridge 等未逐一验证,`ifconfig create bridge` 失败即内核不支持,非本包问题。
