# 设备探针（隔离验证用）

这些小程序用来**让设备自己回答"能不能"**，而不是读源码猜。
每个都是单文件 C，交叉编译后走部署三件套推到设备跑。

## 编译与部署

```sh
export IOS_SYSROOT=~/ios-tool/iPhoneOS10.3.sdk
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib

./tools/cc-wrapper.sh -o /tmp/p probe-atomic-align.c
ldid -S /tmp/p
scp /tmp/p mobile@<device>:/tmp/p
ssh mobile@<device> 'chmod 755 /tmp/p && chown mobile:mobile /tmp/p && ldid -S /tmp/p && /tmp/p'
```

## 清单

### `probe-atomic-align.c` ★ 决定性证据

**问题**：Apple armv7 上 8 字节原子到底行不行？

**结论**（2026-11-16）：
```
sizeof(int64_t)=8   _Alignof(int64_t)=4
__atomic_load_n(4字节对齐的 int64)  ->  Bus error: 10   ← SIGBUS
```

**为什么重要**：这是 python3 `socket.socket()` 100% 崩溃的根因，
也是 node 墙 #11 / OpenSSL init 崩溃的同一个根因。
详见 `docs/toolchain.md` §19。

> **警告**：这个探针会**故意崩溃**（SIGBUS），这是预期行为，不是探针坏了。

### `probe-atomic-align-control.c`

同上，但**只做安全的部分**：拆半读 + 8 字节对齐的原子。
用来确认"4 字节原子可靠"和"对齐了就没事"，是上面那个的对照组。

### `probe-socket-syscall.c`

**问题**：设备上 `socket()`/`connect()` 系统调用本身能走吗？

**用途**：排除环境嫌疑。当 Python 层 socket 崩时，跑这个能立刻区分
"是设备/网络问题"还是"是我们编译的东西有问题"。
**实测结果**：`fd=3` + `connect` 成功 → 设备网络栈完全正常，
问题 100% 在 CPython 侧（最终定位到 8 字节原子）。
