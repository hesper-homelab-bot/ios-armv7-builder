# socat 1.8.0.3 移植专项(armv7 iOS 10.3.3)

> 包:`socat4_1.8.0.3-1_iphoneos-arm.deb` · 2026-11-20 完成并设备验证
> 上游:dest-unreach.org socat 1.8.0.3(GPL-2+)

## 1. 验收

- `socat -V` → 1.8.0.3 ✓
- **TCP 中继闭环**:设备上 `socat TCP-LISTEN:12345,reuseaddr,fork TCP:127.0.0.1:22`,
  ssh -p 12345 走中继登录 dropbear,回显 `RELAY-OK via socat` ✓
- check-undefined:181/181 全解析 ✓

## 2. 墙实录

1. **恒真探针**:`HAVE_GETRESUID/HAVE_GETRESGID`(Linux 专属 API)→
   config.h 压制,procan.c 走 getuid 回退分支。
2. **libtool 归档(§2 老朋友)**:libxio.a 被静默无视 → 手链全部 .o;
   排除 procan*/filan_main(另两个二进制的 main),**filan.o 本体保留**
   (socat 引用其 filan_fd)——排除多了会剩一个 UNRESOLVED,按符号回填。

## 3. 用法

```sh
socat TCP-LISTEN:8080,fork TCP:127.0.0.1:80     # 端口转发
socat - TCP:192.168.31.6:8080                   # 管道对接
```

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `socat/src/` | 源树 |
| `socat/build.sh` / `make-deb.sh` | 构建(压制+手链)/ 打包 |
