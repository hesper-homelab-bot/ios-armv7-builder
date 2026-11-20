# pgrep/pkill 移植专项（armv7 iOS 10.3.3）

> 包:`pgrep4_1.1-1_iphoneos-arm.deb`(1.1 = **-f 全参修复**)· 2026-11-19 初版 / 2026-11-20 修复
> OpenBSD pkill 1.44 的 Darwin 适配(单文件 ~600 行,一个二进制两个名字)

## 1. 状态

| 项 | 值 |
|---|---|
| 源 | OpenBSD `usr.bin/pkill` 1.44(BSD 许可)适配,非 procps(procps 全家依赖 /proc,Darwin 没有) |
| 数据源 | `sysctl(KERN_PROC_ALL)`(进程表)+ `KERN_PROCARGS2`(全参) |
| 安装 | `/usr/bin/pgrep` + `/usr/bin/pkill`(同二进制,argv[0] 分流) |
| 验收 | 1.0:基础匹配/击杀;1.1:`pgrep -f` 同 uid 读全 argv、跨 uid 回退 comm(见 §3) |

## 2. 平台差异(适配记录)

| OpenBSD 原文 | Darwin 适配 |
|---|---|
| kvm_openfiles/kvm_getprocs | sysctl(KERN_PROC_ALL) 两阶段(Darwin kinfo_proc 字段在 kp_proc/kp_eproc 下;**e_pcred/e_ucred 是值不是指针**,点访问) |
| kvm_getargv | `KERN_PROCARGS2` 解析(argc + padding NULs + exec_path + argv 串区) |
| -s sid | **撤下**:Darwin 的 struct eproc 无 e_sid,session id 不经 sysctl 暴露 |
| pledge() | 删(OpenBSD 专属) |
| uid_from_user/gid_from_group | getpwnam/getgrnam |

## 3. 1.1 修复:KERN_PROCARGS2 当年调用姿势错了(2026-11-20 设备复测定案)

**旧结论(1.0 时代)作废**:"PROCARGS2 连 root 也 ENOENT、节点未实现"——错。
设备自带 `/bin/ps` 一直能显示 root 进程全参,说明数据源可用;拉 Apple
`adv_cmds-163` 的 ps 源码(print.c getproclline)对出真相:

1. **正确姿势是 3 元 mib** `{CTL_KERN, KERN_PROCARGS2, pid}` + KERN_ARGMAX
   大小的缓冲。1.0 的 pgrep.c 写成了 **4 元** `{CTL_KERN, KERN_PROC,
   KERN_PROCARGS2, pid}`——把 PROCARGS2 当成 KERN_PROC 的子操作符,内核不认,
   恒失败,于是永远走 comm 回退。当年的 ENOENT 是 **v1**(KERN_PROCARGS,
   复测 errno=2 确认真缺)的,两件事被混在一起定性了。
2. **权限模型(xnu-3789 sysctl_procargsx + 设备双身份实测)**:
   - 同 uid 可读(mobile 读 SpringBoard ✓、读自己的 dropbear 会话子进程 ✓);
   - **跨 uid 必须 root**(mobile 读 root 的 dropbear 监听 = EINVAL 22;
     root 全读 ✓);
   - **死 pid 也是 EINVAL**(proc_find 失败),不是 ESRCH——跨连接引用 pid
     做测试会踩这种竞态假象,要在**同一会话内**测目标进程。
   - 非 root 下 -f 静默回退 p_comm(与上游 kvm_getargv()==NULL 同形),
     设计保持不变。
3. 1.1 验收(同会话):`pgrep -lf dropbear` → 本会话 dropbear 显示
   `/var/mobile/tools/db-dropbear -F -E -p 22 -r ...` 完整 argv,跨 uid 行
   显示 `(db-dropbear)` 回退;`pgrep -f host_ed25519`(argv 深处 token)命中 rc=0。

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `pgrep/pgrep.c` | 实现(平台差异逐条注释;getargv 含 1.1 修复注记) |
| `pgrep/build.sh` / `pgrep/make-deb.sh` | 构建 / 打包(pgrep+pkill 双名) |
| `pgrep/probe-args2.c` | PROCARGS2 复测探针(双身份,定位旧 bug 的证据) |
