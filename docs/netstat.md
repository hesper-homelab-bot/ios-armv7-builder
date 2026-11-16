# netstat 1.0 移植专项（armv7 iOS 10.3.3）

> 包：`netstat4_1.0-1_iphoneos-arm.deb`
> **自研程序**（非上游移植）：`netstat/netstat.c`（约 900 行）
> 本文记录**状态、四轮探针的 ABI 锚点表、以及"偏移全部实测"的方法论**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 1.0（自研实现） |
| 包名 | `netstat4_1.0-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/bin/netstat` |
| 目标内核 | **xnu-3789.70.16**（iPad3,4 / iOS 10.3.3） |
| 验收 | ✅ `-a` / `-t` / `-u` / `-r` / `-i` **全模式通过**；ABI 设备实测锚定；审计 **23/23 绿** |
| 符号 | 纯 libSystem 符号（`check-undefined.sh` 全绿） |

## 2. 为什么要自研

netstat 读的内核 sysctl **和 macOS netstat 读的是同一批**：

```
net.inet.tcp.pcblist / net.inet.udp.pcblist / net.inet.raw.pcblist
NET_RT_DUMP（路由）  / NET_RT_IFLIST2|IFLIST（接口）
```

**为什么要手写结构体**：sysctl 的载荷里嵌着**内核结构体**
（`struct inpcb` 的用户态形式、`struct xsocket`、`struct otcpcb`），
而这些头文件**在 iOS 上不是公开的**。**Apple 自己的 netstat 也是复制一份。**

> ⚠️ **这里的每个偏移都是在设备上测出来的**（探针在 `netstat/probe-netstat.c`），
> 并与 `lsof` 交叉验证过——**不是从头文件猜的**。

## 3. ABI 锚点表（★ 全部设备实测闭环）

### 3.1 缓冲区布局

```
[xinpgen 24B][entries...][xinpgen trailer 24B]
```

### 3.2 `xinpgen`（24 字节）

| 字段 | 偏移 |
|---|---|
| `xig_len` | 0 |
| `xig_count` | 4 |
| `xig_gen` | 8 |
| `xig_sogen` | 16 |

### 3.3 条目尺寸与内部偏移

| 结构 | 总长 | 内部偏移 |
|---|---|---|
| **tcp 条目**（`struct xtcpcb`） | **524B** | `xt_len@0`、`inpcb@4`、`otcpcb@212`、`xsocket@416`、`alignhack@516` |
| **udp/raw 条目**（`struct xinpcb`） | **320B** | `xi_len@0`、`inpcb@4`、`xsocket@212` |

### 3.4 `struct inpcb`（208B，起始于 +4）

| 字段 | 偏移 | 说明 |
|---|---|---|
| `inp_fport` / `inp_lport` | **20 / 22** | `u16`，**网络字节序** —— 记得 `ntohs` |
| `inp_vflag` | 80 | bit0 = v4，bit1 = v6 |
| `inp_dependfaddr` | 84 | 16 字节 v6 联合体 |
| `inp_dependladdr` | 100 | 16 字节 v6 联合体 |

> **IPv4 走 v4-mapped 形式**，所以 v4 地址的字节在 **@96 / @112**。

### 3.5 `struct otcpcb`（204B，起始于 +212）

| 字段 | 偏移 |
|---|---|
| `t_segq` / `t_dupacks` / unused | 0 / 4 / 8 |
| `t_timer[4]` | 12 |
| `t_inpcb` | 28 |
| `t_state` | 32 → **TCP 状态在 entry+244** |

### 3.6 `struct xsocket`（100B）

| 字段 | 相对偏移 |
|---|---|
| `xso_protocol` / `xso_family` | +20 / +24 |
| `so_rcv.sb_cc` / `so_snd.sb_cc` | +48 / +72 |

### 3.7 静态断言

**所有尺寸都用静态断言钉死**——将来内核变了会**编译失败**，
而不是打印垃圾。

## 4. 四轮探针（方法论）

| 轮次 | 目的 |
|---|---|
| probe1 | MIB 可见性 + 链步长 |
| probe2 | 字段 + 状态（对照 `lsof`） |
| probe3 | v4-mapped 地址修正 |
| probe4 | IFLIST2 消息链结构 |

> **方法论**：sysroot 里**没有** `<netinet/in_pcb.h>`，所以探针用
> **最小本地结构体**描述 xinpgen 链（只保留 Darwin/FreeBSD 都一致的
> 头部字段），并把**原始字节 dump 出来**——**真实步长由设备给出，
> 而不是靠头文件猜**。

## 5. 输出格式（BSD/Darwin 风格）

- `*.port` 通配
- `tcp4` / `tcp6`
- `default` 路由
- **剩余秒** 的 `Expire`
- 接口：名称 + MAC + 计数

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `netstat/netstat.c` | 主程序（含完整 ABI 偏移注释） |
| `netstat/probe-netstat.c` | 设备探针（四轮定位用） |
| `netstat/make-deb.sh` | 打包 |
