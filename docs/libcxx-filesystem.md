# C-6：std::filesystem 26 符号补齐（libcxx-fs.a）

> 解决 link-prescan REPORT.md §C-6：设备 libc++.1.dylib（iOS 10 时代，共享缓存内）
> 完全没有 `std::filesystem`（iOS 13 才进 dylib），libnode 有 26 个
> `std::__1::__fs::filesystem::*` 符号缺失。
> 方案：用与本构建相同的 LLVM 15.0.7 头文件 + 同版本的 libc++ **源码**，把
> filesystem 实现编成静态归档，链接时只依赖设备 libc++ 已导出符号 + libSystem。
> 产物：`~/scratch/node-shims/libcxx-fs.a`（darwin 扁平归档，armv7 thumb）。

## 1. 结论速览

- 26/26 符号全部有定义（llvm-nm-21 --defined-only 逐一比对 cxx_miss.txt）。
- 归档外部未定义符号 92 个，设备侧 dlsym 全量审计：**80 个 HIT
  （44 libSystem + 20 libc++ + 16 cxa/unwind），12 个 MISS 全部是归档自身
  定义的 fs 符号**（归档内互解析，ld64 链接 NOUNDEFS 通过）。
- 设备实测 3 个探针全过：path 操作、directory_iterator、status/symlink_status、
  copy_file、remove_all、symlink 三件套、异常抛接（filesystem_error）。
- node 侧集成：**链接行加 `~/scratch/node-shims/libcxx-fs.a` 即可**，无需其它改动。

## 2. 26 个缺失符号（mangled，来自 cxx_miss.txt，cppgc 2 条不在内）

```
__ZNKSt3__14__fs10filesystem18directory_iterator13__dereferenceEv
__ZNKSt3__14__fs10filesystem4path10__filenameEv
__ZNKSt3__14__fs10filesystem4path11__root_nameEv
__ZNKSt3__14__fs10filesystem4path13__parent_pathEv
__ZNKSt3__14__fs10filesystem4path16__root_directoryEv
__ZNKSt3__14__fs10filesystem4path3endEv
__ZNKSt3__14__fs10filesystem4path5beginEv
__ZNKSt3__14__fs10filesystem4path9__compareENS_17basic_string_viewIcNS_11char_traitsIcEEEE
__ZNSt3__14__fs10filesystem10__absoluteERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem11__copy_fileERKNS1_4pathES4_NS1_12copy_optionsEPNS_10error_codeE
__ZNSt3__14__fs10filesystem12__equivalentERKNS1_4pathES4_PNS_10error_codeE
__ZNSt3__14__fs10filesystem14__copy_symlinkERKNS1_4pathES4_PNS_10error_codeE
__ZNSt3__14__fs10filesystem14__current_pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem14__read_symlinkERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem16__create_symlinkERKNS1_4pathES4_PNS_10error_codeE
__ZNSt3__14__fs10filesystem16__symlink_statusERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem18__create_directoryERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem18__weakly_canonicalERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem18directory_iterator11__incrementEPNS_10error_codeE
__ZNSt3__14__fs10filesystem18directory_iteratorC1ERKNS1_4pathEPNS_10error_codeENS1_17directory_optionsE
__ZNSt3__14__fs10filesystem20__create_directoriesERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem26__create_directory_symlinkERKNS1_4pathES4_PNS_10error_codeE
__ZNSt3__14__fs10filesystem4path17replace_extensionERKS2_
__ZNSt3__14__fs10filesystem4path8iterator11__incrementEv
__ZNSt3__14__fs10filesystem8__removeERKNS1_4pathEPNS_10error_codeE
__ZNSt3__14__fs10filesystem8__statusERKNS1_4pathEPNS_10error_codeE
```

（以上 26 条；精确机器可读清单：`~/scratch/link-prescan/cxx_miss.txt` 中含
`__fs` 的 26 行；覆盖验证脚本比对 `llvm-nm-21 --defined-only` 输出，结果 26/26。）

