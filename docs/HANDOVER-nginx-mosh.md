# HANDOVER: nginx + mosh 移植(2026-11-12 会话交接)

> 明日入口。两个包的状态、产物位置、断点、下一步。正本在本文件(git 管理);
> 详细墙记录另见各处引用。

## 状态总览

| 包 | 状态 | 产物 |
|---|---|---|
| mosh 1.4.0 | **基本完成**(二进制已验证协议层),收尾中 | `out/mosh-server` `out/mosh-client`(3.8MB);deb 待重打 |
| nginx 1.26.3 | **编译成功**,差最后两步 | `~/ios-tool/nginx-src/nginx-1.26.3/objs/nginx`(4.3MB);deb 未打 |

APT repo 当前 **15 包**(mosh 已入库;nginx 完成后 16)。

## mosh:已完成/剩余

**已完成**(全部沉淀在 `mosh/build.sh` 注释 + `mosh/patch-mosh.py`):
- host protoc 自举(3.20.3 源码,与目标 libprotobuf 严格同版本;tarball
  不自带 .pb.cc,必须生成)
- libprotobuf 交叉编译 + darwin 归档重打包,装 `$HOME/ios-tool/protobuf-ios/`
- 64 位原子雷**未兑现**(clang 内联 LL/SC,不走坏 libcall;判据=反汇编看
  ldrexd,不是 nm)
- 设备验证:mosh-server 输出 `MOSH CONNECT`,主机 mosh-client 真连成功
  (UDP + 加密 + 终端流)
- 设备侧已装:deb `mosh_1.4.0-1`;`/usr/bin/mosh-server` 软链已建;
  `/dev/bpf*` 666 已进 selfheal

**剩余(明天)**:
1. `mosh/build.sh` 重跑时 exit=22 且 `tmp/mosh-src/mosh-1.4.0` 树消失——
   原因未查(build.sh 的解压分支会重下重解,幂等);重跑 build.sh 排查
2. deb 重打(最终二进制)+ README 补 mosh 章节(引用 mosh/build.sh 墙清单)
3. `tmp/mosh-progress.md`(子 agent 落盘,197 行)有 protoc/shim 细节,可提炼

## nginx:已完成/剩余

**已完成**(详细 197 行断点文档:`tmp/nginx-progress.md`,必读):
- `--crossbuild=Darwin:16.7.0:armv7`:官方机制,auto/os 走 Darwin 分支
  (kqueue 真引擎),绕过主机 uname 误判——不用改源码
- configure 需要 3 处补丁(auto/feature 的 run 探针 hook、auto/types/sizeof
  尺寸表、auto/endianness)——`nginx/crossanswer.sh` + `patch-nginx.py`
- pcre2 **私有**重建于 `~/ios-tool/nginx-src/pcre2-ios/`(28 成员 darwin
  归档)。**教训:绝不让 nginx 指向 nmap 共享源码树**——它的 make distclean
  清掉了共享树的 pcre2(见 nginx-progress.md)
- 链接成功:out 二进制 4.3MB,pcre2/zlib/openssl 静态链入,kqueue undefined
  (正确),无 epoll/sendfile;**OpenSSL4 ASN1 不透明化补丁已打**
  (ngx_event_openssl_stapling.c,同 nmap 墙)
- `nginx/build.sh`、`nginx/nginx.conf` 样例(8080)、`nginx/make-deb.sh`
  (含 postinst)均已写

**剩余(明天)**:
1. **`_setproctitle` 缺失**:error.log 显示 worker 死于它(sysroot 缺口,
   同 xlocale/assert 类)。修法:sysroot-overlay 补 setproctitle(桩:iOS
   libSystem 不导出,可 Stub 为空或从 Libc 源核实)→ worker 存活
2. deb 打包(make-deb.sh 已写)+ 设备部署(dpkg -i 用 root)+
   **mobile 会话验证**:nginx 启动(ps 应见 master/worker)+ curl
   127.0.0.1:8080 + nmap -sT 扫 8080
3. README 补章节、make-repo、commit、release(问用户:并入 batch 还是
   单独 tag)

## 手机端(Termius)连接问题——排查链与未完事项

**现象演进**(用户手机,iPhone 192.168.31.78):
1. `sh: mosh-server: command not found` —— 非交互 ssh 不读 /etc/profile;
   修法:`ln -sf /var/mobile/tools/bin/mosh-server /usr/bin/mosh-server`
   (+mosh-client 软链)。**设备侧已修好。**
2. 连上后界面卡住 → `network is unreachable`。

**排查链**(tcpdump + 进程监控 + 崩溃报告,全部实测):
- 手机向设备 60001 盲发 UDP(4ms 间隔,数千包)无回包 —— 发的是**缓存会话**
  (App 重连逻辑用记住的 IP:port:key)
- 设备侧 ps 抓不到 mosh-server 进程(监控 40 秒全 0)—— 带非交互 ssh 复现
  时 server 却存活(掩盖了问题:**非交互 ssh 不带 pty**)
- **真凶(对照实验复现)**:Termius 的 ssh 带 pty,读完 MOSH CONNECT 后关闭
  ssh 通道 → dropbear 清理整个 pty 会话进程组 → mosh-server 被杀。宿主机
  OpenSSH 同样流程不杀(对照实验:同流程 iPad alive=0 / 宿主机 alive=2)
- 修复:`mosh/patch-mosh.py` 的 **early detach**(mosh-server main 第一行
  setsid + SIGHUP ignore);上游的 fork()/exit(0) detach 不够——子进程仍在
  同组。patch 后 ssh -tt 复现:server 存活(90221)✅
- 历史干扰:早期还有一次 dyld 崩溃(崩溃报告:InternalMetadata 符号缺失,
  protobuf 静态库问题)已随重编消失;调试用的信号审计 patch 已移除

**明日验证步骤**(务必以 mobile 会话):
1. Termius 删掉旧会话条目(清掉缓存的 60001)→ 全新连接
2. 设备侧同时挂监控:`for 300s: ps mosh 进程 + tcpdump -i en0 udp
   portrange 60000-61000`——三步断点(ssh 起没起 server / UDP 到没到 /
   server 回没回)任何一步都看得见
3. 若 Termius 仍重试旧缓存:检查 App 的会话设置(有无 --server= 绝对路径
   选项:`/var/mobile/tools/bin/mosh-server new`)
4. 交互验证可用主机 mosh-client(带 tty 尺寸的 python pty 法)直连设备当前会话

## 本日通用教训(已进 docs/toolchain.md §8)

- musl 头的 Linux 值穿马甲(ioctl/_IOW、netdb NI_/AI_/EAI_)
- cc-wrapper -M/-MM 透传修复(ASCII 毒化 .o)
- **ssh 会话默认 mobile**(root 掩盖权限问题)
- **主机 Wi-Fi 接口不跑无上限 tcpdump**(iwlwifi 抓包掉线,宿主机被迫重启)
- 设备诊断命令一律限时;抓包文件写 /tmp 后即时清理

## 环境
- 工具链 env 4 行见 docs/toolchain.md §1;设备 `ssh mobile@ipad`(root 仅系统级)
- protobuf/mosh/nginx 源码树:$HOME/ios-tool/{protobuf-src,mosh-src,nginx-src}/
- nginx 的 pcre2 私有树:$HOME/ios-tool/nginx-src/pcre2-ios/
