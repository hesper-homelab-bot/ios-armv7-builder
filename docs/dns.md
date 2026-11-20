# dnsq 1.0:dig / nslookup / host(armv7 iOS 10.3.3)

> 包:`dns4_1.0-1_iphoneos-arm.deb` · 2026-11-20 完成并设备验证
> 一个二进制三个名字(argv[0] 分流),自研 stub 解析器,零依赖 C(~600 行)

## 1. 背景

设备实探(2026-11-20):DNS 客户端**全家缺席**(dig/nslookup/host/
dnsdomainname 0/4),调试 DNS 一直靠宿主机。自研补齐。

## 2. 能力

| 项 | 说明 |
|---|---|
| 传输 | UDP 53,2 次重试 3s 超时;**TC 置位自动回落 TCP**(TCP-DNS 2 字节长度前缀) |
| 记录 | A / AAAA / CNAME / MX / TXT / NS / PTR / SOA / ANY(未知类型按 RFC 3597 `\# n` 显示) |
| 名字解析 | 压缩指针(两游标算法:消费位与跳转位分离),跳转上限 32 |
| 解析服务器 | `/etc/resolv.conf` nameserver(iOS 网络变化时系统自动重生成);`@server` 覆盖 |
| 前端 | `dig [@srv] name [type] [+short]`;`nslookup name [srv]`;`host [-t type] name [srv]`(三前端统一支持 `-t`) |

## 3. 验收(设备,2026-11-20)

- `dig +short github.com` → 20.6.7.17(与真实一致)
- `dig apple.com A` → QUESTION/ANSWER 完整格式,TTL/IN/类型逐条
- `nslookup example.com` → Server + 双 A
- `host qq.com` → 双 A 逐条;`host -t aaaa github.com` → 空,**与宿主机
  dig @192.168.31.1 对拍一致**(该网络上游不回 AAAA,非解析 bug)
- `dig -t mx apple.com +short` → 6 条 MX 带优先级;`nslookup -t ns qq.com` → 4 条 NS
- check-undefined:36/36 符号全解析

## 4. 已知限制

- 不做递归解析器行为(纯 stub:把查询原样交给上游);不支持 EDNS0/DO
- `host` 的 CNAME 链自动跟随只跟 ANSWER 区里实际返回的记录(与上游一致的紧凑语义)

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `dns/dnsq.c` | 实现(wire 编解码 / 传输 / 三前端) |
| `dns/build.sh` / `make-deb.sh` | 构建 / 打包(symlink 装法 + /usr/bin 链接) |