## 3. 源码来源与编译

- 源码：**LLVM 15.0.7** `libcxx/src/filesystem/`（与 libcxx15-headers 的
  `_LIBCPP_VERSION 15007` 同 tag `llvmorg-15.0.7`）。GitHub 直连被墙，
  用 `git clone --filter=blob:none --sparse --depth 1 --branch llvmorg-15.0.7
  https://mirrors.tuna.tsinghua.edu.cn/git/llvm-project.git` 取下
  （需 `-c http.proxy=` 绕开本机死代理，见 toolchain.md）。
  已 vendor 到 `~/scratch/node-shims/fs-src/`（含小改，见 §4）。
  - 注：LLVM 15 的 `path.cpp` 并入 `operations.cpp`（git 树里
    `libcxx/src/filesystem/` 只有 5 个文件，path 的实现在 operations.cpp）。
- 编译对象（2 个进归档）：
  - `operations.o` ← operations.cpp（path/operations/copy_file 全在这）
  - `directory_iterator.o` ← directory_iterator.cpp
  - `int128_builtins.cpp` 编出空 TU（armv7 无 __SIZEOF_INT128__），不进归档。
- 编译旗标（注意：**不能用 cxx-wrapper.sh**，原因见 §5-1）：

```sh
~/ios-tmux-builder/tools/cc-wrapper.sh \
  -nostdinc++ -isystem $HOME/ios-tool/libcxx15-headers \
  -isystem "$IOS_SYSROOT/usr/include" \
  -D_LIBCPP_DISABLE_AVAILABILITY \
  -std=gnu++20 -O2 \
  -include ~/scratch/node-shims/fs-src/fs_shim_compat_decls.h \
  -c fs-src/operations.cpp -o fs-build/operations.o
# directory_iterator.cpp 同上；然后：
llvm-ar-21 --format=darwin rc ~/scratch/node-shims/libcxx-fs.a \
  fs-build/operations.o fs-build/directory_iterator.o
```

- 与 cxx-wrapper 的差异只有一处：**去掉 `-D_LIBCPP_NO_EXCEPTIONS`**，
  保留 `-D_LIBCPP_DISABLE_AVAILABILITY`（iOS 10 上必须有，filesystem 被标
  iOS 13 availability）。目标仍是 armv7 thumb（cc-wrapper 默认 target）。

## 4. 对 vendored 源码的补丁（3 处，全部标注 `fs-shim PATCH`）

1. **copy_file 绕开 sendfile/copyfile**（operations.cpp 顶部 + copy_file_impl）：
   sysroot 自带 Linux 签名的 `<sys/sendfile.h>`，若走 `_LIBCPP_FILESYSTEM_USE_SENDFILE`
   分支会按 Linux 参数序调设备 libSystem 的 sendfile（签名不同/行为未定义）；
   `<copyfile.h>` 不在 sysroot。强制新增 `_LIBCPP_FILESYSTEM_USE_POSIXRW`
   分支：64KB read/write 循环，只依赖 unistd.h。设备实测 copy_file 正常。
2. **remove_all 的 O_DIRECTORY 陷阱**（fdopendir 失败分支）：
   本设备不认 O_DIRECTORY（sysroot 里 `#define O_DIRECTORY 0`），
   `openat(文件, O_DIRECTORY|...)` 会**成功**，随后 `fdopendir` 失败 ENOTDIR，
   LLVM 15 原版在此直接报错返回 → 文件永远删不掉 → 目录 rmdir 报 ENOTEMPTY(66)。
   补丁：fdopendir 因 ENOTDIR/ELOOP 失败时改走 unlinkat(parent, name, 0) 删文件。
   设备实测 remove_all n=3 ec=0（修复前 n=npos ec=66 且文件全部残留）。
3. **`fs_shim_compat_decls.h`**（-include 注入）：sysroot 的 unistd.h 缺
   `unlinkat` 声明（函数本身设备有，dlsym OK），补 `extern "C" int unlinkat(int,
   const char*, int);`。

