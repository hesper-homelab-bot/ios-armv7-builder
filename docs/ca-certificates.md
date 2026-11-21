# ca-certificates4 —— 统一 CA 信任包(2026-11-21)

> 工具链通用规则见 `docs/toolchain.md`；审稿出处:第二位审稿人
> "做一个统一的 CA 证书包……投入最小、受益面最大"。

## 问题

curl/wget/git/python3/go/node 各自处理证书,而本仓库的 curl(OpenSSL 4
静态链接)**没有编译进默认信任路径**,每个运行时都要单独喂锚点:

| 运行时 | 此前姿势 | 问题 |
|---|---|---|
| curl | `SSL_CERT_FILE=/etc/ssl/cert.pem` | 手动、易忘(rc=60) |
| wget4 | 同上(env.sh,归 wget4 包) | 分散 |
| git | `http.sslCAInfo=/etc/ssl/cert.pem`(写死在 gitconfig) | 指向系统库 |
| python3 | 文档里曾有关证书验证的测试妥协 | 不可接受 |
| node/go | `SSL_CERT_FILE` 同 curl | 分散 |

系统库 `/etc/ssl/cert.pem`(iOS 10.3 时代,120 证书,不属于任何 deb)缺
现代根(ISRG X2 等),且**无更新途径**。

## 方案

`ca-certificates4` deb(纯数据 + 一个脚本,零编译):

```
/var/mobile/tools/etc/ca-certificates/ca-bundle.crt   Mozilla bundle(118 证书,2026-11-21 快照)
/var/mobile/tools/bin/update-ca-certificates          原子刷新脚本
```

- bundle 快照进 `sources.lock`(`ca-bundle` 行,sha256 钉死),构建走
  `tools/fetch-src.sh` 统一验证通道
- `update-ca-certificates`:下载 curl.se 最新 bundle → PEM 计数 ≥100 +
  首证书 openssl 解析两项 sanity → 同文件系统 `mv` 原子替换;
  **鸡生蛋防护**:下载自身用旧 bundle 锚定,失败回退系统库
- 系统 `/etc/ssl/cert.pem` **不动**(生产 sshd 等依赖它的行为不变)

## 各运行时接入(实测)

```sh
export SSL_CERT_FILE=/var/mobile/tools/etc/ca-certificates/ca-bundle.crt
git config --global http.sslCAInfo /var/mobile/tools/etc/ca-certificates/ca-bundle.crt
```

验收矩阵(2026-11-21,设备实测,全部真验证):

| 用例 | 结果 |
|---|---|
| curl + 管理的 bundle → apple.com | **200,ssl_verify_result=0** |
| curl + 系统 bundle(对照) | 200 |
| python3 `http.client` + 管理的 bundle | **200** |
| python3 + **假 bundle(README 文件)** | **SSLCertVerificationError**(负例:证明验证是真实的,不是摆设) |
| node https.get + 管理的 bundle | **200** |
| git ls-remote gitee + 管理的 bundle | **refs 正常返回** |
| update-ca-certificates 真跑 | bundle updated (118 → 118) |

## 版本

- `20261121-2`:update 脚本补鸡生蛋自举(rev1 下载时无锚,rc=60)
- bundle 滚动更新靠设备上的 `update-ca-certificates`;deb 里的快照仅
  作为初始值,sources.lock 行随每次重打包更新
