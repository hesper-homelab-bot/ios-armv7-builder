# ios-tmux-builder 项目准则与文档索引

本项目：为 iPad4（armv7 / iOS 10.3.3）交叉编译并打包软件的仓库。
用户级协作准则见 `~/.dsh/AGENTS.md`；本文只放**本项目**的内容。

## 文档索引（正本都在本仓库 docs/，随 git 管理）

**组织方式**：每个移植包一份 `docs/<pkg>.md` 专项文档（写法见
`docs/doc-conventions.md`）。带 ★ 的是**跨包通用**或**源头性**文档。

### 通用规则（★ 新移植前必读）

| 文档 | 内容 |
|---|---|
| ★ `docs/toolchain.md` | **交叉编译总纲**：env、归档格式、thumb、原子雷区、部署验证、连接方式；19 个编号节 |
| ★ `docs/doc-conventions.md` | **专项文档怎么写**（build.sh 注释 vs docs 的分工、脱敏、取材顺序） |
| ★ `docs/porting-backlog.md` | **候选队列**：待表态 / 远期 / 判死 + 已上线包一览表 |
| `docs/debugserver.md` | 活体调试（设备 debugserver + 主机 lldb-21） |

### 语言运行时

| 文档 | 内容 |
|---|---|
| ★ `docs/python.md` | **Python 索引页**：3.13/3.14 双版本导航、重建、两个必知坑 |
| `docs/python3.md` | CPython 移植主文档（13 道墙、原子根因、全部验收） |
| `docs/node.md` | Node 22.23.4（墙列表、链接配方、JIT 判死证据链） |
| `docs/quickjs.md` | QuickJS（Phase 1） |
| `docs/libcxx-filesystem.md` | libc++ filesystem（C++ 运行时） |

### 网络与服务

| 文档 | 内容 |
|---|---|
| `docs/dropbear.md` | **设备唯一 sshd**（22 口、selfheal 守护、host keys） |
| `docs/openssh.md` | 自编 OpenSSH 10.6p2（22226 验证口） |
| `docs/nginx.md` | nginx 1.26.3（`--crossbuild` 命门、设备侧已停用） |
| `docs/mosh.md` | mosh 1.4.0（protobuf 链、五层雷、**原子问题的关键反证**） |
| `docs/tor.md` | tor 0.4.8.14（全静态栈、探针压制、两条结构性规避） |
| `docs/wget.md` | wget 1.25.0（**双签名约定的出处**） |
| `docs/curl.md` | curl 8.16.0（三坑、**签名传说真相**） |
| `docs/git.md` | git 2.51.2（手写 config.mak、Linux 宿主默认值泄漏清单） |

### 网络工具

| 文档 | 内容 |
|---|---|
| `docs/nmap.md` | nmap 7.95（**侵入性最强**，八道墙，倒逼出 sysroot 修复） |
| `docs/tcpdump.md` | tcpdump 4.99.5 + libpcap（**只在收包路径才炸的假阳性**） |
| `docs/netstat.md` | netstat 1.0（**自研**，ABI 全设备实测） |
| `docs/lsof.md` | lsof 4.99.7（libproc 路线、内核 ABI 勿手改） |
| `docs/whois.md` | whois 5.6.6（**最干净**：零探针覆盖零补丁） |
| `docs/rsync.md` | rsync 3.3.0（**探针有罪推定原则**） |

### 库与开发工具

| 文档 | 内容 |
|---|---|
| ★ `docs/openssl.md` | OpenSSL 4.0.3（带汇编；**消费者必读的链接约定**） |
| `docs/sqlite.md` | SQLite 3.54.1（**故意不跑 configure**） |
| `docs/ffmpeg.md` | FFmpeg 9.0.2（远期最大工程；SDK 模式首个大项目） |
| `docs/jq.md` | jq 1.7.1 + oniguruma（libtool 陷阱） |
| `docs/class-dump.md` | class-dump（**真实 SDK 破局**、Apple 头世界隔离） |
| `docs/uuidgen.md` | uuidgen 1.47.2（替代死掉的 BigBoss uuid） |
| `docs/make.md` | GNU make 4.4.1（设备端重建） |
| `docs/p7zip.md` | p7zip 17.05 |

### 终端与文本

| 文档 | 内容 |
|---|---|
| ★ `docs/tmux.md` | tmux 3.8（**第一个移植**，历史成因 + `libSystem.tbd` 机制） |
| ★ `docs/vim.md` | Vim 9.1（**终端类模板**，六道 WALL） |
| `docs/less.md` | less 668（curses 策略沿用） |

### 私有（不入库）

| 文档 | 内容 |
|---|---|
| `DEVICE.md` | 设备全书（英文编号节；**gitignored**，勿提交勿外发） |

## 本仓库工作规则

1. 文档改动与代码/脚本改动同仓提交；DEVICE.md 永不提交。
2. `~/scratch/node-research/BUILD-STATE.md` 是 node 的权威流水账（仓库外），
   docs/node.md 只保留**提炼后的当前状态**，细节引用流水账。
3. 设备部署一律走部署三件套 + 新文件名（见 docs/toolchain.md §5）。
3.5. **ssh 默认用 mobile**（`ssh ipad`）；root（`ssh root@ipad`）只用于
    dpkg 安装、改设备权限等系统级操作，且要在汇报里点名。理由：用户日常
    也是 mobile，root 下能跑通的探针会掩盖权限问题（/dev/bpf* 事件教训）。
4. 用户级准则若需修订 → 改 `~/.dsh/AGENTS.md`，不要在本仓库重复。
5. **新移植默认走 SDK sysroot 模式**（2026-11-15 拍板）：
   `IOS_SYSROOT=~/ios-tool/iPhoneOS10.3.sdk` + `IOS_STUBDIR=$HOME/ios-tool`。
   头用真 Apple SDK（NULL/getopt/net 系缺口根治）；`-lSystem` 锚点必须
   仍用手写 stub tbd——SDK 的 libSystem.tbd 是 re-export 壳，cctools ld64
   追设备绝对路径必炸。存量 24 包不重编（musl sysroot 产物，可复现性
   保留）。细节与金丝雀记录：docs/toolchain.md §16。
