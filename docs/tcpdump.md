# tcpdump 4.99.5 + libpcap 1.10.5 移植专项（armv7 iOS 10.3.3）

> 包：`tcpdump_4.99.5-1_iphoneos-arm.deb`（含 libpcap）
> 构建脚本注释即详细文档：`tcpdump/build.sh`、`libpcap/build.sh`
> 本文记录**设备侧的 BPF 链路验证、一个"只在收包路径才炸"的隐蔽坑**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | tcpdump 4.99.5（依赖 libpcap 1.10.5） |
| 包名 | `tcpdump_4.99.5-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools` |
| 验收 | ✅ **`tcpdump -i en0 -c 3` 抓到真实 SSH 流量** |

## 2. 设备侧的 BPF 链路（2026-11-12 全部实测）

```
/dev/bpf0-2 存在且 root 可读
    → xnu-3789.70.16 的 net/bpf.h 进 sysroot
        → libpcap 的 BPF 支持
            → tcpdump 抓到真实流量
```

**已知限制**：本设备的 **Wi-Fi 接口拒绝混杂模式**
（`BIOCPROMISC: Operation not supported on socket`）——
**tcpdump 会打一条警告然后照常工作**。这是预期行为，不是故障。

> 排查设备网络时注意：`/dev/bpf*` **需要 root**。以 `mobile` 身份跑会
> 拿不到句柄——这曾导致一次误判（见仓库 AGENTS.md 工作规则 3.5：
> **ssh 默认用 mobile，root 只用于系统级操作**）。

## 3. 依赖关系（tcpdump 没有 `--with-pcap`）

tcpdump 4.99.5 **根本没有 `--with-pcap` 选项**——它会去找**自己源码目录旁边**
的本地 libpcap 构建树（`../libpcap-X.Y.Z`）。所以 build.sh 会在必要时
**把 libpcap 树软链过去**。

## 4. ★ 两个坑

### 4.1 `getopt_long` 声明冲突（sysroot 头自身的问题）

sysroot 的 `unistd.h` 把 `getopt_long` 的第 4 个参数声明为 `const void *`，
而 `getopt.h` 正确地写作 `const struct option *`。
**任何同时包含两者的文件**（如 `tcpdump.c`）就报类型冲突。

**修法**：改 **sysroot 头本身**（前向声明 `struct option`）。

> 同类修复见 `docs/nmap.md` §4（那一批 sysroot 修复中的一项）。

### 4.2 ★★ 假阳性符号 —— **只在收包路径才炸**

tcpdump 的 configure 通过 cc-wrapper 跑 `main in -lpcap` 式的探测，
而 wrapper 的链接行是 `-undefined dynamic_lookup` → **每个探测都成功**，
**不管符号是否真的存在**。

这里**真正致命的假阳性**有四个：

```
HAVE_PCAP_SET_OPTIMIZER_DEBUG
HAVE_PCAP_SET_PARSER_DEBUG
HAVE_PCAP_FINDALLDEVS_EX
HAVE_PCAP_OPEN
```

它们全被 `#define` 进了 `config.h`，**但 libpcap 1.10.5 里一个都没有**
（`pcap_set_*_debug` 被 `BDEBUG` 守卫，而 libpcap 默认构建把它 `#undef` 了）。

**症状**——**这个坑之所以恶劣，在于它只在实际处理数据包时才出现**：

```
dyld: lazy symbol binding failed: Symbol not found: _pcap_set_optimizer_debug
```

而 `--version` 和 `-D` **跑得好好的**——于是很容易误判成"包没问题"。

**修法**：编辑 `config.h` 把四个全 `#undef`，**并在重建前用
`llvm-nm libpcap.a` 核对**。

> **通用教训**：`-undefined dynamic_lookup` 下的探测**只能证伪不能证真**。
> 凡是"编译过了、`--version` 也对、一用就崩"的形态，
> 优先怀疑假阳性符号。见 `docs/toolchain.md` §8。

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `tcpdump/build.sh` | 构建（**两个坑全文**在注释里） |
| `libpcap/build.sh` | libpcap 构建（tcpdump 会自动调用） |
| `tcpdump/make-deb.sh` | 打包 |
| `tools/probe-symbols.sh` | 设备符号白名单生成器（核对假阳性用） |
