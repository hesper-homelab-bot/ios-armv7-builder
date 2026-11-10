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

## 已知问题

- 从主机连 22226 报 `Permission denied (publickey)`：ossh 侧
  authorized_keys/算法配置待查（不紧急）。

## 历史：老 OpenSSH 6.7p1 已卸载

系统自带的 OpenSSH 6.7p1（曾占 22，后让位后守 22222）已于 2026-11-10 卸载：
`/usr/sbin/sshd` 与其 LaunchDaemon 均已清除，22222 不复存在。它曾因占 22 造成
dropbear crash-loop 一整天无人发现（见 `docs/dropbear.md` 事故复盘）——**勿复活**。