## 5. ABI 问题与解法（按严重程度）

### 5-1. `-D_LIBCPP_NO_EXCEPTIONS` 使 filesystem 异常路径变成直接 abort（已修）

cxx-wrapper.sh 给所有 C++ 编译注入 `-D_LIBCPP_NO_EXCEPTIONS`（node 自己的 TU
靠它过编译）。但 LLVM 15 头文件 `__filesystem/filesystem_error.h:82-95`：

```cpp
#ifndef _LIBCPP_NO_EXCEPTIONS
void __throw_filesystem_error(...) { throw filesystem_error(...); }
#else
void __throw_filesystem_error(...) { _VSTD::abort(); }   // ← 直接 abort
#endif
```

编译出的库一进 throwing 重载（如 `fs::current_path("/nonexistent")`）就
`abort()`（SIGABRT，崩溃栈：fsprobe3 内两帧直接调 libsystem_c 的 abort，
异常机制完全没参与）。**证据**：设备上最小 throw/catch 对照（不含本归档）
正常，含归档的 throwing 探针 abort；去掉该 define 重编后同一探针全过。
⇒ 归档对象必须用 cc-wrapper 直调、不带 `-D_LIBCPP_NO_EXCEPTIONS`。
此 define 只影响本归档自己的 TU；node 侧 TU 保持原样（见 §8 遗留项）。

### 5-2. 命名空间/重整对齐（验证通过，无改动）

头文件把 filesystem 包在 `std::__1::__fs::filesystem`（`__config:663`，
`_LIBCPP_STD_VER > 14` 时 inline namespace `__fs`），与 cxx_miss.txt 的
26 符号逐字吻合；同版本源码（15.0.7）+ 同头文件编译，重整名一致。
设备 libc++ 6.0.1 的 `std::__1` 核心模板（basic_string、system_error、
shared_ptr 等）与 LLVM 15 头文件 ABI 兼容——归档引用的 20 个 std 符号
全部在设备 dylib dlsym 命中，探针含 directory_iterator（走
`shared_ptr<__dir_stream>`，即 `__shared_weak_count` 全套）实测正常。

### 5-3. 设备没有的符号一个都不留（自检方法）

设备 libc++ 不在磁盘（`/usr/lib/libc++.1.dylib` 是断链，实体在 dyld 共享缓存），
llvm-nm 对 dylib 的常规做法不可用。采用 **设备侧 dlsym 全量审计**：

```sh
# symprobe：归档 92 个未定义符号逐个 dlsym（显式句柄，不用 RTLD_DEFAULT——
# 本机老 dyld 上 RTLD_DEFAULT 全部 MISS，连 abort 都查不到，是探针方法坑）
# 顺序：libSystem.B → libc++ → libc++abi → libunwind(/usr/lib/system/)
```

结果：80 HIT / 12 MISS，12 个 MISS 全部是 `__fs::filesystem` 系
（归档自身定义，链接期 NOUNDEFS 已证）。其中关键 C 符号实测设备 libSystem
**都有**：`unlinkat、openat、fchmodat、fdopendir、dirfd、realpath、statvfs、
utimes、clock_gettime、__error、__divdi3、__stack_chk_*`，
`_Unwind_SjLj_*`（libunwind）与 `__cxa_*`（libc++abi）也全在。
无任何"设备没有的未定义符号"，dyld 不会死。

## 6. 设备验证（新文件名部署三件套：chmod 755 + chown mobile:mobile + ldid -S）

探针源码/二进制：`~/scratch/node-shims/probe/`；已部署设备
`/var/mobile/scratch/{fsprobe,fsprobe2,fsprobe3,symprobe}`（新名字，未动旧文件）。

- **fsprobe**（基础路径 + 迭代 + copy）：
  `path a/b ✓ filename=b parent_path=a exists=1 current_path ✓ dir_iter=3
  status type=2 create_dirs ec=0 copy_file ec=0 remove_all ec=0`
  （复跑时 copy_file ec=17=EEXIST 属正确语义——上次运行的目标文件还在）。
