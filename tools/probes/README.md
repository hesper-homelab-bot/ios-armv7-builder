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

### `probe-tsd-layout.c` ★ Go 移植 TLS 的决定性证据

**问题**：iOS 10.3.3 的 pthread TSD 到底长什么样？`TPIDRURO` 与
`pthread_self()` 什么关系？`pthread_key_create` 给的 key 会落在哪？

**用途**：Go 移植的 `tlsinit` 需要在 TSD 里找 g 的槽位，而 1.14 的
注释只写了"第一个 key 应该是 258"，没有布局图。

**实测结果**（iPad4 / iOS 10.3.3）：
- `pthread_key_create` → **k=258**（与 1.14 注释精确吻合）；
- `TPIDRURO = 基址+1`（**可能不对齐**，需 `BIC $3`）；
- `pthread_setspecific` 写入的 magic 落在 **`基址+0x408`（槽 258）**；
- `TPIDRURO ±4KB` 全部可读（正常进程里 512 槽扫描不会出界）。

**结论**：1.14 的扫描方案在**正常 PIE 布局**下可用；Go 非 PIE 早期
进程里布局会漂移，故移植最终改用"固定槽 + 直接存槽地址"的方案
（见 `docs/go.md` §3.6）。

### `probe-tsd-direct.c`

**问题**：iOS 10.3.3 是否导出 `_pthread_setspecific_direct` /
`_pthread_getspecific_direct`（可省掉 TSD 扫描的直连槽 API）？

**用途**：如果能用直连槽，Go 的 TLS 初始化会简单得多。

**实测结果**：`dlsym` 两者都返回 **0x0**；查
`libsystem_pthread.tbd` 确认**该 API 在 iOS 10.3.3 未导出**
→ 直连槽路线判死（省下一次弯路）。
