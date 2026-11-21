# musl → SDK 批量迁移(2026-11-21,大哥拍板"用 musl 的包都在 CI 上 SDK 打包")

> 方法:本机 `tools/sdk-migrate-probe.sh <pkg>` 逐包 SDK 试构建
> (env:SDK 三件套 + OSSL 留存树),过墙 → CI 全链验证 → bump rev 打包。
> 通用坑模式见 `docs/toolchain.md` §23 与 `docs/curl.md` §7。

## 状态

| 包 | 状态 | 备注 |
|---|---|---|
| curl | ✅ SDK 已上线(8.16.0-6) | 见 docs/curl.md §7 |
| quickjs | ✅ 生来 SDK | docs/quickjs.md |
| ca-certificates4 | ✅ 数据包 | |
| whois | ✅ CI 绿(金丝雀 1) | 源 fetch 化 + _XOPEN_SOURCE 700 补丁 |
| rsync | ✅ CI 绿(金丝雀 2) | 源 fetch 化;12 符号 dlsym 实测入白名单 |
| make | ✅ 本机绿(133/133) | 源 fetch 化;CI 待跑 |
| openssl | 🔄 本机构建中 | env SDK 化(CROSS_TOP/SDKs 链接形);CI 待跑 |
| p7zip | ✅ 本机探针过 | 打包 rev bump 待做 |
| sqlite | ✅ 本机探针过 | 同上 |
| jq | ✅ 本机绿(143/143) | HAVE_POW10 探针谎言修复(config.h);打包待做 |
| tcpdump | ⏳ 依赖 libpcap | |
| libpcap | ⏳ net/bpf.h ABI 化中 | bpf.h 在 overlay 不在 SDK;SYSINC 段要 ABI 目录化 |
| nmap | ⏳ build.sh 内嵌补丁断言失败 | 源树=~/scratch 旧树已打补丁;需干净树+补丁幂等化 |
| less | ⏳ ncurses 检测失败 | "Cannot find terminal libraries";SDK 模式 ncurses 配置待做 |
| dropbear | ⏳ 待查 | 日志只到 archive 警告;真实错误未现 |
| tor | ⏳ ~/scratch 旧树 make Error 2 | 同 nmap:干净树化 |
| vim | ⏳ 未探 | ncurses 同 less |
| git | ⏳ 未探 | 依赖 zlib(已 SDK 化)+ openssl + curl |
| node | ⏳ 未探 | 最重(V8);musl 依赖面最大 |
| openssh | ⏳ 未探 | |
| mosh | ⏳ 未探 | protobuf host 侧 |
| lsof | ⏳ 未探 | libproc 路线 |
| class-dump | ⏳ 未探 | Foundation/CoreFoundation tbd |

## CI 侧(full-build.yml)

- 单 job(bootstrap→canaries→audit);env 含 SDK 契约
- 金丝雀 1(whois)/2(rsync)已绿;3a(openssl)/3b(curl)修好待跑
- publish 步骤仍 if:false(全包覆盖后才启用)

## 已固化工具

- `tools/sdk-migrate-probe.sh <pkg>`:单包 SDK 试构建 + 门禁
- `tools/device-symprobe.sh [--dry] <sym>...`:设备 dlsym 实测 → 白名单
  (rsync 的 12 个 libc/_chk/ctype 符号即此法入册)