- **fsprobe2**（remove_all 专项）：修复前 `n=npos ec=66 文件全残留`；
  修复后 `remove_all n=3 ec=0`、`remove(file) ok=1`、`remove(空目录) ok=1`。
- **fsprobe3**（异常 + symlink + canonical）：
  `filesystem_error` 抛/接 ✓ `what()="filesystem error: in current_path: No
  such file or directory [\"/nonexistent_dir_xyz\"]"` ✓ `code=2` ✓ `path1()` ✓；
  copy_file 抛错带 "copy_file" ✓；create_symlink/read_symlink/copy_symlink ✓；
  equivalent ✓ absolute ✓ weakly_canonical=/private/var ✓。
- **symprobe**：见 §5-3。

## 7. node 集成方式（主 agent 收尾用）

- 链接行（libnode 链接命令）加：`~/scratch/node-shims/libcxx-fs.a`。
  位置随意（ld64 按需从归档取成员；node 4 个对象引用的 26 符号都在其中）。
- 不需要动头文件、不需要 -lc++（设备 dyld 启动时自带 libc++）。
- node 4 个调用点实测分析（`~/scratch/node-research/node-v22.23.4/src/`）：
  - node_errors.cc:545 `path(argv0).replace_extension().filename()` — 纯路径操作；
  - node_modules.cc:279-342 TraverseParent `parent_path()` — 纯路径操作；
  - node_file.cc:3138-3153 `status/symlink_status(path, error_code)` — ec 重载；
  - node_task_runner.cc:227 `std::filesystem::equivalent(root, dir)` — **throwing
    重载**（见 §8）。
- 归档未定义符号在链接后由设备 dyld 解析（同 node 现有 `-undefined
  dynamic_lookup` 模式），**无需把 libcxx-fs.a 的符号导出**。

## 8. 遗留问题 / 注意

1. **throwing fs 调用穿越 node 的 -fno-exceptions 帧**：node 自己的 TU 全部
   `-fno-exceptions`（无 unwind 表/注册）。若 node 代码走到 throwing 重载且
   系统调用报错（目前只有 node_task_runner.cc:227 的 `equivalent()`），异常
   从本归档抛出、穿过无表的 node 帧到最外层 → 行为是 std::terminate（与真
   libc++ 15 在同样代码下的行为一致，不是本归档缺陷）。`node --run` 正常路径
   （文件存在）不会触发错误分支。
2. node 自己 TU（cxx-wrapper 编译）里内联的 `__throw_filesystem_error` 仍是
   abort 版本——同上，只在 throwing 重载 + 出错时才走到；error_code 重载不受
   影响（node_file.cc 用法安全）。
3. `fs_shim_compat_decls.h` 目前只声明了 `unlinkat`；若后续往 fs-src 加源文件
   且用到其它 sysroot 缺声明的函数，按同样方式补（每个都要先设备 dlsym 验证）。
4. 归档用 `--format=darwin` 生成，成员名 basename 唯一（operations/directory_iterator
   无重名冲突）；`llvm-ar-21 t` 已验证 2 成员。

## 9. 产物清单

| 产物 | 路径 |
|---|---|
| 静态归档 | `~/scratch/node-shims/libcxx-fs.a`（114KB，darwin 扁平） |
| vendored 源码+补丁 | `~/scratch/node-shims/fs-src/`（LLVM 15.0.7 + fs-shim PATCH） |
| 编译对象 | `~/scratch/node-shims/fs-build/` |
| 兼容声明 | `~/scratch/node-shims/fs-src/fs_shim_compat_decls.h` |
| 探针（源码+二进制） | `~/scratch/node-shims/probe/`（fsprobe/fsprobe2/fsprobe3/symprobe） |
| 设备侧探针副本 | `<device>:/var/mobile/scratch/{fsprobe,fsprobe2,fsprobe3,symprobe}` |

复现/重建命令见 §3；验证方法见 §5-3、§6。
