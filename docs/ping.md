# ping 1.0 移植专项（armv7 iOS 10.3.3）

> 包：`ping4_1.0-1_iphoneos-arm.deb`(setuid root 4755)· 2026-11-19 完成并设备验证
> 自写实现(无上游;理由见下),单文件 `ping/ping.c`(~380 行)

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 1.0(自写;iputils 是 Linux 专属、OpenBSD ping 假定 setuid+raw、Apple 闭源) |
| 传输 | **SOCK_RAW + IPPROTO_ICMP**(需 root;包以 setuid 4755 安装,mobile 直接可用) |
| 安装 | `/usr/bin/ping`(setuid),postinst 设备 ldid 重签 |
| 验收 | loopback 3/3(0.25-0.48ms);mobile 身份 ping vv 2/2(8-29ms);tailnet 对端见 §4 |

## 2. 探明的事实(全设备实测,2026-11-19)

| 探针 | 结果 |
|---|---|
| mobile + `SOCK_RAW,IPPROTO_ICMP` | EACCES(raw 需 root) |
| mobile + `SOCK_DGRAM,IPPROTO_ICMP` | **可建可发**——但 **echo reply 永不投递**到该 socket |
| root + `SOCK_RAW` | 收发全通 |
| tcpdump lo0 | dgram 模式发出的 request 上线、内核有 reply 生成,但**不投递给 dgram socket**(iOS 硬化策略) |
| checksum | 第一版大端累加配小端存储 → ICMP cksum 字节反(wrong icmp cksum),内核静默丢弃 request(无 reply、无差错)→ 改小端累加后全通 |

**结论:ping 必须 root 或 setuid**;包内 postinst 固定 4755。

## 3. 用法

```sh
ping -c 3 192.168.31.6        # 常规
ping -i 0.2 -c 5 10.0.0.1     # 快速率
ping -W 2000 -c 1 example.com # 超时/域名解析
```

## 4. 已知限制

- **tailnet 地址(100.x)不适用**:tailscale 的 userspace-netstack 不代答
  ICMP echo——网内连通性用 `tailscale ping <ip>`(disco 层,5ms 级已验证)。
- `-t tty`/`-I` 等高级语义未实现(保持最小)。
- ICMP checksum 字节序教训:累加方向必须与目标端存储序配套(大端累加
  配小端 `n_short` 赋值 = 字节反、内核静默丢包)——`ping/ping.c` cksum 注释。

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `ping/ping.c` | 实现(ICMP dgram/raw 双探记录在注释) |
| `ping/build.sh` / `ping/make-deb.sh` | 构建 / 打包(setuid 4755) |
