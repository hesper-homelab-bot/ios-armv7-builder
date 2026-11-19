# pgrep/pkill 1.0 移植专项（armv7 iOS 10.3.3）

> 包:`pgrep4_1.0-1_iphoneos-arm.deb` · 2026-11-19 完成并设备验证
> OpenBSD pkill 1.44 的 Darwin 适配(单文件 ~600 行,一个二进制两个名字)

## 1. 状态

| 项 | 值 |
|---|---|
| 源 | OpenBSD `usr.bin/pkill` 1.44(BSD 许可)适配,非 procps(procps 全家依赖 /proc,Darwin 没有) |
| 数据源 | `sysctl(KERN_PROC_ALL)`(进程表)+ `KERN_PROCARGS2`(全参) |
| 安装 | `/usr/bin/pgrep` + `/usr/bin/pkill`(同二进制,argv[0] 分流) |
| 验收 | `pgrep -f tailscaled`/`pgrep -l dropbear`/`pkill -f` 击杀验证全通 |

## 2. 平台差异(适配记录)

| OpenBSD 原文 | Darwin 适配 |
|---|---|
| kvm_openfiles/kvm_getprocs | sysctl(KERN_PROC_ALL) 两阶段(Darwin kinfo_proc 字段在 kp_proc/kp_eproc 下;**e_pcred/e_ucred 是值不是指针**,点访问) |
| kvm_getargv | `KERN_PROCARGS2` 解析(argc + exec_path + argv 串区) |
| -s sid | **撤下**:Darwin 的 struct eproc 无 e_sid,session id 不经 sysctl 暴露 |
| pledge() | 删(OpenBSD 专属) |
| uid_from_user/gid_from_group | getpwnam/getgrnam |

## 3. 已知限制

- **`-f` 全参匹配需 root**:iOS 10 的 `KERN_PROCARGS2` 仅 root 可读
  (ENOENT 定性为该节点在 iOS 内核未实现——连 root 也 ENOENT;而设备自带
  `/bin/ps` 能显示全参,其数据源待逆向)。非 root 下 -f **静默回退 p_comm**
  (与上游 kvm_getargv()==NULL 路径同形)——按短名匹配仍可用的原因。
- KERN_PROCARGS(v1)同样 ENOENT(3 元 mib 复测过)。

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `pgrep/pgrep.c` | 实现(平台差异逐条注释) |
| `pgrep/build.sh` / `pgrep/make-deb.sh` | 构建 / 打包(pgrep+pkill 双名) |
