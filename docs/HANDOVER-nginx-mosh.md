# HANDOVER: nginx + mosh + netstat 移植 —— 已完成(2026-11-13)

> 2026-11-12 的交接任务当天全部收尾。本文保留为完成记录；
> 后续移植的方法论沉淀在 `docs/toolchain.md` §9-§13(必读)。

## 最终状态

| 包 | 版本 | 状态 |
|---|---|---|
| nginx | 1.26.3-5 | **服务化完成**:launchd 守护(com.hesper.nginx)、postinst 自动 load、gzip 实测 200 |
| mosh | 1.4.0-4 | **真机验证完成**:Termius 手机连接正常(用户 2026-11-13 确认) |
| netstat | 1.0-1 | **全模式完成**:-a/-t/-u/-r/-i 全绿，ABI 设备实测锚定，审计 23/23 绿 |

APT repo:**17 包**。Release:**apps-20261113(单独 tag,用户 2026-11-13 拍板)**,
17 个 deb 全量上传:https://github.com/hesper-homelab-bot/ios-armv7-builder/releases/tag/apps-20261113

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

- [x] **移植 netstat**(HANDOVER 顶部待办节,方向/判据已写)
  - **ABI 锚点(全部设备实测闭环)**: xinpgen 24B(xig_len@0,count@4) → TCP 条目 524B(xinpcb@4 + otcpcb@212 + xsocket@416) → UDP/raw 320B(xinpcb@4 + xsocket@212)
  - **关键偏移(静态断言钉死)**: inp_fport/lport@20/22(网络序)、v4 地址存 v4-compat 形式 @96/@112、t_state@244、xso_protocol/family/rcv/snd@436/440/464/488
  - **四轮探针**: probe1(MIB 可见性+链步长)→ probe2(字段+状态对照 lsof)→ probe3(v4-mapped 地址修正)→ probe4(IFLIST2 消息链结构)
  - **输出格式**: BSD/Darwin 风格(*.port 通配、tcp4/tcp6、default 路由、剩余秒 Expire、接口名+MAC+计数)
  - **审计**: check-undefined.sh 23/23 绿(纯 libSystem 符号)

## 遗留(2026-11-13 全量审计后记录)

**全量符号审计已完成**(tools/audit-all.sh,覆盖 out/ 全部二进制 + repo deb
载荷)。真雷与处置:

- [x] jq `_pow10` → libios-compat.a 忠实仿真(pow(10,x)),jq 已重建
      143/143 审计全绿;新二进制在 out/,待设备网络稳定后部署
- [x] **openssh Blowfish**:11 个二进制引用 `_blf_enc` 等 5 符号 undefined。
      真实在 `openbsd-compat/blowfish.c`(Makefile 已列),重链即可解析;
      **加密私钥 KDF 路径可达,优先重建**。已完成：`ios-config.site` pin 三个
      `ac_cv_func_Blowfish_*`=no + 显式链接 `blowfish.o`(而非 `-lopenbsd-compat`,
      ld64 不回扫档案)。14/14 二进制 check-undefined 全绿。
- [x] wget 全新构建失败:原有 4 符号 `fflush_unlocked`/`fputs_unlocked`/
      `fread_unlocked`/`__fsetlocking` 未决。已完成：重建 libios-compat.a
      (含这 4 个桩)，wget 261/261 审计全绿。
- [x] terminfo 全家(tmux/vim)、utmp 三件套、BLAS(node)等冷路径符号:
      桩已进 libios-compat.a,现网二进制均正常(lazy 绑定 + 冷路径)。
      BLAS 新增 daxpy_/ddot_/dnrm2_/dscal_ 桩(nmap 触发)。
- [x] `_NSGetExecutablePath` 探针误拒(设备应有),待单查
      已完成：加入 libios-compat.a 存根(返回 -1, buflen=0)，node 等已过审计。

## 设备侧注意事项

- Termius 连接即起 mosh-server;ps 验证要抓 `mosh-server new`(会话
  只活 4 秒是正常流程:server 起来即脱离 ssh)
- 调试期装过日志 wrapper(`/var/mobile/tools/bin/mosh-server` 脚本),
  已被 deb 覆盖还原为真二进制;`/tmp/moshwrap.log` 可删
- 我方测试会话(端口 60200)若仍在会 60s 超时自退,无需处理

## nginx 停用（2026-11-14，设备侧）+ 宿主机误停已复原

- 用户要停的是**设备侧** nginx（com.hesper.nginx，监听 8080）。
- 宿主机 systemd nginx 被误停，当日已复原：`systemctl enable --now nginx`，
  active + enabled 双确认。
- 设备侧：`launchctl unload /Library/LaunchDaemons/com.hesper.nginx.plist`
  停服务（launchd 无任务、进程清零）；iOS 10 launchd 的 `-w` **未落
  overrides**（`/var/db/launchd/db/com.apple.launchd/overrides.plist` 不存在），
  开机不自启靠往 plist 写 `<key>Disabled</key><true/>`（用
  `/var/mobile/tools/bin/node` 改写——root 非登录 shell 的 PATH 只有
  /usr/bin:/bin，裸 `node` 找不到）。改前备份：
  `/var/mobile/.local/etc/backup-nginx/com.hesper.nginx.plist.pre-disable`。
- 注意：plist 被改 → `dpkg -V nginx4` 会报该文件 md5 不符（预期，非损坏）。
- 重新启用：去掉 plist 里的 Disabled 键（或恢复备份）后
  `launchctl load /Library/LaunchDaemons/com.hesper.nginx.plist`。
