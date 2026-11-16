# 自编 OpenSSH 10.6p2（ossh）专项

> 22 端口的 dropbear 见 `docs/dropbear.md`；工具链通用规则见 `docs/toolchain.md`。

## 定位与形态

- **port 22226，验证口，非兜底**：用于在真实连接上验证自编 OpenSSH 10.6p2，
  不承担任何兜底职责（设备唯一的 sshd 是 22 的 dropbear）。
- 二进制在 `/var/mobile/tools/ossh-*`：`ossh-sshd` + `ossh-sshd-auth` /
  `ossh-sshd-session`（OpenSSH 10 的三分体形态），以及 `ossh-ssh`、`ossh-scp`、
  `ossh-sftp`、`ossh-ssh-keygen` 等客户端套件。
- 守护：`com.hesper.osshd`（RunAtLoad + KeepAlive）→
  `/var/mobile/.local/bin/osshd-daemon.sh`：首跑生成 host key 并常驻前台。
- 设备侧配置：`/var/mobile/ssh-openssh/`（`sshd_config` + `ssh_host_*_key`）。
- 构建要点：`--with-privsep-user=_sshd`（iOS 预留给 sshd 的非特权用户）——
  缺它 sshd 拒绝启动（"Privilege separation user sshd does not exist"）。
- 仓库侧：`openssh/{build.sh,ios-config.site,make-deb.sh,sshd_config,
  osshd-daemon.sh,osshd.plist}`。

## 构建坑：Blowfish 未定义符号（已修）

**现象**：11 个二进制引用 `_blf_enc` 等 **5 个 Blowfish 符号 undefined**
（全量符号审计 `tools/audit-all.sh` 发现）。

**根因**：真实实现在 `openbsd-compat/blowfish.c` 里，**Makefile 已列出该文件**，
但链接时没被解析。

**修法**（已完成）：

1. `ios-config.site` 里 **pin 三个 `ac_cv_func_Blowfish_*`=no**
2. **显式链接 `blowfish.o`**——而不是 `-lopenbsd-compat`
   （**ld64 不回扫档案**，`toolchain.md` §2 同族）

**结果**：14/14 二进制 `check-undefined` 全绿。

> **注意**：这条路径**加密私钥的 KDF 会走到**，所以是**优先重建**项，
> 不是冷路径。

## 已知问题

- 从主机连 22226 报 `Permission denied (publickey)`：ossh 侧
  authorized_keys/算法配置待查（不紧急）。

## 历史：老 OpenSSH 6.7p1 已卸载

系统自带的 OpenSSH 6.7p1（曾占 22，后让位后守 22222）已于 2026-11-10 卸载：
`/usr/sbin/sshd` 与其 LaunchDaemon 均已清除，22222 不复存在。它曾因占 22 造成
dropbear crash-loop 一整天无人发现（见 `docs/dropbear.md` 事故复盘）——**勿复活**。
