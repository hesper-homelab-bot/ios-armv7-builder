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
| dropbear | ✅ 本机绿(107/131/69/76) | endian -D→OSSwap*+预包含;SVR_DROP_PRIVS=0+MULTIUSER=0(复刻生产形态:0 setres/getrandom 引用);getrandom/clearenv config.site fallback;**部署待大哥拍板** |
| tor | ⏳ ~/scratch 旧树 make Error 2 | 同 nmap:干净树化(源在 lock,build.sh fetch 化) |
| vim | ⏳ 未探 | ncurses 同 less |
| git | ⏳ 未探 | 依赖 zlib(已 SDK 化)+ openssl + curl |
| node | ⏳ 未探 | 最重(V8);musl 依赖面最大 |
| openssh | 🔄 WIP | ppoll/setres 全量 python 补丁(设备实测无 ppoll/setres*);sftp-server 的 utimensat 声明墙收尾中(设备有函数、SDK 头不声明);build.sh 曾被 PYEOF 粘连事故截断,已从 d7f1ed1 重建 |
| mosh | ⏳ 未探 | protobuf host 侧 |
| lsof | ⏳ 未探 | libproc 路线 |
| class-dump | ⏳ 未探 | Foundation/CoreFoundation tbd |

## curl 依赖链的 CI 专项(2026-11-21 深夜)

- **CI 单跑架构已落地**(大哥方案):build.yaml(reusable,inputs.package)+
  full-build.yaml(strategy.matrix)+ single-build.yaml(单包手触);
  curl/build.sh 自含 openssl 依赖(matrix 无序)。
- 首轮 matrix:whois ✅ rsync ✅ openssl 构建 ✅(门禁差 10 符号,已
  dlsym 实测入册);curl 差最后一墙:**CI 上 curl 的 vtls/openssl.c 编译
  报 asn1_string_st 不完整(opaque/头配置差异),本机同源同命令过**——
  怀疑点:CI 新 Configure 生成的 configuration 头 vs 本机留存树旧头、
  或系统 /usr/include/openssl 污染;待取证(make 命令行 dump)。
- openssl 的 atomic_compat 已撤销(dlsym 证明设备 libSystem 有全套
  __atomic_* helper——当年"设备缺"的结论被实测推翻)。

- **nghttp2 autotools → cmake**:本机过、CI 的 conftest 探测必死且
  config.log 拒绝展示原因(三轮 dump 无果)→ 换 brotli 同款 cmake 交叉
  (要点:`BUILD_STATIC_LIBS=ON` 必须显式——其 ALIAS 假设 static 目标
  存在,只给 BUILD_SHARED_LIBS=OFF 会让 ALIAS 悬空报错)。
- **openssl 的 atomic_compat 撤销**:dlsym 实测设备 libSystem **有**全套
  __atomic_* runtime helper(当年"设备缺"的结论错了);compat 的
  alias 桩(.word 长跳)也被现代 ld64 的 PIE text-relocation 拒绝。
  compat 文件保留作墙记录,链接不再引用。
- **教训强化**:本机"过"≠CI"过"——本机留存树的旧对象会让增量构建
  跳过重编(假绿);每包过墙必须以 CI 干净 runner 的真全量为准。

## CI 侧(full-build.yml)

- 单 job(bootstrap→canaries→audit);env 含 SDK 契约
- 金丝雀 1(whois)/2(rsync)已绿;3a(openssl)/3b(curl)修好待跑
- publish 步骤仍 if:false(全包覆盖后才启用)

## 已固化工具

- `tools/sdk-migrate-probe.sh <pkg>`:单包 SDK 试构建 + 门禁
- `tools/device-symprobe.sh [--dry] <sym>...`:设备 dlsym 实测 → 白名单
  (rsync 的 12 个 libc/_chk/ctype 符号即此法入册)
