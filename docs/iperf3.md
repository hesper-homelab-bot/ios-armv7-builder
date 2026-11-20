# iperf3 3.22.1 移植专项(armv7 iOS 10.3.3)

> 包:`iperf34_3.22.1-1_iphoneos-arm.deb` · 2026-11-20 完成并设备验证
> 上游:esnet/iperf 3.22.1(BSD-3);server/client 均 mobile 可用(普通 TCP/UDP socket)

## 1. 验收(设备↔宿主,WiFi 实测)

| 模式 | 结果 |
|---|---|
| host→device TCP 双流 | **22.0 Mbits/sec**(SUM sender) |
| device→host TCP(-R) | **27.6 Mbits/sec** |
| host→device UDP 30M | 30.0 Mbits/sec,jitter 0.398ms,**0% 丢包** |
| `iperf3 --version` | 3.22.1 + iPad4/Darwin 16.7.0/xnu-3789.70.16 正确识别 |

## 2. 墙实录

1. **configure 恒真探针 ×4**:`cpuset_setaffinity`/`sched_setaffinity`/
   `SetProcessAffinityMask`/`clock_nanosleep` 全被 dynamic_lookup 恒真探针
   放进 config.h——iOS 10 全都没有(cpuset 头都缺)。压制清单(已固化进
   build.sh):四个 ac_cv_func_*=no。
2. **libtool 归档陷阱(§2 归档规则的活教材)**:GNU ar 归档 ld64 静默无视
   → 换 darwin-ar 再 configure 也无效(libtool 内嵌 AR 不吃环境),归档里
   甚至只剩符号索引没有成员。**终解:绕开归档,configure+make 只出 .o,
   全部 .o 手链一次成型**(138/138 符号全解析),已固化进 build.sh。
3. cc-wrapper 的 env(R4 同源):多命令构建时 env 必须进 build.sh,
   不能靠 shell 延续。

## 3. 用法

```sh
iperf3 -s                 # 设备当服务端(后台跑加 -D)
iperf3 -c <host> -t 10    # 设备打流到主机
iperf3 -c <host> -R -u -b 50M
```

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `iperf3/src/` | 源树(交叉配置产物保留,build.sh 幂等) |
| `iperf3/build.sh` / `make-deb.sh` | 构建(手链固化)/ 打包 |
