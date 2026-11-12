# ios-tmux-builder 项目准则与文档索引

本项目：为 iPad4（armv7 / iOS 10.3.3）交叉编译并打包软件的仓库。
用户级协作准则见 `~/.dsh/AGENTS.md`；本文只放**本项目**的内容。

## 文档索引（正本都在本仓库 docs/，随 git 管理）

| 文档 | 内容 |
|---|---|
| `docs/toolchain.md` | 交叉编译工具链通用规则（env、归档、thumb、原子雷区、部署验证、连接方式） |
| `docs/node.md` | Node 22.23.4 移植专项（墙列表、链接配方、补丁、当前状态） |
| `docs/dropbear.md` | ssh 服务专项（dropbear 22、selfheal 守护、host keys） |
| `docs/openssh.md` | 自编 OpenSSH 10.6p2（22226 验证口） |
| `docs/quickjs.md` | QuickJS（Phase 1） |
| `docs/HANDOVER-nginx-mosh.md` | **明日入口**:nginx/mosh 移植交接(状态、断点、剩余) |
| `docs/debugserver.md` | 活体调试（设备 debugserver + 主机 lldb-21） |
| `DEVICE.md` | 设备全书（英文编号节；**gitignored，私有**，勿提交勿外发） |

## 本仓库工作规则

1. 文档改动与代码/脚本改动同仓提交；DEVICE.md 永不提交。
2. `~/scratch/node-research/BUILD-STATE.md` 是 node 的权威流水账（仓库外），
   docs/node.md 只保留**提炼后的当前状态**，细节引用流水账。
3. 设备部署一律走部署三件套 + 新文件名（见 docs/toolchain.md §5）。
3.5. **ssh 默认用 mobile**（`ssh ipad`）；root（`ssh root@ipad`）只用于
    dpkg 安装、改设备权限等系统级操作，且要在汇报里点名。理由：用户日常
    也是 mobile，root 下能跑通的探针会掩盖权限问题（/dev/bpf* 事件教训）。
4. 用户级准则若需修订 → 改 `~/.dsh/AGENTS.md`，不要在本仓库重复。
