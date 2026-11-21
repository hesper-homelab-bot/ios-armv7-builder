# sources.lock — 可复现/可审计的源码下载基建

> 2026-11-21 建立。目标:任何一个 `*/build.sh` 从哪里下载源码、下载到什么
> 东西,全部登记在一个文件里,每次构建都按 sha256 校验,缓存命中时完全不碰
> 网络。

## 三个部件

| 部件 | 位置 | 作用 |
|---|---|---|
| `sources.lock` | 仓库根目录 | 唯一的源码登记簿(TSV,pkg/版本/URL/sha256) |
| `tools/fetch-src.sh` | 工具 | 唯一的下载入口:缓存→校验→落缓存 |
| `SRC_CACHE` | `tmp/src-cache/`(默认,已 gitignore) | 全部源码 tar 的统一缓存 |

缓存路径规则:`$SRC_CACHE/<pkg>/<URL 的 basename>`,例如
`tmp/src-cache/tcpdump/tcpdump-4.99.5.tar.gz`。**故意不放 /tmp** —— 宿主
的 /tmp 是小 tmpfs,node 一个包就有 ~102MB(见 AGENTS.md 规则 0)。

## sources.lock 格式

TSV,严格四列(CI 按此解析):

```
pkg <TAB> version <TAB> url <TAB> sha256
```

* 一行一个 `(包, 版本)`。被别的包的构建间接用到的源码(zlib、openssl、
  libpcap、oniguruma…)也各有自己的行 —— 间接源同样登记。
* `#` 开头是注释行:该行的消费方、备注、失效记录都写在注释里。
* 特殊 sha256 值 `ANY`:上游没有 release、只能跟分支的情况(whois、
  class-dump、gas-preprocessor),lock 行里固定到某个 commit 的归档 URL。
* 失效 URL 不改 build.sh 的行为,只在注释里标 TODO/替代 URL(例:zlib.net
  不再提供 1.3.1,已换 github tag 归档)。

build.sh 取值方式(下载点原地改造,只动下载那几行):

```sh
td_tar="$("$root/tools/fetch-src.sh" tcpdump \
    "https://www.tcpdump.org/release/tcpdump-$TD_VERSION.tar.gz" \
    "$(awk -F'\t' '$1=="tcpdump"{print $4}' "$root/sources.lock")")"
tar -C "$HOME/ios-tool/tcpdump-src" -xzf "$td_tar"
```

也可以 `read -r URL SHA <<<"$("$root/tools/fetch-src.sh" --lock tcpdump)"`
一次拿 URL+sha。两处写法等价,lock 永远是唯一事实来源。

## fetch-src.sh 用法

```sh
tools/fetch-src.sh <pkg> <url> <sha256> [dest]   # 取包:缓存命中直接用,否则下载→校验→入缓存
tools/fetch-src.sh --lock <pkg>                  # 从 lock 打印 "url sha 文件名"
tools/fetch-src.sh --check [pkg...]              # 校验缓存 vs lock(无参=全部;CI 门禁)
tools/fetch-src.sh --list                        # 列出缓存内容
```

* 缓存有且 sha256 匹配 → 直接用,零网络;
* 缓存无 → 下载到 `.part`,验 sha256,过了才改名入缓存;
* 校验失败 → 报错退出,**不静默使用**、不留坏缓存;
* `[dest]`:个别下游要固定路径时,把校验过的文件硬链过去(不复制,
  不占双倍空间)。nmap→nginx pcre2 种子包就是这么办的。

## 加一个新包 / 更新版本

1. **新包**:在 `sources.lock` 加一行(pkg/version/url/sha256),sha256 用
   `curl -fL <url> | sha256sum` 或先下载再算;下载物跑一次
   `tools/fetch-src.sh <pkg> <url> <sha256>` 让它入缓存,然后
   `tools/fetch-src.sh --check <pkg>` 确认 OK。
2. **升级版本**:改 build.sh 里的 `*_VERSION` → 下载新 tarball 算 sha256 →
   更新 lock 行的 version/url/sha256 → `--check`。旧缓存留着无害(按
   basename 区分),不需要可以手动删 `tmp/src-cache/<pkg>/`。
3. 改完必跑 `tools/fetch-src.sh --check`(全量),这是 CI 门禁。

## 当前登记范围

* 已在 lock 中:34 个源(见文件本身;含间接依赖 zlib/openssl/libpcap/
  oniguruma/protobuf/libevent/musl/e2fsprogs 与 xnu 的 net/bpf.h)。
* **不在** lock 里(有意):
  * 仓库内 vendored 源码树(iperf3/src、socat/src、ncdu/src、patch/src、
    traceroute、ping 等)——已被 git 跟踪,无需下载;
  * iPhoneOS10.3.sdk.zip(GB 级手工下载,class-dump/build.sh 引用);
  * tailscale/tailcat 的 GOPROXY Go module(构建期拉取,未 pin);
  * go 的 bootstrap 工具链($HOME/go-sdk,宿主手工安装)。
* 已知问题 URL:见 lock 内 TODO 注释与提交说明(zlib.net 404 已换 github
  归档;其余全部 200 且 sha256 已实测)。