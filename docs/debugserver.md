# debugserver：iPad4 活体调试（2026-11-10 打通）

## 构成
- **设备端**：`/var/mobile/tools/debugserver`（来自 iOS 10.3 Developer Disk
  Image，fat: armv7/armv7s/arm64，13.9MB）。签名 entitlements
  （get-task-allow + task_for_pid-allow + com.apple.springboard.debugapplications）。
- **主机端**：`lldb-21`（apt，21.1.8）。
- DDI 来源（要提交的文档用镜像通道写法）：raw.githubusercontent 的
  haikieu/xcode-developer-disk-image-all-platforms 仓库
  `DiskImages/iPhoneOS.platform/DeviceSupport/10.3.zip`（15,511,009 B；
  本网络直连 raw.githubusercontent 被 SSL 干扰，**用 ghproxy.net 前缀下载**）。

## 用法
```sh
# 设备端：spawn 模式（debugserver 自己拉起目标，停在入口）
/var/mobile/tools/debugserver 0.0.0.0:1234 /var/mobile/scratch/<bin> &
# 或 attach 模式（目标先跑起来，--attach=<pid>）
/var/mobile/tools/debugserver 0.0.0.0:1234 --attach=<pid> &

# 主机端：
lldb-21 -b -o "platform select remote-ios" \
  -o "process connect connect://<device>:1234" \
  -o "bt 6" -o "register read pc sp lr r7" -o "si" -o "detach" -o "quit"
```

## 已验证（2026-11-10 实测）
- attach 运行中进程 ✓；bt 带本地符号（把未 strip 的孪生体放主机本地路径，
  lldb 自动用它符号化目标帧）✓；寄存器读 ✓；单步 `si` ✓；detach ✓。
- spawn 模式 detach 后 debugserver 退出；attach 模式 detach 后目标继续跑。

## 调试目标要求
被调试进程必须带 `get-task-allow` 签名：`ldid -S<ent.xml> <bin>`（ent 至少
`<key>get-task-allow</key><true/>`）。普通 `ldid -S`（无 entitlements）不可调。

## 设备注意事项
- 设备无 `pgrep`/`pkill`（用 `ps ax | awk` 取 pid）。
- ssh 命令外层用**单引号**，否则 `$(...)`/`$1` 被本地 shell 提前展开。
- 调完记得 kill 目标进程与 debugserver，避免残留占口。
