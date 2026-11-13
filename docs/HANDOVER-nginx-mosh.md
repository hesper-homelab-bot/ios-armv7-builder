# HANDOVER: nginx + mosh 移植 —— 已完成(2026-11-13)

> 2026-11-12 的交接任务当天全部收尾。本文保留为完成记录；
> 后续移植的方法论沉淀在 `docs/toolchain.md` §9-§13(必读)。

## 最终状态

| 包 | 版本 | 状态 |
|---|---|---|
| nginx | 1.26.3-5 | **服务化完成**:launchd 守护(com.hesper.nginx)、postinst 自动 load、gzip 实测 200 |
| mosh | 1.4.0-4 | **真机验证完成**:Termius 手机连接正常(用户 2026-11-13 确认) |

APT repo:**16 包**。Release:**apps-20261113(单独 tag,用户 2026-11-13 拍板)**,
16 个 deb 全量上传:https://github.com/hesper-homelab-bot/ios-armv7-builder/releases/tag/apps-20261113

## mosh 当天修掉的五层雷(全部设备实测定位)

1. `exit=22`/源码树消失 = release URL 前缀错(`mosh-` 不是 `v-`,404)
2. configure 探测四连骗:protoc(PATH)、OpenSSL 走宿主库
   (PKG_CONFIG_LIBDIR)、AC_CHECK_LIB 裸 -lcrypto(预置
   ac_cv_lib_crypto_*)、wcwidth(XSI 宏需成组)——详见 toolchain.md §9
3. `config.h` 被 make 反复重生成 → 修正必须做在 **config.h.in 模板**
   + 触摸 autotools 链(aclocal/autoconf/autoheader regen 链,§13)
4. `HAVE_PLEDGE` 必须**未定义**(非 0,#ifdef 陷阱)
5. `-DNDEBUG` 必须与 protobuf 库一致(InternalMetadata 析构)、
   zlib 用显式 .a(wrapper 丢 -lz)、`pledge`/recvmmsg 等 6 符号进
   libios-compat.a 优雅降级

## 防雷体系(本日沉淀,后续移植直接用)

- `tools/check-undefined.sh` — 链接后审计门禁(已接入两个 build.sh)
- `tools/probe-symbols.sh` — 设备实测符号白名单生成器
- `sysroot-overlay/usr/lib/libios-compat.a` — 优雅降级桩
- `nginx/nginx-daemon.sh` + `com.hesper.nginx.plist` — 守护模板

## 遗留(用户点名,下一个任务)

- [ ] **移植 netstat**(HANDOVER 顶部待办节,方向/判据已写)

## 遗留(2026-11-13 全量审计后记录)

**全量符号审计已完成**(tools/audit-all.sh,覆盖 out/ 全部二进制 + repo deb
载荷)。真雷与处置:

- [x] jq `_pow10` → libios-compat.a 忠实仿真(pow(10,x)),jq 已重建
      143/143 审计全绿;新二进制在 out/,待设备网络稳定后部署
- [ ] **openssh Blowfish**:11 个二进制引用 `_blf_enc` 等 5 符号 undefined。
      真实在 `openbsd-compat/blowfish.c`(Makefile 已列),重链即可解析;
      **加密私钥 KDF 路径可达,优先重建**。openssh 自带的黑名单式门禁
      (build.sh 内 ABSENT/KNOWN_UNRESOLVED)漏了它——建议也接入
      tools/check-undefined.sh(白名单模式)
- [ ] wget 全新构建失败:`warc.c` 缺 uuid 头(uuid_generate/uuid_unparse),
      Nov 6 产物正常,属重建脆弱性,与本次改动无关
- [ ] terminfo 全家(tmux/vim)、utmp 三件套、BLAS(node)等冷路径符号:
      桩已进 libios-compat.a,下次这些包重建时自动生效;现网二进制
      均正常(lazy 绑定 + 冷路径)
- [ ] `_NSGetExecutablePath` 探针误拒(设备应有),待单查

## 设备侧注意事项

- Termius 连接即起 mosh-server;ps 验证要抓 `mosh-server new`(会话
  只活 4 秒是正常流程:server 起来即脱离 ssh)
- 调试期装过日志 wrapper(`/var/mobile/tools/bin/mosh-server` 脚本),
  已被 deb 覆盖还原为真二进制;`/tmp/moshwrap.log` 可删
- 我方测试会话(端口 60200)若仍在会 60s 超时自退,无需处理
