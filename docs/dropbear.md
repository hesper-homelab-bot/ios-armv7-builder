# dropbear ssh 服务专项（iPad4 / iOS 10.3.3）

> 工具链/部署通用规则见 `docs/toolchain.md`；设备私有细节（真实地址等）见
> `DEVICE.md`（gitignored）与本地 `~/.ssh/config`。

## 拓扑（2026-11-10 定版）

| port | 服务 | 状态 |
|---|---|---|
| 22 | dropbear 2026.94 —— **设备上唯一的 sshd** | 常驻（`com.hesper.dropbear`） |
| 22226 | ossh-sshd（自编 OpenSSH 10.6p2） | 验证口，**非兜底**（见 `docs/openssh.md`） |
| 22222 | 老 OpenSSH 6.7p1 | 已废：2026-11-10 卸载，**勿复活**（曾占 22 酿成一天故障） |

## 守护

- `com.hesper.dropbear`（`/Library/LaunchDaemons/`）：RunAtLoad + KeepAlive，
  launchd 以约 10s 周期重试；日志 `/var/mobile/.local/dropbear-daemon.{log,err}`。
- wrapper `/var/mobile/.local/bin/dropbear-daemon.sh` 职责：
  1. 首跑生成缺失的 host key（dropbear 缺 key 会立即退出，launchd 会静默空转）；
  2. `exec db-dropbear -F -E -p 22 -r host_ed25519 -r host_rsa`（`-F` 前台
     供 launchd 监管；dropbear 自身 daemon 化则无法被 KeepAlive 看住）；
  3. `DROPBEAR_EXTRA_ARGS` 可直传额外参数（如曾经的 `-p 2222` lifeline，已停用）。
- 自愈守护 `/var/mobile/.local/bin/ssh-selfheal.sh` v2.1（`com.hesper.sshfix`，
  每 120s，root），规则原文摘录：
  - **R1** db-dropbear 正在监听 22 → 一切正常，直接退出（静默，不写日志）。
  - **R2** 22 被别的进程占着（老 sshd 等；会话子进程与 ossh-sshd 不会误伤）→
    杀掉占用者，dropbear KeepAlive ≤10s 自动绑定。
  - **R3** 端口空闲但 dropbear 没起 → `launchctl start com.hesper.dropbear` 加速拉起。
  - **R4** dropbear 二进制缺失/不可执行 → 只记录告警（已无兜底二进制，需人工修复）。
  - 日志：`/var/mobile/.local/ssh-selfheal.log`（v2.1 只在 R2/R3/R4 落行）。
    原 22222 plist 自愈逻辑（R5）随老 sshd 一并移除。

## host keys

`/var/mobile/ssh/host_{ed25519,rsa}`（ed25519 优先 + RSA-2048 兼容旧客户端；
wrapper 首跑生成，600/mobile）。换机/重生成后客户端需 `ssh-keygen -R` 一次。

## 事故复盘（selfheal v2.1 的由来）

2026-11-09 夜间设备重启后，dropbear 一直 crash-loop（"port 22 already in
use"，被一个老 sshd 进程占着 22），没有人发现；老 sshd 以 22 服务了一整天——
当天所有 `-o HostKeyAlgorithms=+ssh-rsa` 兼容参数都源于此。教训：launchd 对
crash-loop 的重试是静默的，"端口被占"这类故障没有告警就等于没有 ssh。
selfheal v2.1 保证此类情况 2 分钟内自愈。

## 连接

```sh
ssh root@<device>        # 现代算法直连，无任何兼容参数
ssh-keygen -R <device>   # host key 变更后清一次旧记录
```

`<device>` 的具体地址见 `DEVICE.md`（gitignored）或本地 `~/.ssh/config`。

## 设备侧文件

- 二进制：`/var/mobile/tools/db-{dropbear,dropbearkey,dbclient,scp,sftp-server}`
  （`WITH_DB_SFTPSERVER=1` 构建 → 带 `db-sftp-server`）。
- 仓库侧：`dropbear/{build.sh,ios-config.site,make-deb.sh,dropbear-daemon.sh,
  dropbear-daemon.plist,switch-to-22.sh}`。

## 已知问题

- 22226（osshd）从主机连接报 `Permission denied (publickey)`——ossh 侧
  authorized_keys/算法配置待查（不紧急，22 不受影响）。
